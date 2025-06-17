#!/bin/bash

# SSH Key Setup for CI/CD Pipeline
# Run this script locally to generate keys for GitHub Actions

echo "🔑 Setting up SSH keys for CI/CD pipeline..."

# Create a dedicated SSH key pair for CI/CD
ssh-keygen -t rsa -b 4096 -C "github-actions-cicd" -f ./cicd_ssh_key -N ""

echo "✅ SSH key pair generated:"
echo "- Private key: ./cicd_ssh_key"
echo "- Public key: ./cicd_ssh_key.pub"

echo ""
echo "📋 Public key content (add this to terraform.tfvars):"
echo "ssh_public_key = \"$(cat ./cicd_ssh_key.pub)\""

echo ""
echo "🔒 Private key content (add this to GitHub Secrets as SSH_PRIVATE_KEY):"
echo "Copy the entire content below (including BEGIN/END lines):"
echo "----------------------------------------"
cat ./cicd_ssh_key
echo "----------------------------------------"

echo ""
echo "🚨 SECURITY REMINDER:"
echo "1. Add the private key to GitHub Secrets immediately"
echo "2. Delete the local private key file: rm ./cicd_ssh_key"
echo "3. Keep the public key for reference: mv ./cicd_ssh_key.pub ./cicd_ssh_key_public.txt"

echo ""
echo "📝 Next steps:"
echo "1. Copy the public key to terraform/terraform.tfvars"
echo "2. Add private key to GitHub repository secrets"
echo "3. Clean up local private key file"