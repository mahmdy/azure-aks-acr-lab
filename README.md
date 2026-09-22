# Azure AKS + ACR Lab

Hands-on Azure Kubernetes Service (AKS) lab integrating Azure Container Registry (ACR), StatefulSets, multi-node Pod distribution, Availability Zones, and Azure Load Balancer.

This project can be deployed in two ways:

1. **Local PowerShell automation** for learning and troubleshooting.
2. **GitHub Actions + Azure OIDC** for a mostly automated CI/CD-style deployment.

The GitHub workflow is the recommended way to demonstrate the automation side of the project.

---

## Architecture

```text
                         GitHub Repository
                                |
                         GitHub Actions
                                |
                         OIDC / Azure Login
                                |
                                v
                              Azure
                 +--------------+--------------+
                 |                             |
                 v                             v
                ACR                           AKS
          nginx:Prod                 3 Nodes / 3 Zones
                                             |
                         +-------------------+-------------------+
                         |                   |                   |
                         v                   v                   v
                       Node 1             Node 2             Node 3
                       Zone 1             Zone 2             Zone 3
                         |                   |                   |
                         +-------------------+-------------------+
                                             |
                                      6 StatefulSet Pods
                                      demo-web-0 ... -5
                                             |
                                             v
                                    LoadBalancer Service
                                             |
                                             v
                                          Internet
```

The application flow is:

```text
NGINX image
    |
    v
Azure Container Registry
    |
    | ACR pull permission
    v
AKS
    |
    v
StatefulSet
    |
    +--> demo-web-0
    +--> demo-web-1
    +--> demo-web-2
    +--> demo-web-3
    +--> demo-web-4
    +--> demo-web-5
    |
    v
Kubernetes Service (LoadBalancer)
    |
    v
Azure Public Load Balancer
```

Each landing page identifies the Pod, Pod sequence, Pod IP, Node, Availability Zone, and image reference. This makes scheduling and load balancing visible during the lab.

---

# Repository Files

```text
azure-aks-acr-lab/
|
+-- .github/
|   +-- workflows/
|       +-- deploy-aks-lab.yml
|       +-- cleanup-aks-lab.yml
|
+-- aks-3node-6pod-lab.yaml
+-- deploy-aks-3node-6pod-lab.ps1
+-- setup-github-azure-oidc.ps1
+-- README.md
```

### `aks-3node-6pod-lab.yaml`

Kubernetes manifest containing:

- Namespace
- ConfigMap containing the landing-page startup script
- Headless Service required by the StatefulSet
- 6-replica StatefulSet
- Topology spread constraints
- Public `LoadBalancer` Service

### `deploy-aks-3node-6pod-lab.ps1`

The reusable deployment automation. It supports both interactive local execution and non-interactive GitHub Actions execution.

### `setup-github-azure-oidc.ps1`

A **one-time bootstrap script** that establishes trust between this GitHub repository and Azure using GitHub OIDC. It also prepares the Azure Resource Group and the Azure permissions needed by the workflow.

### `.github/workflows/deploy-aks-lab.yml`

Manual GitHub Actions workflow that logs in to Azure with OIDC and runs the deployment automation.

### `.github/workflows/cleanup-aks-lab.yml`

Manual cleanup workflow that deletes the AKS cluster and ACR while intentionally preserving the Resource Group and its GitHub OIDC role assignments.

---

# Why StatefulSet?

The application is technically stateless, but this lab uses a StatefulSet because it gives the replicas stable ordinal identities:

```text
demo-web-0
demo-web-1
demo-web-2
demo-web-3
demo-web-4
demo-web-5
```

That makes the Pod sequence easy to demonstrate on the landing page.

The Node hosting a Pod is not part of that identity. If a Pod is recreated, Kubernetes can place it on another suitable Node while keeping the StatefulSet ordinal.

---

# Why Three Nodes and Six Pods?

The lab intentionally uses:

```text
3 Nodes
6 application Pods
```

The target distribution is approximately:

```text
Node 1 -> 2 Pods
Node 2 -> 2 Pods
Node 3 -> 2 Pods
```

The manifest uses `topologySpreadConstraints` to request balanced placement across:

- `topology.kubernetes.io/zone`
- `kubernetes.io/hostname`

The Kubernetes scheduler makes the final placement decision.

Do not treat the exact Pod-to-Node mapping as permanent. Pod recreation can result in a different Node assignment.

---

# Azure Resources

Default configuration:

| Resource | Configuration |
|---|---|
| Region | East US |
| AKS Nodes | 3 |
| Availability Zones | 1, 2, 3 |
| Node VM size | `Standard_D4s_v5` |
| Application replicas | 6 |
| Container image | NGINX |
| ACR tag | `Prod` |
| Kubernetes workload | StatefulSet |
| External Service | LoadBalancer |

The node size is deliberately kept small for a lab while meeting the requirements of an AKS system node pool. Azure recommends using supported VM sizes for AKS system pools; B-series is not the target SKU for this exercise.

---

# Prerequisites

## Local execution

Install:

- Azure CLI
- `kubectl`
- PowerShell 5.1 or PowerShell 7+
- An Azure subscription

Verify:

```powershell
az version
kubectl version --client
```

Log in:

```powershell
az login
```

Check the subscription:

```powershell
az account show
```

If necessary:

```powershell
az account set --subscription "<SUBSCRIPTION_ID_OR_NAME>"
```

## GitHub Actions execution

For the OIDC setup you also need:

- GitHub CLI (`gh`)
- `gh auth login`
- Permission in Azure to create an Entra application/service principal and role assignments
- Permission to configure the GitHub repository

---

# Option A — Local PowerShell Deployment

This is useful when learning the Azure and Kubernetes commands directly.

## Step 1 — Clone the repository

```powershell
git clone <YOUR_REPOSITORY_URL>
cd azure-aks-acr-lab
```

Verify:

```powershell
Get-ChildItem
```

## Step 2 — Allow the script to run

```powershell
Set-ExecutionPolicy -Scope Process Bypass
```

## Step 3 — Run the deployment

```powershell
.\deploy-aks-3node-6pod-lab.ps1
```

The interactive version asks for:

```text
Resource Group
AKS cluster name
ACR name
```

Press ENTER to accept defaults where available.

The script automatically:

1. Checks Azure CLI.
2. Checks Azure authentication.
3. Checks the selected AKS VM SKU.
4. Creates/reuses the Resource Group.
5. Creates/reuses the ACR.
6. Creates/reuses the AKS cluster.
7. Gets AKS credentials.
8. Imports `nginx:alpine` into ACR as `nginx:Prod`.
9. Attaches the ACR to AKS.
10. Renders and applies the Kubernetes manifest.
11. Waits for all six Pods.
12. Displays Nodes, Pods, Service, and endpoints.
13. Prints the LoadBalancer landing-page URL when available.

---

# Option B — GitHub Actions + Azure OIDC

This is the recommended automated path.

The workflow does **not** store an Azure client secret in GitHub. Instead, GitHub Actions requests a short-lived OIDC token and Azure trusts the configured federated identity. GitHub documents OIDC as a way to authenticate to Azure without long-lived Azure credentials stored as secrets.

The workflow requires:

```yaml
permissions:
  id-token: write
  contents: read
```

and uses:

```yaml
uses: azure/login@v2
```

The Azure identity is scoped to the lab Resource Group rather than the whole subscription.

---

## Step 1 — Authenticate GitHub CLI

Install GitHub CLI if necessary, then:

```powershell
gh auth login
```

Verify:

```powershell
gh auth status
```

---

## Step 2 — Run the one-time Azure/GitHub OIDC bootstrap

From the repository directory:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
```

Then:

```powershell
.\setup-github-azure-oidc.ps1
```

The script asks for:

```text
Lab Resource Group
GitHub repository (OWNER/REPO)
```

Example:

```text
Lab Resource Group [rg-aks-3node-lab]: rg-aks-3node-lab
GitHub repository (OWNER/REPO): YOUR-USER/azure-aks-acr-lab
```

The script then:

1. Creates the lab Resource Group in East US.
2. Reads the GitHub repository and owner IDs.
3. Creates a Microsoft Entra application/service principal.
4. Grants the application `Contributor` on the lab Resource Group.
5. Grants `User Access Administrator` on the lab Resource Group so the workflow can create the ACR pull role assignment needed by AKS.
6. Creates a GitHub OIDC federated credential bound to the repository's immutable identity and the `main` branch.
7. Prints the three values required as GitHub Actions secrets.

GitHub repositories created after July 15, 2026 use immutable default OIDC subjects containing owner and repository IDs. The bootstrap script uses those IDs so the trust relationship is not based only on a mutable repository name.

---

## Step 3 — Add GitHub Actions secrets

Open the GitHub repository:

```text
Settings
  -> Secrets and variables
  -> Actions
  -> New repository secret
```

Create these three secrets using the values printed by the bootstrap script:

```text
AZURE_CLIENT_ID
AZURE_TENANT_ID
AZURE_SUBSCRIPTION_ID
```

Do **not** create an `AZURE_CLIENT_SECRET` secret for this workflow.

---

## Step 4 — Push the workflow files

Make sure these files are committed:

```text
.github/workflows/deploy-aks-lab.yml
.github/workflows/cleanup-aks-lab.yml
```

Then:

```powershell
git add .
git commit -m "Add Azure AKS GitHub Actions automation"
git push origin main
```

---

## Step 5 — Start the deployment from GitHub

Open:

```text
GitHub repository
    -> Actions
    -> Deploy AKS ACR Lab
    -> Run workflow
```

Enter:

```text
Resource Group
AKS cluster name
ACR name
Location
```

The default location is:

```text
eastus
```

The Resource Group should be the one prepared by the OIDC bootstrap script because that is where the GitHub identity has its Azure permissions.

Click:

```text
Run workflow
```

No Azure login is required on your PC for the workflow itself.

---

# What Happens Inside GitHub Actions?

```text
GitHub Actions Runner
        |
        v
Checkout repository
        |
        v
Azure OIDC token
        |
        v
azure/login@v2
        |
        v
Azure access token
        |
        +----------------------+
        |                      |
        v                      v
       ACR                    AKS
        |                      |
        | nginx:Prod           | 3 Nodes
        |                      |
        +----------+-----------+
                   |
                   v
             Kubernetes
                   |
                   v
             6 StatefulSet Pods
                   |
                   v
             LoadBalancer
                   |
                   v
             Public IP
```

The workflow then prints the Nodes, Pods, Service, and endpoints and adds the public URL and deployment information to the GitHub Actions job summary.

---

# Verify the Deployment

The workflow already performs verification, but you can also inspect the cluster manually.

## Nodes

```powershell
kubectl get nodes -o wide
```

Expected:

```text
3 Ready Nodes
```

## Pods

```powershell
kubectl get pods -n aks-web-lab -o wide
```

Expected:

```text
demo-web-0
demo-web-1
demo-web-2
demo-web-3
demo-web-4
demo-web-5
```

All should eventually be:

```text
1/1 Running
```

## StatefulSet

```powershell
kubectl get statefulset -n aks-web-lab
```

Expected:

```text
NAME       READY
demo-web   6/6
```

## Service

```powershell
kubectl get service demo-web -n aks-web-lab
```

Look for:

```text
EXTERNAL-IP
```

## Endpoints

```powershell
kubectl get endpoints demo-web -n aks-web-lab
```

The Service should have the healthy application endpoints.

---

# Test the Landing Page

Get the public IP:

```powershell
kubectl get service demo-web -n aks-web-lab
```

Open:

```text
http://<EXTERNAL-IP>
```

or:

```powershell
curl.exe http://<EXTERNAL-IP>
```

The page displays information similar to:

```text
AKS 3-Node / 6-Pod Demo

Pod Sequence:       3
Pod Name:           demo-web-3
Pod IP:             10.244.x.x
Node:               aks-...-vmss000001
Availability Zone:  2
Image:              acr...azurecr.io/nginx:Prod
```

---

# Test Load Distribution

Send multiple requests:

```powershell
$IP="<EXTERNAL-IP>"

for ($i=1; $i -le 20; $i++) {
    Write-Host "Request $i"
    curl.exe -s --no-keepalive "http://$IP"
    Write-Host ""
}
```

The responses should identify different Pods over multiple requests.

Do not expect strict round-robin behavior. The purpose of the test is to observe that the Service can send traffic to multiple healthy Pod endpoints.

---

# Show Which Pod Runs on Which Node

```powershell
kubectl get pods -n aks-web-lab -o wide
```

Or a focused view:

```powershell
kubectl get pods -n aks-web-lab `
  -o custom-columns="POD:.metadata.name,NODE:.spec.nodeName,IP:.status.podIP,STATUS:.status.phase"
```

The important relationship is:

```text
Pod
  |
  +-- runs on --> Node
```

The Service itself is not a Pod and is not assigned to one particular Node in the same way an application Pod is. It selects healthy Pod endpoints and provides a stable networking abstraction.

---

# Test StatefulSet Self-Healing

Delete one Pod:

```powershell
kubectl delete pod demo-web-0 -n aks-web-lab
```

Watch the replacement:

```powershell
kubectl get pods -n aks-web-lab -w
```

The StatefulSet should recreate:

```text
demo-web-0
```

The identity remains `demo-web-0`, but the replacement may be scheduled on a different suitable Node.

---

# Troubleshooting

## `ImagePullBackOff`

Inspect the Pod:

```powershell
kubectl describe pod <POD_NAME> -n aks-web-lab
```

Check the `Events` section.

A common ACR error is:

```text
401 Unauthorized
```

This indicates an ACR authentication/authorization problem.

Check the AKS-to-ACR integration:

```powershell
az aks show `
  --resource-group <RESOURCE_GROUP> `
  --name <AKS_NAME> `
  --query identityProfile.kubeletidentity
```

The AKS kubelet identity needs the appropriate ACR pull role. For a normal RBAC ACR, this is typically `AcrPull`.

## LoadBalancer IP is pending

```powershell
kubectl get service demo-web -n aks-web-lab -w
```

## Pod is Pending

```powershell
kubectl describe pod <POD_NAME> -n aks-web-lab
```

Look at `Events` for scheduling or resource problems.

## Pods are not balanced

Inspect:

```powershell
kubectl get pods -n aks-web-lab -o wide
```

and:

```powershell
kubectl get nodes --show-labels
```

The topology constraints are scheduling constraints, not a guarantee that a specific StatefulSet ordinal permanently belongs to a specific Node.

## GitHub Azure login fails

Verify:

- `AZURE_CLIENT_ID`
- `AZURE_TENANT_ID`
- `AZURE_SUBSCRIPTION_ID`
- The workflow contains `id-token: write`.
- The federated credential matches this repository and the `main` branch.
- The repository is using the immutable subject configuration expected by the bootstrap script.

Also verify the Azure role assignments on the lab Resource Group.

---

# Cleanup from GitHub Actions

The cleanup workflow intentionally preserves the Resource Group because the GitHub OIDC application has its permissions scoped there.

Go to:

```text
GitHub
  -> Actions
  -> Cleanup AKS ACR Lab
  -> Run workflow
```

Provide:

```text
Resource Group
AKS name
ACR name
```

For the confirmation field enter exactly:

```text
DELETE
```

The workflow will:

1. Show the current resources.
2. Delete the AKS cluster.
3. Wait for AKS deletion.
4. Delete the ACR.
5. Preserve the Resource Group and its OIDC role assignments.

The Resource Group itself has no compute charge. Keeping it allows the next GitHub deployment to reuse the same OIDC permissions.

---

# Full Manual Cleanup

If you intentionally want to remove the Resource Group too, you can do it locally:

```powershell
az group delete `
  --name <RESOURCE_GROUP> `
  --yes `
  --no-wait
```

Important: deleting the Resource Group also removes the role assignments scoped to it. The GitHub OIDC bootstrap must therefore be run again before the workflow can deploy into a newly recreated Resource Group.

---

# Security Model

## GitHub → Azure

The project uses GitHub Actions OIDC rather than a long-lived Azure client secret.

```text
GitHub Actions
      |
      | short-lived OIDC token
      v
Microsoft Entra ID
      |
      v
Azure access token
```

The workflow does not require:

```text
AZURE_CLIENT_SECRET
```

## Azure permissions

The GitHub application is scoped to the lab Resource Group.

The bootstrap grants:

```text
Contributor
User Access Administrator
```

at that Resource Group scope.

`User Access Administrator` is needed here because the deployment needs to establish the AKS kubelet identity's ACR pull role assignment. This is a lab-oriented design; in a production environment, prefer narrower/custom permissions where practical.

## ACR → AKS

The AKS kubelet identity receives the ACR pull permission needed to retrieve the private image.

```text
AKS kubelet identity
        |
        | AcrPull / appropriate ACR reader role
        v
Azure Container Registry
```

---

# Why `nginx:Prod`?

The lab imports the public NGINX image into the private ACR and tags it:

```text
nginx:Prod
```

The resulting reference is:

```text
<ACR_NAME>.azurecr.io/nginx:Prod
```

This demonstrates the concept of promoting an image into a private registry before it is deployed into AKS.

For a real CI/CD pipeline, this step could be replaced with:

```text
Source Code
   ↓
Build
   ↓
Security Scan / Trivy Gate
   ↓
Push approved image to ACR
   ↓
Deploy exact image digest/tag to AKS
```

---

# Learning Objectives

After completing this project, you should be able to explain:

1. What Azure Container Registry does.
2. How AKS authenticates to ACR.
3. How GitHub Actions authenticates to Azure using OIDC.
4. Why OIDC is preferable to long-lived cloud credentials for this workflow.
5. What a StatefulSet is.
6. Why StatefulSet Pods have stable ordinal names.
7. How six Pods are distributed across three Nodes.
8. How topology spread constraints influence scheduling.
9. The difference between Pod identity and Node placement.
10. How a Kubernetes Service selects Pod endpoints.
11. How a LoadBalancer Service exposes an application through Azure.
12. How multiple HTTP requests can reach different replicas.
13. How Kubernetes recreates a deleted StatefulSet Pod.
14. How GitHub Actions can automate Azure infrastructure and Kubernetes deployment.
15. How to inspect Nodes, Pods, Services, and endpoints with `kubectl`.

---

# Important Lab Note

This project is intentionally designed as a hands-on learning environment. It demonstrates multiple Azure and Kubernetes concepts in one workflow rather than being a production reference architecture.

For production use, review at least:

- Dedicated system and user node pools.
- Private networking.
- Network policies.
- TLS/HTTPS.
- Azure RBAC scope.
- ACR repository-level permissions where applicable.
- Secrets management.
- Monitoring and logging.
- Resource requests and limits.
- Cost controls and budgets.
- Image signing and provenance.
- Deployment by immutable image digest instead of a mutable tag such as `Prod`.

The public LoadBalancer is intentional for this lab so that the landing page can be accessed directly from the Internet.

---

# References

- GitHub Actions OIDC with Azure: https://docs.github.com/en/actions/how-tos/secure-your-work/security-harden-deployments/oidc-in-azure
- GitHub OIDC reference and immutable subjects: https://docs.github.com/en/actions/reference/security/oidc
- Microsoft Entra federated identity credentials: https://learn.microsoft.com/en-us/entra/workload-id/workload-identity-federation-create-trust
- Azure AKS managed identities: https://learn.microsoft.com/en-us/azure/aks/managed-identity-overview
- AKS / ACR integration: https://learn.microsoft.com/en-us/azure/aks/cluster-container-registry-integration
