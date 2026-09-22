# Azure AKS + ACR Lab

Hands-on Azure Kubernetes Service (AKS) lab integrating Azure Container Registry (ACR), StatefulSets, multi-node Pod distribution, topology spread constraints, and an Azure Load Balancer.

The lab uses:

- Azure East US
- 3 AKS nodes
- 6 application Pods
- `Standard_D2s_v3` nodes (2 vCPU / 8 GiB each)
- ACR image `nginx:Prod`
- StatefulSet with stable Pod names `demo-web-0` ... `demo-web-5`
- Public `LoadBalancer` Service
- GitHub Actions + Azure OIDC
- No Availability Zone dependency; Pod spreading is based on Kubernetes node hostname

This project can be deployed in two ways:

1. **Local PowerShell automation** for learning and troubleshooting.
2. **GitHub Actions + Azure OIDC** for a mostly automated CI/CD-style deployment.

The GitHub workflow is the recommended way to demonstrate the automation side of the project.

---

# Architecture

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
          nginx:Prod                       3 Nodes
                                             |
                         +-------------------+-------------------+
                         |                   |                   |
                         v                   v                   v
                       Node 1             Node 2             Node 3
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
                                    Azure Public IP
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

Each landing page identifies the Pod, Pod sequence, Pod IP, Node, and image reference. This makes scheduling and load balancing visible during the lab.

---

# What You Will Learn

This lab combines the following concepts in one end-to-end exercise:

1. Azure Resource Groups
2. Azure Container Registry
3. Azure Kubernetes Service
4. AKS node pools and VM sizing
5. Kubernetes Namespaces
6. ConfigMaps
7. StatefulSets
8. Stable StatefulSet Pod identities
9. Services and Endpoints
10. Azure Load Balancer
11. Topology spread constraints
12. Pod self-healing
13. Node cordon and drain
14. Pod rescheduling after node disruption
15. GitHub Actions
16. GitHub OIDC authentication to Azure
17. AKS-to-ACR authentication
18. Automated deployment and cleanup

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
- Topology spread constraint using `kubernetes.io/hostname`
- Public `LoadBalancer` Service

The manifest does **not** require Azure Availability Zones.

### `deploy-aks-3node-6pod-lab.ps1`

Reusable deployment automation. It supports both interactive local execution and non-interactive GitHub Actions execution.

The script:

- Creates or reuses the Resource Group
- Creates or reuses ACR
- Creates or reuses AKS
- Uses `Standard_D2s_v3` for the 3-node lab
- Imports `nginx:alpine` into ACR as `nginx:Prod`
- Attaches ACR to AKS
- Renders the Kubernetes manifest by replacing `__IMAGE__` with the actual ACR image
- Applies the rendered manifest
- Waits for the StatefulSet rollout
- Verifies Nodes, Pods, Service, and endpoints

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

For example, `demo-web-2` can be recreated on a different Node and will still be named `demo-web-2`.

---

# Why Three Nodes and Six Pods?

The lab intentionally uses:

```text
3 Nodes
6 application Pods
```

The normal target distribution is approximately:

```text
Node 1 -> 2 Pods
Node 2 -> 2 Pods
Node 3 -> 2 Pods
```

The manifest uses a topology spread constraint based on:

```text
kubernetes.io/hostname
```

This asks the Kubernetes scheduler to keep the Pods reasonably balanced across the three Nodes.

The lab does **not** use:

```text
topology.kubernetes.io/zone
```

because Availability Zones are not required for this exercise.

The topology constraint uses:

```yaml
whenUnsatisfiable: ScheduleAnyway
```

This is intentional. It allows Kubernetes to continue scheduling Pods when perfect spreading is not possible—for example, when one Node becomes unavailable. The scheduler still tries to keep the workload balanced, but availability is not blocked by the spreading preference.

Do not treat the exact Pod-to-Node mapping as permanent. Pod recreation and Node disruption can result in a different mapping.

---

# Azure Resources

Default configuration:

| Resource | Configuration |
|---|---|
| Region | East US |
| AKS Nodes | 3 |
| Node VM size | `Standard_D2s_v3` |
| Total lab node capacity | 6 vCPU / 24 GiB |
| Application replicas | 6 |
| Container image | NGINX |
| ACR tag | `Prod` |
| Kubernetes workload | StatefulSet |
| External Service | LoadBalancer |
| Availability Zone dependency | None |

The `Standard_D2s_v3` size provides 2 vCPUs and 8 GiB memory per Node. Three Nodes therefore use 6 vCPUs in total, which keeps the lab within the subscription quota used for this exercise.

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
3. Creates/reuses the Resource Group.
4. Creates/reuses the ACR.
5. Creates/reuses the AKS cluster.
6. Gets AKS credentials.
7. Imports `nginx:alpine` into ACR as `nginx:Prod`.
8. Attaches the ACR to AKS.
9. Renders the Kubernetes manifest and replaces `__IMAGE__`.
10. Applies the rendered Kubernetes manifest.
11. Waits for all six Pods.
12. Displays Nodes, Pods, Service, and endpoints.
13. Prints the LoadBalancer landing-page URL when available.

The current automation does not perform the earlier experimental AKS VM SKU pre-check.

---

# Option B — GitHub Actions + Azure OIDC

This is the recommended automated path.

The workflow does **not** store an Azure client secret in GitHub. Instead, GitHub Actions requests a short-lived OIDC token and Azure trusts the configured federated identity.

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

The script then:

1. Creates the lab Resource Group in East US.
2. Reads the GitHub repository and owner IDs.
3. Creates a Microsoft Entra application/service principal.
4. Grants the application `Contributor` on the lab Resource Group.
5. Grants `User Access Administrator` on the lab Resource Group so the workflow can create the ACR pull role assignment needed by AKS.
6. Creates a GitHub OIDC federated credential bound to the repository identity and `main` branch.
7. Prints the three values required as GitHub Actions secrets.

---

## Step 3 — Add GitHub Actions secrets

Open the GitHub repository:

```text
Settings
  -> Secrets and variables
  -> Actions
  -> New repository secret
```

Create:

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
Image:              acr...azurecr.io/nginx:Prod
```

The landing page does not display an Availability Zone because the lab does not depend on Availability Zones.

---

# Test Load Distribution

Send multiple requests:

```powershell
$IP="<EXTERNAL-IP>"

for ($i=1; $i -le 20; $i++) {
    Write-Host "Request $i"
    curl.exe -s --no-keep-alive "http://$IP"
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

Or:

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

# Hands-On Exercise 1 — StatefulSet Self-Healing

Delete one Pod:

```powershell
kubectl delete pod demo-web-0 -n aks-web-lab
```

Watch:

```powershell
kubectl get pods -n aks-web-lab -w
```

The StatefulSet should recreate:

```text
demo-web-0
```

The identity remains `demo-web-0`, but the replacement may be scheduled on a different suitable Node.

Check the new placement:

```powershell
kubectl get pods -n aks-web-lab -o wide
```

---

# Hands-On Exercise 2 — Cordon a Node

A cordon prevents **new** Pods from being scheduled on a Node. It does not evict existing Pods.

First inspect Nodes:

```powershell
kubectl get nodes
```

Choose one Node and cordon it:

```powershell
kubectl cordon <NODE_NAME>
```

Verify:

```powershell
kubectl get nodes
```

You should see:

```text
Ready,SchedulingDisabled
```

Existing Pods on the Node continue running.

Uncordon when finished:

```powershell
kubectl uncordon <NODE_NAME>
```

---

# Hands-On Exercise 3 — Drain a Node

A drain evicts eligible workload Pods so that they can be recreated elsewhere.

Inspect the Pods first:

```powershell
kubectl get pods -n aks-web-lab -o wide
```

Drain the selected Node:

```powershell
kubectl drain <NODE_NAME> --ignore-daemonsets --delete-emptydir-data
```

Watch the StatefulSet:

```powershell
kubectl get pods -n aks-web-lab -o wide -w
```

Because the topology constraint uses `ScheduleAnyway`, Kubernetes can continue scheduling replacement Pods even when perfect three-way spreading is temporarily impossible.

When the exercise is complete:

```powershell
kubectl uncordon <NODE_NAME>
```

Then verify:

```powershell
kubectl get nodes
kubectl get pods -n aks-web-lab -o wide
```

---

# Hands-On Exercise 4 — Observe Node Failure Behavior

The purpose of this exercise is to understand the difference between:

- Pod failure
- Node scheduling restriction
- Node drain
- Actual Node unavailability

A real Node failure can temporarily leave its Pods unavailable while Kubernetes detects the failure and recreates/reschedules workloads.

Check the workload:

```powershell
kubectl get pods -n aks-web-lab -o wide
```

Check Node conditions:

```powershell
kubectl get nodes
kubectl describe node <NODE_NAME>
```

The important lesson is that a StatefulSet preserves the Pod's ordinal identity, while Kubernetes is responsible for deciding where the replacement Pod runs.

---

# Troubleshooting

## Wrong or stale kubectl context

If `kubectl` points to an old AKS cluster or an unreachable API endpoint, refresh the credentials:

```powershell
az aks get-credentials `
  --resource-group rg-aks-3node-lab `
  --name aks-3node-lab `
  --overwrite-existing
```

Then verify:

```powershell
kubectl get nodes -o wide
```

This is especially useful when the AKS cluster has been recreated.

## `InvalidImageName`

If a Pod reports:

```text
InvalidImageName
```

inspect the actual image stored in the StatefulSet template:

```powershell
kubectl get statefulset demo-web -n aks-web-lab -o jsonpath="{.spec.template.spec.containers[0].image}"
```

The value should look similar to:

```text
<ACR_NAME>.azurecr.io/nginx:Prod
```

It should **not** still contain:

```text
__IMAGE__
```

The deployment script is responsible for replacing `__IMAGE__` before applying the manifest.

After correcting the repository source files, rerun the GitHub deployment workflow rather than manually editing the live StatefulSet.

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

Check the AKS kubelet identity:

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

Look at `Events` for scheduling, topology, or resource problems.

## Pods are not perfectly balanced

Inspect:

```powershell
kubectl get pods -n aks-web-lab -o wide
```

The topology constraint is a scheduling rule, not a permanent Pod-to-Node assignment.

With `ScheduleAnyway`, Kubernetes is allowed to accept less-than-perfect spreading when required to keep Pods schedulable.

## GitHub Azure login fails

Verify:

- `AZURE_CLIENT_ID`
- `AZURE_TENANT_ID`
- `AZURE_SUBSCRIPTION_ID`
- The workflow contains `id-token: write`.
- The federated credential matches the repository and `main` branch.
- The Azure role assignments still exist on the lab Resource Group.

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
5. Verify that the Resource Group remains.

The Resource Group itself is intentionally preserved so the existing GitHub OIDC role assignments can be reused for the next deployment.

---

# Full Manual Cleanup

If you intentionally want to remove the Resource Group too:

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
4. Why OIDC avoids long-lived cloud credentials in GitHub.
5. What a StatefulSet is.
6. Why StatefulSet Pods have stable ordinal names.
7. How six Pods are distributed across three Nodes.
8. How topology spread constraints influence scheduling.
9. The difference between Pod identity and Node placement.
10. How a Kubernetes Service selects Pod endpoints.
11. How a LoadBalancer Service exposes an application through Azure.
12. How multiple HTTP requests can reach different replicas.
13. How Kubernetes recreates a deleted StatefulSet Pod.
14. The difference between cordon and drain.
15. How workload Pods can be rescheduled when a Node becomes unavailable.
16. How GitHub Actions can automate Azure infrastructure and Kubernetes deployment.
17. How to inspect Nodes, Pods, Services, and endpoints with `kubectl`.
18. How automated cleanup can remove AKS and ACR while preserving the OIDC Resource Group.

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
- High-availability requirements and Availability Zone design where appropriate.

The public LoadBalancer is intentional for this lab so that the landing page can be accessed directly from the Internet.

---

# References

- GitHub Actions OIDC with Azure: https://docs.github.com/en/actions/how-tos/secure-your-work/security-harden-deployments/oidc-in-azure
- GitHub OIDC reference: https://docs.github.com/en/actions/reference/security/oidc
- Microsoft Entra federated identity credentials: https://learn.microsoft.com/en-us/entra/workload-id/workload-identity-federation-create-trust
- Azure AKS managed identities: https://learn.microsoft.com/en-us/azure/aks/managed-identity-overview
- AKS / ACR integration: https://learn.microsoft.com/en-us/azure/aks/cluster-container-registry-integration
