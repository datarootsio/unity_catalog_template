# **Docker Container Set up**

This is the initial setup of the project with docker containers. Goal is having on-premise lightweight DWH/DB with governance using open-source tools.

Components
- **Unity Catalog (Docker)**: Metadata, Governance, Auth.
- **dbt + dbt-duckdb-uc (Docker)**: Transformation, register tables in UC, write Delta tables. Uses Admin Token.
- **Delta Tables (Can be local or cloud)**: Storage format.
- **UC CLI (Docker)**: Required for Admin (user mgmt) and User (token generation via browser auth). 
- **DuckDB CLI/UI (Local)**: Query engine, connects to UC using User Token.

---
## **How Everything works?**
The core data flow is as follows: dbt uses a specialized plugin within its dbt-duckdb adapter to process raw data. It transforms this data and prepares to write the output (as Delta tables) to a designated storage location (cloud-based or on-premise). Simultaneously, this plugin interacts directly with the Unity Catalog server. It registers the table's metadata into Unity Catalog. This integration is vital because the metadata in Unity Catalog must exactly match the physical data.

Once the data is written to its storage location and its metadata is registered in Unity Catalog by dbt, DuckDB (via its UC extension) can connect to Unity Catalog. This allows end users to query the tables through the governed namespace, simplifying data access, especially with tools like the DuckDB UI.

This containerized setup, thanks to the dbt plugin's capabilities, provides a simple yet effective demonstration of how Unity Catalog's strengths can be leveraged, with dbt automating both the data transformation and the metadata registration into the catalog.

---
## **How to Use It?**

**1. Clone Repository:**

Clone this repository to a desired folder

**2. Fill input parameters inside compose.yml :**

You have to adjust the 'STORAGE_PATH' parameter inside the compose.yml to your liking. 

Note: Critical thing with storage path is in order for the setup to work, you have to write the path to these three locations:
![Project Plan - Azure](/images/storage_paths.png)

If you were to use Azure(With current setup only Azure is supported), fill 'STORAGE_PATH' parameter as:

"abfs[s]://<file_system>@<account_name>.dfs.core.windows.net/<path>"

Then you should create .env file and write following properties of Azure app you created that has access to the storage location you will use inside Azure:

- AZURE_STORAGE_ACCOUNT='_'
- AZURE_STORAGE_CLIENT_ID='_'
- AZURE_STORAGE_CLIENT_SECRET='_'
- AZURE_STORAGE_TENANT_ID='_'



Additionally, As default auth properties will be off. But if you want to use them go to uc-cong/server.properties and fill in the parts according to here : https://docs.unitycatalog.io/server/auth/


**3. Develop Your dbt Project :**

Develop your project and  put it on the folder: 'dbt-project' (do not change the name of the folder). 

In the dbt project make sure profiles.yml stayed as is. And you filled the catalog name and schema name in the dbt_project.yml.


**4. Compose up :**

Run docker-compose up in terminal it should automatically get both dbt container and unity catalog container up and running. 

---

## **After Deployment**

Unity Catalog Container will be running on "http://localhost:8080/" and you can the ui in "http://localhost:3000/"


You can run the dbt job with :

write here the cmd


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



