#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$ResourceGroup,
    [string]$AksName,
    [string]$AcrName,
    [string]$Location = "eastus",
    [switch]$NonInteractive
)

$ErrorActionPreference = "Stop"

if (-not $ResourceGroup) {
    if ($NonInteractive) { throw "ResourceGroup is required in non-interactive mode." }
    $ResourceGroup = Read-Host "Resource Group [rg-aks-3node-lab]"
    if ([string]::IsNullOrWhiteSpace($ResourceGroup)) { $ResourceGroup = "rg-aks-3node-lab" }
}
if (-not $AksName) {
    if ($NonInteractive) { throw "AksName is required in non-interactive mode." }
    $AksName = Read-Host "AKS cluster [aks-3node-lab]"
    if ([string]::IsNullOrWhiteSpace($AksName)) { $AksName = "aks-3node-lab" }
}
if (-not $AcrName) {
    if ($NonInteractive) { throw "AcrName is required in non-interactive mode." }
    $defaultAcr = "acraks3node$(Get-Random -Minimum 1000 -Maximum 9999)"
    $AcrName = Read-Host "ACR name (lowercase/global unique) [$defaultAcr]"
    if ([string]::IsNullOrWhiteSpace($AcrName)) { $AcrName = $defaultAcr }
}

$VM_SIZE = "Standard_D2s_v3"
$NODE_COUNT = 3
$IMAGE_REPO = "nginx"
$IMAGE_TAG = "Prod"
$IMAGE = "$AcrName.azurecr.io/$IMAGE_REPO`:$IMAGE_TAG"

$ManifestSource = Join-Path $PSScriptRoot "aks-3node-6pod-lab.yaml"
$ManifestRendered = Join-Path $PSScriptRoot "aks-3node-6pod-lab.generated.yaml"

Write-Host "`n=== AKS 3-Node / 6-Pod Lab ===" -ForegroundColor Cyan
Write-Host "  Resource Group : $ResourceGroup"
Write-Host "  Location       : $Location"
Write-Host "  AKS            : $AksName"
Write-Host "  ACR            : $AcrName"
Write-Host "  Image          : $IMAGE"
Write-Host "  VM Size        : $VM_SIZE"
Write-Host "  Nodes          : $NODE_COUNT"
Write-Host "  Web Pods       : 6"
Write-Host "  Availability Zones : Not used"

if (-not $NonInteractive) {
    $confirm = Read-Host "Continue? [Y/n]"
    if ($confirm -and $confirm -notmatch '^(?i)y(es)?$') { exit 0 }
}

Write-Host "`n[1/9] Checking Azure CLI..." -ForegroundColor Cyan
az version | Out-Null
if ($LASTEXITCODE -ne 0) { throw "Azure CLI is not available." }

Write-Host "[2/9] Checking Azure login..." -ForegroundColor Cyan
az account show --output none 2>$null
if ($LASTEXITCODE -ne 0) {
    if ($NonInteractive) { throw "Azure CLI is not logged in." }
    az login | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Azure login failed." }
}

Write-Host "[3/9] Creating Resource Group if needed..." -ForegroundColor Cyan
az group create --name $ResourceGroup --location $Location --output none
if ($LASTEXITCODE -ne 0) {
    throw "Failed to create or verify Resource Group '$ResourceGroup'."
}

Write-Host "[4/9] Creating ACR if needed..." -ForegroundColor Cyan
$acrExists = az acr show --name $AcrName --resource-group $ResourceGroup --query id -o tsv 2>$null
if (-not $acrExists) {
    az acr create `
        --resource-group $ResourceGroup `
        --name $AcrName `
        --location $Location `
        --sku Basic `
        --output none
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to create ACR '$AcrName'."
    }
}
else {
    Write-Host "ACR already exists; reusing it." -ForegroundColor DarkGray
}

Write-Host "[5/9] Creating AKS if needed (3 nodes, no Availability Zones)..." -ForegroundColor Cyan
$aksExists = az aks show --resource-group $ResourceGroup --name $AksName --query id -o tsv 2>$null

if (-not $aksExists) {
    az aks create `
        --resource-group $ResourceGroup `
        --name $AksName `
        --location $Location `
        --node-count $NODE_COUNT `
        --node-vm-size $VM_SIZE `
        --generate-ssh-keys `
        --network-plugin azure `
        --load-balancer-sku standard `
        --output none

    if ($LASTEXITCODE -ne 0) {
        throw "AKS cluster '$AksName' could not be created. Stopping deployment."
    }
}
else {
    Write-Host "AKS already exists; reusing it." -ForegroundColor DarkGray
}

Write-Host "[6/9] Loading kubeconfig..." -ForegroundColor Cyan
az aks get-credentials `
    --resource-group $ResourceGroup `
    --name $AksName `
    --overwrite-existing `
    --output none
if ($LASTEXITCODE -ne 0) {
    throw "Failed to retrieve kubeconfig for AKS cluster '$AksName'."
}

Write-Host "[7/9] Importing nginx:alpine into ACR as nginx:Prod..." -ForegroundColor Cyan
az acr import `
    --name $AcrName `
    --source docker.io/library/nginx:alpine `
    --image "$IMAGE_REPO`:$IMAGE_TAG" `
    --force `
    --output none
if ($LASTEXITCODE -ne 0) {
    throw "Failed to import nginx:alpine into ACR '$AcrName'."
}

Write-Host "[8/9] Granting AKS ACR pull permission..." -ForegroundColor Cyan
az aks update `
    --resource-group $ResourceGroup `
    --name $AksName `
    --attach-acr $AcrName `
    --output none
if ($LASTEXITCODE -ne 0) {
    throw "Failed to grant AKS permission to pull from ACR '$AcrName'."
}

if (-not (Test-Path $ManifestSource)) {
    throw "Cannot find $ManifestSource. Keep aks-3node-6pod-lab.yaml beside this script."
}

Write-Host "[9/9] Rendering and applying Kubernetes manifest..." -ForegroundColor Cyan
$yaml = Get-Content -Raw -Path $ManifestSource
$yaml = $yaml.Replace("__IMAGE__", $IMAGE)
Set-Content -Path $ManifestRendered -Value $yaml -Encoding UTF8

kubectl apply -f $ManifestRendered
if ($LASTEXITCODE -ne 0) {
    throw "kubectl failed to apply the Kubernetes manifest."
}

Write-Host "`nWaiting for all six Pods..." -ForegroundColor Cyan
kubectl rollout status statefulset/demo-web -n aks-web-lab --timeout=15m
if ($LASTEXITCODE -ne 0) {
    throw "The demo-web StatefulSet did not become ready."
}

Write-Host "`n=== Nodes ===" -ForegroundColor Yellow
kubectl get nodes -o wide
Write-Host "`n=== Pods and Nodes ===" -ForegroundColor Yellow
kubectl get pods -n aks-web-lab -o wide
Write-Host "`n=== Services ===" -ForegroundColor Yellow
kubectl get svc -n aks-web-lab
Write-Host "`n=== Endpoint distribution ===" -ForegroundColor Yellow
kubectl get endpoints demo-web -n aks-web-lab

$externalIP = kubectl get svc demo-web -n aks-web-lab -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
Write-Host ""
if ($externalIP) {
    Write-Host "Landing page: http://$externalIP" -ForegroundColor Green
}
else {
    Write-Host "LoadBalancer IP is still pending. Run:"
    Write-Host "kubectl get svc demo-web -n aks-web-lab -w"
}

Write-Host "`nUseful commands:" -ForegroundColor Yellow
Write-Host "  kubectl get pods -n aks-web-lab -o wide"
Write-Host "  kubectl get nodes --show-labels"
Write-Host "  kubectl get svc -n aks-web-lab"
Write-Host "  kubectl get endpoints demo-web -n aks-web-lab"
Write-Host "  kubectl get pods -n aks-web-lab -o custom-columns=NAME:.metadata.name,NODE:.spec.nodeName,IP:.status.podIP"
