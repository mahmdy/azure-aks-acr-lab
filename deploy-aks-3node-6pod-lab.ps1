#requires -Version 5.1
$ErrorActionPreference = "Stop"

# ============================================================
# AKS 3-Node / 6-Pod Lab
# ============================================================
# Creates:
#   - Resource Group in East US
#   - ACR (Basic)
#   - AKS with 3 Linux nodes across zones 1/2/3
#   - Imports public nginx:alpine into ACR as nginx:Prod
#   - Grants AKS permission to pull from ACR
#   - Deploys 6 nginx StatefulSet Pods
#   - Uses topology spread constraints to distribute them
#   - Creates an Azure LoadBalancer Service
#
# User interaction is limited to resource names. Press ENTER
# to accept the defaults.
# ============================================================

Write-Host "`n=== AKS 3-Node / 6-Pod Lab ===" -ForegroundColor Cyan

$RG = Read-Host "Resource Group [rg-aks-3node-lab]"
if ([string]::IsNullOrWhiteSpace($RG)) { $RG = "rg-aks-3node-lab" }

$AKS = Read-Host "AKS cluster [aks-3node-lab]"
if ([string]::IsNullOrWhiteSpace($AKS)) { $AKS = "aks-3node-lab" }

$ACR = Read-Host "ACR name (lowercase/global unique) [acraks3node$(Get-Random -Minimum 1000 -Maximum 9999)]"
if ([string]::IsNullOrWhiteSpace($ACR)) { $ACR = "acraks3node$(Get-Random -Minimum 1000 -Maximum 9999)" }

$LOCATION = "eastus"
$VM_SIZE = "Standard_D4s_v5"
$NODE_COUNT = 3
$IMAGE_REPO = "nginx"
$IMAGE_TAG = "Prod"
$IMAGE = "$ACR.azurecr.io/$IMAGE_REPO`:$IMAGE_TAG"
$MANIFEST_SOURCE = Join-Path (Get-Location) "aks-3node-6pod-lab.yaml"
$MANIFEST_RENDERED = Join-Path (Get-Location) "aks-3node-6pod-lab.generated.yaml"

Write-Host "`nConfiguration" -ForegroundColor Yellow
Write-Host "  Resource Group : $RG"
Write-Host "  Location       : $LOCATION"
Write-Host "  AKS            : $AKS"
Write-Host "  ACR            : $ACR"
Write-Host "  Image          : $IMAGE"
Write-Host "  VM Size        : $VM_SIZE"
Write-Host "  Nodes          : 3 (zones 1,2,3)"
Write-Host "  Web Pods       : 6"

$confirm = Read-Host "Continue? [Y/n]"
if ($confirm -and $confirm -notmatch '^(?i)y(es)?$') { exit 0 }

Write-Host "`n[1/10] Checking Azure CLI..." -ForegroundColor Cyan
az version | Out-Null

Write-Host "[2/10] Checking Azure login..." -ForegroundColor Cyan
az account show --output none 2>$null
if ($LASTEXITCODE -ne 0) {
    az login | Out-Null
}

Write-Host "[3/10] Checking AKS VM SKU availability in East US..." -ForegroundColor Cyan
az aks list-vm-skus --location $LOCATION --size $VM_SIZE --all --output table

Write-Host "[4/10] Creating Resource Group..." -ForegroundColor Cyan
az group create --name $RG --location $LOCATION --output none

Write-Host "[5/10] Creating ACR..." -ForegroundColor Cyan
az acr create --resource-group $RG --name $ACR --location $LOCATION --sku Basic --output none

Write-Host "[6/10] Creating AKS (3 nodes, zones 1/2/3)..." -ForegroundColor Cyan
az aks create `
    --resource-group $RG `
    --name $AKS `
    --location $LOCATION `
    --node-count $NODE_COUNT `
    --node-vm-size $VM_SIZE `
    --zones 1 2 3 `
    --generate-ssh-keys `
    --network-plugin azure `
    --load-balancer-sku standard `
    --output none

Write-Host "[7/10] Loading kubeconfig..." -ForegroundColor Cyan
az aks get-credentials --resource-group $RG --name $AKS --overwrite-existing --output none

Write-Host "[8/10] Importing nginx:alpine into ACR as nginx:Prod..." -ForegroundColor Cyan
az acr import `
    --name $ACR `
    --source docker.io/library/nginx:alpine `
    --image "$IMAGE_REPO`:$IMAGE_TAG" `
    --force `
    --output none

Write-Host "[9/10] Granting AKS ACR pull permission..." -ForegroundColor Cyan
az aks update `
    --resource-group $RG `
    --name $AKS `
    --attach-acr $ACR `
    --output none

if (-not (Test-Path $MANIFEST_SOURCE)) {
    throw "Cannot find $MANIFEST_SOURCE. Keep aks-3node-6pod-lab.yaml beside this script."
}

Write-Host "[10/10] Rendering and applying Kubernetes manifest..." -ForegroundColor Cyan
$yaml = Get-Content -Raw -Path $MANIFEST_SOURCE
$yaml = $yaml.Replace("__IMAGE__", $IMAGE)
Set-Content -Path $MANIFEST_RENDERED -Value $yaml -Encoding UTF8
kubectl apply -f $MANIFEST_RENDERED

Write-Host "`nWaiting for all six Pods..." -ForegroundColor Cyan
kubectl rollout status statefulset/demo-web -n aks-web-lab --timeout=10m

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
} else {
    Write-Host "LoadBalancer IP is still pending. Run:"
    Write-Host "kubectl get svc demo-web -n aks-web-lab -w"
}

Write-Host "`nUseful commands:" -ForegroundColor Yellow
Write-Host "  kubectl get pods -n aks-web-lab -o wide"
Write-Host "  kubectl get nodes --show-labels"
Write-Host "  kubectl get svc -n aks-web-lab"
Write-Host "  kubectl get endpoints demo-web -n aks-web-lab"
Write-Host "  kubectl get pods -n aks-web-lab -o custom-columns=NAME:.metadata.name,NODE:.spec.nodeName,IP:.status.podIP"
Write-Host ""
