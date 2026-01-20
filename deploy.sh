#!/bin/bash

# Azure Virtual Desktop Deployment Script
# This script deploys the AVD infrastructure using Bicep templates

set -e

# Configuration
RESOURCE_GROUP=""
LOCATION="UK South"
TEMPLATE_FILE="bicep/main.bicep"
PARAMETER_FILE="parameters/tst-main.bicepparam"
DEPLOYMENT_NAME="avd-deployment-$(date +%Y%m%d-%H%M%S)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        print_error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        print_error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check if bicep is installed
    if ! az bicep version &> /dev/null; then
        print_warning "Bicep CLI not found. Installing..."
        az bicep install
    fi
    
    print_status "Prerequisites check completed."
}

# Function to validate parameters
validate_parameters() {
    print_status "Validating parameters..."
    
    if [ -z "$RESOURCE_GROUP" ]; then
        print_error "Resource group not specified. Please set RESOURCE_GROUP variable."
        exit 1
    fi
    
    if [ ! -f "$TEMPLATE_FILE" ]; then
        print_error "Template file not found: $TEMPLATE_FILE"
        exit 1
    fi
    
    if [ ! -f "$PARAMETER_FILE" ]; then
        print_error "Parameter file not found: $PARAMETER_FILE"
        exit 1
    fi
    
    print_status "Parameter validation completed."
}

# Function to create resource group if it doesn't exist
create_resource_group() {
    print_status "Checking resource group: $RESOURCE_GROUP"
    
    if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        print_status "Creating resource group: $RESOURCE_GROUP"
        az group create --name "$RESOURCE_GROUP" --location "$LOCATION"
    else
        print_status "Resource group already exists: $RESOURCE_GROUP"
    fi
}

# Function to validate bicep template
validate_template() {
    print_status "Validating Bicep template..."
    
    az deployment group validate \
        --resource-group "$RESOURCE_GROUP" \
        --template-file "$TEMPLATE_FILE" \
        --parameters "@$PARAMETER_FILE" \
        --no-prompt
    
    print_status "Template validation completed successfully."
}

# Function to deploy template
deploy_template() {
    print_status "Starting deployment: $DEPLOYMENT_NAME"
    
    # Prompt for admin password if not provided via Key Vault
    if [ -z "$ADMIN_PASSWORD" ]; then
        echo -n "Enter admin password for VMs (will not be displayed): "
        read -s ADMIN_PASSWORD
        echo
    fi
    
    az deployment group create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$DEPLOYMENT_NAME" \
        --template-file "$TEMPLATE_FILE" \
        --parameters "@$PARAMETER_FILE" \
        --parameters adminPassword="$ADMIN_PASSWORD" \
        --no-prompt
    
    print_status "Deployment completed successfully."
}

# Function to show deployment outputs
show_outputs() {
    print_status "Deployment outputs:"
    
    az deployment group show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$DEPLOYMENT_NAME" \
        --query properties.outputs \
        --output table
}

# Function to show post-deployment instructions
show_post_deployment() {
    print_status "Post-deployment steps:"
    echo ""
    echo "1. Configure FSLogix (if enabled):"
    echo "   - Navigate to the created Storage Account in Azure portal"
    echo "   - Configure FSLogix policies in Intune"
    echo ""
    echo "2. Assign users to the Application Group:"
    echo "   - Use Azure portal or PowerShell to assign 'Desktop Virtualization User' role"
    echo ""
    echo "3. Configure Intune policies for session hosts"
    echo ""
    echo "4. Test user connections via AVD web client or native apps"
    echo ""
}

# Main execution
main() {
    echo "============================================"
    echo "Azure Virtual Desktop Deployment Script"
    echo "============================================"
    echo ""
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --resource-group)
                RESOURCE_GROUP="$2"
                shift 2
                ;;
            --location)
                LOCATION="$2"
                shift 2
                ;;
            --parameter-file)
                PARAMETER_FILE="$2"
                shift 2
                ;;
            --admin-password)
                ADMIN_PASSWORD="$2"
                shift 2
                ;;
            --help)
                echo "Usage: $0 --resource-group <rg-name> [options]"
                echo ""
                echo "Options:"
                echo "  --resource-group   Azure resource group name (required)"
                echo "  --location         Azure region (default: UK South)"
                echo "  --parameter-file   Parameter file path (default: parameters/tst-main.bicepparam)"
                echo "  --admin-password   VM admin password (will prompt if not provided)"
                echo "  --help            Show this help message"
                exit 0
                ;;
            *)
                print_error "Unknown parameter: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
    
    check_prerequisites
    validate_parameters
    create_resource_group
    validate_template
    deploy_template
    show_outputs
    show_post_deployment
    
    print_status "Deployment script completed successfully!"
}

# Run main function
main "$@"