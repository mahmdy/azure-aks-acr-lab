#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$ResourceGroup,
    [string]$GithubRepository,
    [string]$ApplicationName = "github-azure-aks-lab"
)

$ErrorActionPreference = "Stop"

# One-time bootstrap for GitHub Actions -> Azure OIDC.
# This script intentionally scopes the GitHub identity to ONE resource group.
# It creates:
#   1. The resource group used by the lab.
#   2. A Microsoft Entra application/service principal.
#   3. A GitHub OIDC federated credential bound to this repository and main branch.
#   4. Contributor + User Access Administrator on the lab resource group.
#
# Requirements:
#   - Azure CLI logged in with permission to create Entra applications,
#     role assignments, and resource groups.
#   - GitHub CLI (gh) installed and authenticated, so repository/owner IDs
#     can be retrieved for immutable GitHub OIDC subjects.

if (-not $ResourceGroup) {
    $ResourceGroup = Read-Host "Lab Resource Group [rg-aks-3node-lab]"
    if ([string]::IsNullOrWhiteSpace($ResourceGroup)) { $ResourceGroup = "rg-aks-3node-lab" }
}

if (-not $GithubRepository) {
    $GithubRepository = Read-Host "GitHub repository (OWNER/REPO)"
}

if ($GithubRepository -notmatch '^[^/]+/[^/]+$') {
    throw "GithubRepository must be in OWNER/REPO format."
}

Write-Host "Checking Azure CLI..." -ForegroundColor Cyan
az version | Out-Null
az account show --output none

Write-Host "Checking GitHub CLI..." -ForegroundColor Cyan
gh --version | Out-Null
gh auth status

$repoInfo = gh repo view $GithubRepository --json id,owner --jq '{repoId:.id,ownerId:.owner.id}' | ConvertFrom-Json
$repoId = [string]$repoInfo.repoId
$ownerId = [string]$repoInfo.ownerId
$owner = $GithubRepository.Split('/')[0]
$repo = $GithubRepository.Split('/')[1]

if (-not $repoId -or -not $ownerId) {
    throw "Could not retrieve GitHub repository/owner IDs."
}

$subscriptionId = az account show --query id -o tsv

Write-Host "Creating Resource Group if needed..." -ForegroundColor Cyan
az group create --name $ResourceGroup --location eastus --output none

Write-Host "Creating Microsoft Entra application..." -ForegroundColor Cyan
$appId = az ad app create --display-name $ApplicationName --query appId -o tsv
az ad sp create --id $appId --output none
$appObjectId = az ad app show --id $appId --query id -o tsv
$spObjectId = az ad sp show --id $appId --query id -o tsv

$scope = "/subscriptions/$subscriptionId/resourceGroups/$ResourceGroup"

Write-Host "Assigning Contributor on the lab resource group..." -ForegroundColor Cyan
az role assignment create `
    --assignee-object-id $spObjectId `
    --assignee-principal-type ServicePrincipal `
    --role Contributor `
    --scope $scope `
    --output none

Write-Host "Assigning User Access Administrator on the lab resource group..." -ForegroundColor Cyan
az role assignment create `
    --assignee-object-id $spObjectId `
    --assignee-principal-type ServicePrincipal `
    --role "User Access Administrator" `
    --scope $scope `
    --output none

# GitHub repositories created after 2026-07-15 use immutable OIDC subjects.
# Because we know the immutable owner/repository IDs, we can create a normal
# GA federated identity credential with an exact subject instead of a wildcard.
$subject = "repo:$owner@$ownerId/$repo@$repoId:ref:refs/heads/main"

$credential = @{
    name = "github-main-aks-lab"
    issuer = "https://token.actions.githubusercontent.com/"
    subject = $subject
    description = "GitHub Actions main branch for azure-aks-acr-lab"
    audiences = @("api://AzureADTokenExchange")
} | ConvertTo-Json -Depth 5

$tmp = Join-Path $env:TEMP "github-aks-federated-credential.json"
Set-Content -Path $tmp -Value $credential -Encoding UTF8

Write-Host "Creating GitHub OIDC federated credential..." -ForegroundColor Cyan
$existing = az ad app federated-credential list --id $appId | ConvertFrom-Json
$alreadyExists = $existing | Where-Object { $_.name -eq "github-main-aks-lab" }
if (-not $alreadyExists) {
    az ad app federated-credential create `
        --id $appId `
        --parameters $tmp `
        --output none
} else {
    Write-Host "Federated credential already exists; reusing it." -ForegroundColor DarkGray
}

Remove-Item $tmp -Force -ErrorAction SilentlyContinue

Write-Host "" 
Write-Host "=== GitHub OIDC Bootstrap Complete ===" -ForegroundColor Green
Write-Host "GitHub repository : $GithubRepository"
Write-Host "Resource Group    : $ResourceGroup"
Write-Host "Azure App Client ID: $appId"
Write-Host "Tenant ID         : $(az account show --query tenantId -o tsv)"
Write-Host "Subscription ID   : $subscriptionId"
Write-Host "" 
Write-Host "Add these GitHub Actions secrets:" -ForegroundColor Yellow
Write-Host "  AZURE_CLIENT_ID       = $appId"
Write-Host "  AZURE_TENANT_ID       = $(az account show --query tenantId -o tsv)"
Write-Host "  AZURE_SUBSCRIPTION_ID = $subscriptionId"
Write-Host "" 
Write-Host "The workflow should use main as its deployment branch." -ForegroundColor Yellow
Write-Host "The Azure identity is scoped to Resource Group: $ResourceGroup" -ForegroundColor Yellow
