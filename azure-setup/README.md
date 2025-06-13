# **Azure Container Set up**

To deploy and enhance the previously mentioned Docker container setup, I used Azure environment. Leveraging its resources like :

- **Azure Container Instances (ACI)**: Hosts UC server, Permissions Manager, & on-demand dbt jobs.
- **Azure Files**: Persistent storage for UC metadata & dbt project files.
- **Azure Data Lake Storage (ADLS Gen2)**: Stores dbt-transformed Delta tables.
- **Azure Container Registry (ACR)**: Manages custom Docker images (UC, dbt, Permissions UI).
- **Azure Key Vault**: Securely stores application secrets (storage keys, UC tokens).
- **Azure Functions**: Automates scheduled dbt job execution via ACI.
- **User-Assigned Managed Identity (UAMI)**: Provides secure, credential-less Azure AD auth for services.

---

## **How Everything works?**
The Unity Catalog server runs continuously in an ACI, its state persisted on Azure Files. This UC server ACI also hosts a simple Streamlit application I developed, which uses the Unity Catalog Python SDK to provide a UI for managing user permissions within UC. 

Data transformation is handled by dbt running in a separate, temporary ACI. This dbt job container is orchestrated by an Azure Function, typically triggered on a schedule. The Function retrieves necessary configurations and secrets from Key Vault, then deploys the dbt ACI. During its run, the dbt container (using its specialized dbt-duckdb plugin) processes data, writes the resulting tables to ADLS, and crucially, registers or updates the metadata for these tables in the persistent Unity Catalog server ACI. Once the dbt job completes, its ACI is terminated to optimize costs.

The deployment process is  automated with shell scripts and Bicep for Infrastructure as Code. 

## **How to Use It?**

**1. Clone Repository:**

Clone this repository to a desired folder

**2. Fill input parameters inside main.sh :**

You have to fill in following parameters:
- Resource Group: Either give existing Resource Group or it will create this Resource Group for you.
- Location: Input your location
- Project Name: All there resource will use this name to be created, so before running the script make sure that this project name is unique. for example : your_project_name_aci, your_project_name_acr ...
![Project Plan - Azure](/images/azuresetup-parameters.png)

**3. Develop Your dbt Project :**

Develop your project and  put it on the folder: 'dbt-project' (do not change the name of the folder). 

In the dbt project make sure profiles.yml stayed as is. And you filled the catalog name and schema name in the dbt_project.yml.


**4. Adjust the schedule on function.py:**

Go to function_app.py inside the function folder. Edit the scheduler of dbt job. Currently it is set to 9 am as default.

**5. Run main.sh :**

You just have run main sh in terminal all resources will be created along with uploading/building necessary files/images etc. Keep in mind that before running the script. You should already be logged in to Azure Environment with a user that has permission of User Access Manager and Contributor to the subscription.

## **After Deployment**

After the main.sh deployment is finished. You should have everything up and running. You can already see Unity Catalog Container in the Azure container Instance with the name unity_catalog_container.

You can go into the create Azure Function App and trigger in manually to run your dbt job. This would create the dbt container and run the dbt  and then terminate the said container.


### **Querying**
After writing the data you can install and use duckdb/duckdb ui to connect and query unity catalog with running following lines:


INSTALL delta; INSTALL uc_catalog; -- If not already installed
LOAD delta; LOAD uc_catalog;

CREATE SECRET  (
      TYPE UC,
      TOKEN '',
      ENDPOINT 'http://unity-catalogz:8080');

(unity or whatever your catalog name is)
ATTACH 'unity' AS unity (TYPE UC_CATALOG);

You will see catalog with all schemas and tables on the left side. And now you can use query it as you wish




