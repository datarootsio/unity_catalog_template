# **DuckDB + Unity Catalog Integration with dbt**

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

## **Project Plan**

### **Step 1: Set-up DuckDB**
- **Install and configure** DuckDB for data processing.

### **Step 2: Set-up dbt Core**
- **Connect dbt Core** to DuckDB as an adapter for data transformation.

### **Step 3: Unity Catalog Integration**
- **Use DuckDB’s Unity Catalog Extension**  
  *(Note: Currently does not support writing directly to Unity Catalog)*.

---

## **Workaround for Writing to Unity Catalog**

Since **direct writing** isn't supported yet, follow these steps:

1. **Create metadata** for the table in Unity Catalog.
2. **Write data** to the corresponding folder in the storage location.

### **Options for Writing**:
- **SparkSQL**
- **PySpark**
- **CLI**
- **UnityCatalog Python library**  
  *(Currently unreliable, as it doesn’t create the necessary folder, making it unreadable by DuckDB)*.

---

## **Final Outcome**
- **Automated data transformation** and writing to Unity Catalog using **DuckDB** and **dbt**.
- Ability to **query tables** with DuckDB while ensuring **user permissions** via Unity Catalog.
- **User Interface (UI)** for catalog management, lineage, and user management.
- **Dockerized environment** for easy setup.
- 
