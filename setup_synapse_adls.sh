#!/bin/bash

set -e  # Exit immediately if a command fails

echo "======================================="
echo " Azure Synapse + ADLS Gen2 Setup Script"
echo "======================================="

# -----------------------------
# CORE CONFIG
# -----------------------------
SUBSCRIPTION_ID="actual_subscription_id"
RESOURCE_GROUP="rg-oea-streamdev"
LOCATION="eastus"

# -----------------------------
# STORAGE CONFIG
# -----------------------------
STORAGE_ACCOUNT="stoeacanvas"
CONTAINERS=("oea")

# -----------------------------
# SYNAPSE CONFIG
# -----------------------------
WORKSPACE_NAME="syn-oea-streamdev"

# -----------------------------
# LOGIN & SUBSCRIPTION
# -----------------------------
echo "Logging into Azure..."
az login

echo "Setting subscription..."
az account set --subscription "$SUBSCRIPTION_ID"

# -----------------------------
# STEP 1 — CREATE STORAGE ACCOUNT (ADLS GEN2)
# -----------------------------
echo "Creating Storage Account..."
az storage account create \
  --name "$STORAGE_ACCOUNT" \
  --resource-group "$RESOURCE_GROUP" \
  --location "$LOCATION" \
  --sku Standard_LRS \
  --kind StorageV2 \
  --hierarchical-namespace true

# -----------------------------
# STEP 2 — CREATE CONTAINERS
# -----------------------------
echo "Creating containers..."
for c in "${CONTAINERS[@]}"
do
  echo "Creating container: $c"
  az storage container create \
    --name "$c" \
    --account-name "$STORAGE_ACCOUNT" \
    --auth-mode login
done

# -----------------------------
# STEP 3 — GET WORKSPACE MANAGED IDENTITY
# -----------------------------
echo "Fetching Synapse Managed Identity..."
WORKSPACE_MI=$(az synapse workspace show \
  --name "$WORKSPACE_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --query "identity.principalId" \
  -o tsv)

echo "Workspace Managed Identity:"
echo "$WORKSPACE_MI"

# -----------------------------
# STEP 4 — ASSIGN STORAGE PERMISSIONS
# -----------------------------
echo "Assigning Storage Blob Data Contributor role..."

STORAGE_SCOPE=$(az storage account show \
  --name "$STORAGE_ACCOUNT" \
  --resource-group "$RESOURCE_GROUP" \
  --query "id" \
  -o tsv)

az role assignment create \
  --assignee "$WORKSPACE_MI" \
  --role "Storage Blob Data Contributor" \
  --scope "$STORAGE_SCOPE"

echo "Waiting for RBAC to propagate..."
sleep 90

# -----------------------------
# STEP 5 — CREATE SYNAPSE LINKED SERVICE
# -----------------------------
echo "Creating Synapse Linked Service..."

az synapse linked-service create \
  --workspace-name "$WORKSPACE_NAME" \
  --name "ls_${STORAGE_ACCOUNT}" \
  --file @- <<EOF
{
  "properties": {
    "type": "AzureBlobFS",
    "typeProperties": {
      "url": "https://${STORAGE_ACCOUNT}.dfs.core.windows.net"
    },
    "connectVia": {
      "referenceName": "AutoResolveIntegrationRuntime",
      "type": "IntegrationRuntimeReference"
    },
    "authentication": "ManagedIdentity"
  }
}
EOF

# -----------------------------
# STEP 6 — VALIDATION
# -----------------------------
echo "Uploading test file..."
echo "STORAGE CONNECTED" > test.txt

az storage blob upload \
  --account-name "$STORAGE_ACCOUNT" \
  --container-name oea \
  --name test.txt \
  --file test.txt \
  --auth-mode login

rm test.txt

# -----------------------------
# STEP 7 — PRODUCTION HARDENING
# -----------------------------
echo "Enabling soft delete..."
az storage account blob-service-properties update \
  --account-name "$STORAGE_ACCOUNT" \
  --enable-delete-retention true \
  --delete-retention-days 14

echo "======================================="
echo " Setup Completed Successfully"
echo "======================================="
