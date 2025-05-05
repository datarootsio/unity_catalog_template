#!/bin/bash
set -e

echo "Starting FastAPI service (Uvicorn) in background..."
# Run Uvicorn with reload disabled for production/container use
uvicorn uc_service:app --host 0.0.0.0 --port 8000 &

echo "Starting Streamlit service in foreground..."
# Run Streamlit headless, binding to all interfaces
# Using --server.runOnSave=false might save some resources if not needed
streamlit run uc_streamlit.py --server.port 8501 --server.address 0.0.0.0 --server.headless true --server.runOnSave false --server.enableCORS false --server.enableXsrfProtection false

echo "Services stopped." # This might only be reached if Streamlit exits