# **DuckDB + Unity Catalog Integration with dbt**

## **Presentation**
https://docs.google.com/presentation/d/1h0AYz4fWH1Q21IdF0OA5vLD0XqJjHwzHrkOzETmVL70/edit?slide=id.g2a663579a0a_0_22#slide=id.g2a663579a0a_0_22

## **Goal**

Integrate DuckDB with Unity Catalog using dbt for automated data transformation and writing.

---

## **Why This Integration?**

### **Why DuckDB?**
- **In-process analytical database** optimized for **fast query execution**.
- **Fast**, **open-source**, and **easy to set up**.

### **Why Unity Catalog?**
- **DuckDB** lacks governance and lineage features and is a **single-user database**.
- **Unity Catalog** provides centralized governance, including:
  - **Access Controls**
  - **Data Lineage**
  - **Row-Level Security (RLS)** for table security, findability, and traceability.

### **Why dbt?**
- **Automate** data transformation and writing processes for efficiency.

---

## **What is Unity Catalog?**
- **Released in June 2024**, it's the **open-source version** of **Databricks Unity Catalog**.
- **Structure**: Catalog → Schema → Table.
- Currently at **Version 0.2** with some missing features and potential issues.

---

## **Project Plan - Current**

### **Step 1: Build Unity-Catalog Container**
- The idea behind this setup is having a quick DB/DWH with data governance. Normally, DuckDB provides a fast and easy-to-build DWH but it does not have any data governance. Now, thanks to Unity Catalog, it is possible to create users and give users permission to certain tables, schemas, etc. Query users can log in through Unity Catalog (which will prompt them to Google authentication). After they authenticate, the user will get their token. When these users connect to Unity Catalog through DuckDB with their token, they will only be able to see the tables they have permission to.
- Unity Catalog stores metadata of the tables in place and this metadata addresses the location of each table. If there is a table in that location, that table can be queried through the data governance layer of Unity Catalog. It is crucial to have unity catalog running on container due to its implementation and reachability

### **Step 2: Build dbt Container*
- Unity Catalog is limited in terms of writing operations. So to write the data to unity catalog additional layer is needed. dbt provides this with  duckdb-dbt module. By using this it module it is possible to write metadata of tables to Unity Catalog while at the same time writing tables in Delta format to a specific location. This is crucial because Unity Catalog needs metadata and physical location info of tables to allow querying.
- It is only logical to have dbt running on its container as well. As we want dbt to write metadata to Unity Catalog, dbt needs the endpoint of Unity Catalog. With a Docker setup, when they are in the same network, dbt can easily reach Unity Catalog's endpoint. dbt also gets access to write to Azure Blob Storage through provided credentials during compose up(optional—if a local folder is chosen as the storage location, dbt doesn't need credentials to write to Azure).

### **Step 3: Query with DuckDB (UI or CLI)**
- Unity Catalog is only a catalog—so even if you have all the tables you want in it with proper permissions, you still need a convenient way to query them. That's where DuckDB comes in. You attach Unity Catalog (with the user token) to DuckDB, and then you can query the tables easily using DuckDB's interface.
#

### Docker Plan

![Project Plan - Azure](/images/dockersetup.png)



---




## **Project Plan (Azure) - WIP**

### Azure Environment Plan

![Project Plan - Azure](/images/azuresetup.png)

## **Final Outcome**
- **Automated data transformation** and writing to Unity Catalog using **DuckDB** and **dbt**.
- Ability to **query tables** with DuckDB while ensuring **user permissions** via Unity Catalog.
- **User Interface (UI)** for catalog management, lineage, and user management.
- **Dockerized environment** for easy setup.
- **IAS for initial setup** implementation will be easy with whole infrastructure pre-coded

