import sys
print(f"Python executable: {sys.executable}")

from fastapi import FastAPI, HTTPException
from unitycatalog.client import ApiClient, Configuration
from unitycatalog.client.api import catalogs_api, grants_api
from unitycatalog.client.models import permissions_change, privilege, update_permissions
from unitycatalog.client.models.securable_type import SecurableType
from prettytable import PrettyTable
import asyncio
import subprocess


app = FastAPI()


def ptable(result):
    print_table = PrettyTable(['PRINCIPAL', 'PRIVILEGES'])
    for assignment in result.privilege_assignments:
        principal = assignment.principal
        privileges = [p.value for p in assignment.privileges]
        print_table.add_row([principal, str(privileges)])
    return print_table


def get_admin_token():
    try:
        with open("etc/conf/token.txt") as token_file:
            return token_file.read().strip()
    except FileNotFoundError:
        print("Token file not found!")
        return None
    except Exception as e:
        print(f"Error reading token file: {e}")
        return None



def get_api_client():
    token = get_admin_token()
    auth_header = f"Bearer {token}"
    config = Configuration(host="http://Localhost:8080/api/2.1/unity-catalog")
    api_client = ApiClient(configuration=config, header_name="Authorization", header_value=auth_header)
    return api_client


@app.get("/list_grants/{stype}/{securable_full_name}")
async def list_grants_endpoint(stype: str, securable_full_name: str):
    try:
        api_client = get_api_client()
        grant_client = grants_api.GrantsApi(api_client)
        result = await grant_client.get(securable_type=stype, full_name=securable_full_name)
        table = ptable(result)
        return {"table": table.get_string()}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/grant/{stype}/{securable_full_name}/{principal}/{permissions_str}")
async def grant_endpoint(stype: str, securable_full_name: str, principal: str, permissions_str: str):
    try:
        api_client = get_api_client()
        grant_client = grants_api.GrantsApi(api_client)

        permissions = permissions_str.split(",")
        privilege_enums = []
        for perm in permissions:
            try:
                privilege_enums.append(getattr(privilege.Privilege, perm.strip()))
            except AttributeError:
                raise ValueError(f"Invalid privilege: {perm}")

        permission_list = permissions_change.PermissionsChange(
            principal=principal, add=privilege_enums, remove=[])
        permission_updates = update_permissions.UpdatePermissions(changes=[permission_list])

        # Use the SecurableType enum for stype
        if stype.upper() == "CATALOG":  # Comparing string with uppercase
            securable_type_enum = SecurableType.CATALOG
        elif stype.upper() == "SCHEMA":
            securable_type_enum = SecurableType.SCHEMA
        elif stype.upper() == "TABLE":
            securable_type_enum = SecurableType.TABLE
        else:
            raise ValueError(f"Unsupported securable type: {stype}")

        await grant_client.update(
            securable_type=securable_type_enum,
            full_name=securable_full_name,
            update_permissions=permission_updates)

        return {"message": "Permissions Granted"}

    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# --- REVOKE ENDPOINT ---
@app.get("/revoke/{stype}/{securable_full_name}/{principal}/{permissions_str}")
async def revoke_endpoint(stype: str, securable_full_name: str, principal: str, permissions_str: str):
    print(f"(Service) Received revoke request: type={stype}, name={securable_full_name}, principal={principal}, perms={permissions_str}") # Added log
    try:
        api_client = get_api_client()
        grant_client = grants_api.GrantsApi(api_client)

        permissions_to_revoke = permissions_str.split(",")
        privilege_enums_to_revoke = []
        invalid_perms = []
        for perm in permissions_to_revoke:
            perm_clean = perm.strip().upper()
            if not perm_clean: continue # Skip empty strings
            try:
                privilege_enums_to_revoke.append(getattr(privilege.Privilege, perm_clean))
            except AttributeError:
                invalid_perms.append(perm)

        if invalid_perms:
             raise HTTPException(status_code=400, detail=f"Invalid privilege(s) to revoke: {', '.join(invalid_perms)}")
        if not privilege_enums_to_revoke:
             raise HTTPException(status_code=400, detail="No valid permissions provided to revoke.")

        permission_list = permissions_change.PermissionsChange(
            principal=principal, add=[], remove=privilege_enums_to_revoke) # Key change: remove list
        permission_updates = update_permissions.UpdatePermissions(changes=[permission_list])

        # Determine SecurableType enum
        try:
            securable_type_enum = SecurableType[stype.upper()]
        except KeyError:
             raise HTTPException(status_code=400, detail=f"Invalid securable type: {stype}")

        await grant_client.update(
            securable_type=securable_type_enum,
            full_name=securable_full_name,
            update_permissions=permission_updates)

        print("(Service) Successfully revoked permissions.") # Added log
        return {"message": "Permissions Revoked"}

    except Exception as e:
        print(f"(Service) Error in revoke_endpoint: {e}") # Added log
        raise HTTPException(status_code=500, detail=f"Failed to revoke permissions: {str(e)}")