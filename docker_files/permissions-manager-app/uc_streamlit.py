import streamlit as st
import requests

# Constants - Replace with your service URL
BASE_URL = "http://localhost:8000"  # Default FastAPI port

# --- Helper Function to make API calls ---
def make_api_call(endpoint_url):
    """Makes a GET request and handles common errors."""
    try:
        print(f"(Streamlit) Calling: {endpoint_url}") # Log the call
        response = requests.get(endpoint_url)
        response.raise_for_status()  # Raise HTTPError for bad responses (4xx or 5xx)
        print(f"(Streamlit) Response Status: {response.status_code}") # Log success status
        return response.json()
    except requests.exceptions.ConnectionError:
        st.error(f"Connection Error: Could not connect to the service at {BASE_URL}. Is the service running?")
        return None
    except requests.exceptions.Timeout:
        st.error("Request timed out. The service might be taking too long to respond.")
        return None
    except requests.exceptions.HTTPError as e:
        # Try to get detail from the JSON response if available
        detail = e.response.text # Default to raw text
        try:
            detail = e.response.json().get('detail', detail)
        except requests.exceptions.JSONDecodeError:
            pass # Keep raw text if JSON parsing fails
        st.error(f"Service Error ({e.response.status_code}): {detail}")
        return None
    except requests.exceptions.RequestException as e:
        st.error(f"An unexpected request error occurred: {e}")
        return None
    except Exception as e:
        st.error(f"An unexpected error occurred in Streamlit: {e}")
        return None

# Streamlit app
st.title("Unity Catalog Permissions Manager")

# ------------------ List Permissions UI ------------------
st.header("List Permissions")
list_cols = st.columns(2)
with list_cols[0]:
    stype_list = st.selectbox("Securable Type", ["catalog", "schema", "table"], key="list_stype")
with list_cols[1]:
    securable_full_name_list = st.text_input("Securable Full Name", key="list_name", placeholder="e.g., unity or unity.default")

list_button = st.button("List Permissions", key="list_button")

if list_button:
    if not securable_full_name_list:
        st.warning("Please enter the Securable Full Name.")
    else:
        endpoint = f"{BASE_URL}/list_grants/{stype_list}/{securable_full_name_list}"
        data = make_api_call(endpoint)
        if data and "table" in data:
            # Use st.text to display preformatted table string from PrettyTable
            st.text(data["table"])
        # Error handling is done within make_api_call

# ------------------ Grant Permissions UI ------------------
st.header("Grant Permissions")
grant_cols = st.columns(2)
with grant_cols[0]:
    stype_grant = st.selectbox("Securable Type", ["catalog", "schema", "table"], key="grant_stype")
    principal_grant = st.text_input("Principal", key="grant_principal", placeholder="e.g., user@example.com or group_name")
with grant_cols[1]:
    securable_full_name_grant = st.text_input("Securable Full Name", key="grant_name", placeholder="e.g., unity or unity.default")
    permissions_grant = st.text_input("Permissions to Grant", key="grant_perms", placeholder="Comma-separated, e.g., USE_CATALOG, CREATE_TABLE")

grant_button = st.button("Grant Permissions", key="grant_button")

if grant_button:
    if not all([securable_full_name_grant, principal_grant, permissions_grant]):
        st.warning("Please fill in all fields for granting permissions.")
    else:
        permissions_list_grant = [p.strip().upper() for p in permissions_grant.split(",") if p.strip()]
        if not permissions_list_grant:
             st.warning("Please enter at least one permission to grant.")
        else:
            permissions_str_grant = ",".join(permissions_list_grant)
            endpoint = f"{BASE_URL}/grant/{stype_grant}/{securable_full_name_grant}/{principal_grant}/{permissions_str_grant}"
            data = make_api_call(endpoint)
            if data and "message" in data:
                st.success(data["message"])
            # Error handling is done within make_api_call

# ------------------ Revoke Permissions UI ------------------
st.header("Revoke Permissions")
revoke_cols = st.columns(2)
with revoke_cols[0]:
    stype_revoke = st.selectbox("Securable Type", ["catalog", "schema", "table"], key="revoke_stype")
    principal_revoke = st.text_input("Principal", key="revoke_principal", placeholder="e.g., user@example.com or group_name")
with revoke_cols[1]:
    securable_full_name_revoke = st.text_input("Securable Full Name", key="revoke_name", placeholder="e.g., unity or unity.default")
    permissions_revoke = st.text_input("Permissions to Revoke", key="revoke_perms", placeholder="Comma-separated, e.g., SELECT, MODIFY")

revoke_button = st.button("Revoke Permissions", key="revoke_button")

if revoke_button:
    if not all([securable_full_name_revoke, principal_revoke, permissions_revoke]):
        st.warning("Please fill in all fields for revoking permissions.")
    else:
        permissions_list_revoke = [p.strip().upper() for p in permissions_revoke.split(",") if p.strip()]
        if not permissions_list_revoke:
             st.warning("Please enter at least one permission to revoke.")
        else:
            permissions_str_revoke = ",".join(permissions_list_revoke)
            endpoint = f"{BASE_URL}/revoke/{stype_revoke}/{securable_full_name_revoke}/{principal_revoke}/{permissions_str_revoke}"
            data = make_api_call(endpoint)
            if data and "message" in data:
                st.success(data["message"])
            # Error handling is done within make_api_call