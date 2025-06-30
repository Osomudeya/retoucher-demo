#!/bin/bash

# Register Microsoft.Dashboard provider for Grafana
az provider register --namespace Microsoft.Dashboard

# Register other commonly needed providers
az provider register --namespace Microsoft.ContainerService
az provider register --namespace Microsoft.Network
az provider register --namespace Microsoft.Compute
az provider register --namespace Microsoft.Storage
az provider register --namespace Microsoft.OperationalInsights
az provider register --namespace Microsoft.Insights
az provider register --namespace Microsoft.DBforPostgreSQL

# Wait for registration to complete
echo "Waiting for provider registration to complete..."
az provider show -n Microsoft.Dashboard --query registrationState -o tsv 