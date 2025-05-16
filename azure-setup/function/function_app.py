import logging
import os
import json
import datetime
from pathlib import Path
import azure.functions as func
from azure.identity import DefaultAzureCredential, ManagedIdentityCredential
# Only need ACI and Resource clients now
from azure.mgmt.containerinstance import ContainerInstanceManagementClient, models as AciModels
from azure.mgmt.resource import ResourceManagementClient
from azure.core.exceptions import HttpResponseError
from azure.keyvault.secrets import SecretClient

SCRIPT_DIR = Path(__file__).parent.absolute()
app = func.FunctionApp()

# === Authentication Helper ===
def get_azure_credential():
    managed_identity_client_id = os.environ.get("AZURE_CLIENT_ID") # Function App's UAMI Client ID
    if managed_identity_client_id:
        logging.info(f"Using ManagedIdentityCredential with Client ID: {managed_identity_client_id}")
        return ManagedIdentityCredential(client_id=managed_identity_client_id)
    else:
        logging.info("AZURE_CLIENT_ID not set, using DefaultAzureCredential (likely System-Assigned MI).")
        return DefaultAzureCredential()

# === Main Timer Function ===
@app.function_name(name="dbtOrchestratorTimer")
@app.timer_trigger(schedule="0 0 7 * * *", # 7 AM UTC daily
                   arg_name="myTimer", run_on_startup=False, use_monitor=True)
def timer_trigger_handler(myTimer: func.TimerRequest) -> None:
    utc_timestamp = datetime.datetime.utcnow().replace(tzinfo=datetime.timezone.utc).isoformat()
    if myTimer.past_due: logging.warning('The timer is past due!')
    logging.info('Python timer trigger function ran at %s', utc_timestamp)

    try:
        # --- Simplified Configuration ---
        config = {
            "SUBSCRIPTION_ID": os.environ.get("AZURE_SUBSCRIPTION_ID"),
            "RESOURCE_GROUP": os.environ.get("RESOURCE_GROUP"),
            "LOCATION": os.environ.get("LOCATION"), # Needed for deployment
            "ACR_LOGIN_SERVER": os.environ.get("ACR_LOGIN_SERVER"), # Passed from main.sh
            "STORAGE_ACCT_NAME": os.environ.get("STORAGE_ACCT_NAME"), # Passed from main.sh
            "DBT_PROJECT_FILE_SHARE_NAME": os.environ.get("DBT_PROJECT_FILE_SHARE_NAME"), # Passed from main.sh
            "DELTA_CONTAINER_NAME": os.environ.get("DELTA_CONTAINER_NAME"), # Passed from main.sh
            "ACI_SUBNET_ID": os.environ.get("ACI_SUBNET_ID"), # <-- Add this line
            # Using pre-compiled JSON approach
            "DBT_JOB_JSON_FILE_NAME": os.environ.get("DBT_JOB_JSON_FILE_NAME", "dbt-job.json"),
            "UAMI_RESOURCE_ID": os.environ.get("UAMI_RESOURCE_ID"), # Passed from main.sh
            "UC_ACI_NAME": os.environ.get("UC_ACI_NAME"), # Passed from main.sh
            "UC_TOKEN_FILE_PATH": os.environ.get("UC_TOKEN_FILE_PATH"), # Path within UC ACI
            "DBT_COMMAND": os.environ.get("DBT_COMMAND", "build"),
            "DBT_MEMORY_GB": int(os.environ.get("DBT_MEMORY_GB", "1")), # Needs to be INT
            "DBT_CPU_CORES": int(os.environ.get("DBT_CPU_CORES", "1")), # Needs to be INT
            "KEY_VAULT_URI": os.environ.get("KEY_VAULT_URI"), # <-- Read Vault URI
            "DBT_STORAGE_KEY_SECRET_NAME": os.environ.get("DBT_STORAGE_KEY_SECRET_NAME", "dbt-storage-account-key"), # <-- Read Secret Name
            "UC_ADMIN_TOKEN": os.environ.get("UC_ADMIN_TOKEN", "uc-admin-key"), # <-- Read Secret Name
           
             # Only include if really needed for mount and passed securely
           # "STORAGE_ACCOUNT_KEY": os.environ.get("STORAGE_ACCOUNT_KEY")
        }
        missing_vars = [k for k, v in config.items() if not v]
        if missing_vars:
             raise ValueError(f"Missing required environment variables: {', '.join(missing_vars)}")

        credential = get_azure_credential()
        resource_client = ResourceManagementClient(credential, config["SUBSCRIPTION_ID"])
        aci_client = ContainerInstanceManagementClient(credential, config["SUBSCRIPTION_ID"])
        secret_client = SecretClient(vault_url=config["KEY_VAULT_URI"], credential=credential)
        
        # Get the storage account key from Key Vault
        storage_account_key = None
        # Create the Key Vault Secret Client
        retrieved_secret = secret_client.get_secret(config["DBT_STORAGE_KEY_SECRET_NAME"])
        storage_account_key = retrieved_secret.value # Get the actual secret value
        if not storage_account_key:
            raise ValueError("Retrieved secret value from Key Vault is empty.")
        
        # Get the admin token from the Key Vault
        admin_token = None
        # Create the Key Vault Secret Client
        retrieved_secret = secret_client.get_secret(config["UC_ADMIN_TOKEN"])
        admin_token = retrieved_secret.value # Get the actual secret value
        if not admin_token:
            raise ValueError("Retrieved secret value from Key Vault is empty.")
        

        # --- Step 1: Get UC ACI FQDN ---
        logging.info(f"Retrieving Public FQDN for UC ACI '{config['UC_ACI_NAME']}'...")
        try:
            uc_aci_instance = aci_client.container_groups.get(config["RESOURCE_GROUP"], config["UC_ACI_NAME"])
            uc_aci_fqdn = uc_aci_instance.ip_address.fqdn if uc_aci_instance.ip_address else None
            if not uc_aci_fqdn: raise ValueError("Failed to retrieve Public FQDN for UC ACI.")
            logging.info(f"UC ACI Public FQDN: {uc_aci_fqdn}")
        except Exception as e:
            logging.error(f"Failed to get UC ACI FQDN: {e}")
            raise

        # --- Step 2: Retrieve Token from UC ACI ---
        logging.info(f"Retrieving UC token from {config['UC_ACI_NAME']} via SDK exec...")
        uc_token_value = None
        try:
            uc_token_value = admin_token # Use the admin token from Key Vault
            if not uc_token_value: raise ValueError("Token not found in exec response.")
            logging.info("UC Token retrieved successfully.")
        except Exception as e:
            logging.error(f"Failed to execute command on UC ACI or retrieve token: {e}")
            raise

        # --- Step 3: Load Pre-compiled ARM Template ---
        logging.info(f"Loading ARM template: {config['DBT_JOB_JSON_FILE_NAME']}")
        json_template_path = SCRIPT_DIR / config["DBT_JOB_JSON_FILE_NAME"]
        if not json_template_path.is_file(): raise FileNotFoundError(f"ARM template not found: {json_template_path}")
        arm_json_template = None
        try:
            with open(json_template_path, 'r') as f: arm_json_template = json.load(f)
        except Exception as e:
            logging.error(f"Failed to load/parse ARM template: {e}")
            raise
        if not arm_json_template: raise ValueError("ARM template is empty.")

        # --- Step 4: Construct Parameters for dbt job ---
        job_instance_name = f"dbt-job-{int(datetime.datetime.utcnow().timestamp())}"
        uc_server_url = f"http://{uc_aci_fqdn}:8080"
        # Construct storage path (assuming container/account names are from config)
        storage_path = f"abfss://{config['DELTA_CONTAINER_NAME']}@{config['STORAGE_ACCT_NAME']}.dfs.core.windows.net/delta-tables"

        arm_parameters = {
             "dbtJobInstanceName": {"value": job_instance_name},
             "acrLoginServer": {"value": config["ACR_LOGIN_SERVER"]},
             # Omit acrUsername/acrPassword if using MI pull
             "uamiResourceId": {"value": config["UAMI_RESOURCE_ID"]},
             "subnetId": {"value": os.environ.get("ACI_SUBNET_ID")}, # Get Subnet ID from env vars too
             "location": {"value": config["LOCATION"]},
             "dbtProjectStorageAccountName": {"value": config["STORAGE_ACCT_NAME"]},
             "storageAccountKey": {"value": storage_account_key}, # <-- Use fetched key
             "subnetId": {"value": config["ACI_SUBNET_ID"]}, # <-- Ensure this uses the config value
             "dbtProjectFileShareName": {"value": config["DBT_PROJECT_FILE_SHARE_NAME"]},
             "ucAdminTokenValue": {"value": uc_token_value},
             "ucServerUrl": {"value": uc_server_url},
             "storagePath": {"value": storage_path},
             "dbtCommandToRun": {"value": config["DBT_COMMAND"]},
             "memoryInGB": {"value": config["DBT_MEMORY_GB"]},
             "cpuCores": {"value": config["DBT_CPU_CORES"]}
        }


        # Add ACR creds if needed
        # if config.get("ACR_PASSWORD"):
        #     arm_parameters["acrUsername"] = {"value": config.get("ACR_USERNAME")}
        #     arm_parameters["acrPassword"] = {"value": config.get("ACR_PASSWORD")}


        # --- Step 5: Deploy dbt Job ACI ---
        deployment_name = f"dbt-job-deploy-{job_instance_name}"
        deployment_properties = {'mode': 'Incremental', 'template': arm_json_template, 'parameters': arm_parameters}
        logging.info(f"Submitting ARM deployment '{deployment_name}'...")
        try:
            poller = resource_client.deployments.begin_create_or_update(
                 config["RESOURCE_GROUP"], deployment_name, {'properties': deployment_properties}
            )
            logging.info(f"Waiting for deployment '{deployment_name}'...")
            final_deployment_state = poller.result() # Wait for completion
            logging.info(f"Deployment completed with state: {final_deployment_state.properties.provisioning_state}")
            if final_deployment_state.properties.provisioning_state != "Succeeded":
                 # Simplified error reporting, enhance if needed
                 raise Exception(f"Deployment failed: {final_deployment_state.properties.error}")
        except HttpResponseError as deployment_error:
            logging.error(f"ARM Deployment failed: {deployment_error}")
            # Attempt to get more details if possible
            try:
                 error_info = deployment_error.model.error.details if deployment_error.model and deployment_error.model.error else "No details"
                 logging.error(f"Deployment error details: {error_info}")
            except Exception:
                 pass # Ignore errors getting more details
            raise deployment_error # Re-raise original error
        except Exception as e:
            logging.error(f"An unexpected error occurred during deployment submission/polling: {e}")
            raise

        logging.info("--- dbt Job ACI Deployment Submitted Successfully ---")

    except Exception as e:
        logging.exception(f"An error occurred during function execution: {e}")
        raise # Ensure Functions runtime knows it failed

    logging.info(f"Python timer trigger function finished at {datetime.datetime.utcnow().replace(tzinfo=datetime.timezone.utc).isoformat()}")