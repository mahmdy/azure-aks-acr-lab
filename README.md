# AKS 3-Node / 6-Pod ACR Web Demo

A hands-on Azure Kubernetes Service (AKS) lab that demonstrates how a container image moves from Azure Container Registry (ACR) into an AKS cluster, how Kubernetes distributes StatefulSet Pods across three Nodes, and how an Azure Load Balancer exposes the application to the Internet.

## What This Project Demonstrates

The project automates the following architecture:

```text
                         Azure
                           |
             +-------------+-------------+
             |                           |
             v                           v
            ACR                         AKS
             |                           |
       nginx:Prod                 3 Worker Nodes
             |                  Zone 1 / 2 / 3
             |                           |
             |                  +--------+--------+
             |                  |        |        |
             |                  v        v        v
             |                Node 1  Node 2  Node 3
             |                  |        |        |
             |                  +--------+--------+
             |                           |
             |                    6 StatefulSet Pods
             |                    demo-web-0 ... demo-web-5
             |                           |
             +---------------------------+
                                         |
                                  LoadBalancer Service
                                         |
                                         v
                                     Internet
```

The intended application flow is:

```text
NGINX Image
    ↓
Azure Container Registry
    ↓
AKS pulls image
    ↓
StatefulSet
    ↓
6 Pods
    ↓
Pods distributed across 3 Nodes
    ↓
Kubernetes Service
    ↓
Azure Load Balancer
    ↓
Internet
```

Each Pod exposes a landing page showing information about itself, including:

- Pod name
- Pod sequence number
- Pod IP
- Node name
- Availability Zone
- Image being used

This makes the Kubernetes scheduling and load-balancing behavior visible instead of hiding it behind a normal NGINX page.

---

# Project Files

The project uses two main files.

## 1. `deploy-aks-3node-6pod-lab.ps1`

This is the main automation script.

It minimizes manual interaction and automates Azure resource creation, ACR image preparation, AKS configuration, Kubernetes deployment, and verification.

## 2. `aks-3node-6pod-lab.yaml`

This is the Kubernetes manifest.

It defines the Kubernetes application workload and Service.

---

# Prerequisites

The deployment is designed for Windows PowerShell.

You need:

- An active Azure subscription
- Azure CLI
- `kubectl`
- Permission to create Azure resources
- An Azure region that supports the requested AKS configuration

Check Azure CLI:

```powershell
az version
```

Check `kubectl`:

```powershell
kubectl version --client
```

Log in to Azure:

```powershell
az login
```

Verify the active subscription:

```powershell
az account show
```

If you have multiple subscriptions:

```powershell
az account list -o table
```

Select the required subscription:

```powershell
az account set --subscription "<SUBSCRIPTION_ID_OR_NAME>"
```

---

# Resource Design

The default deployment uses:

| Resource | Configuration |
|---|---|
| Azure Region | East US |
| AKS Nodes | 3 |
| Node VM size | Standard_D4s_v5 |
| Application replicas | 6 |
| Application image | NGINX |
| ACR tag | `Prod` |
| Kubernetes workload | StatefulSet |
| External Service | LoadBalancer |
| Availability Zones | 1, 2, 3 |

The design intentionally uses three nodes and six application Pods so the lab can demonstrate distribution across nodes.

The application workload uses a StatefulSet because StatefulSet Pods receive stable, ordinal names:

```text
demo-web-0
demo-web-1
demo-web-2
demo-web-3
demo-web-4
demo-web-5
```

This makes the Pod sequence visible and predictable for the lab.

---

# Why StatefulSet?

A normal Deployment creates interchangeable Pods whose generated names change when Pods are recreated.

A StatefulSet provides stable ordinal identities.

With:

```yaml
replicas: 6
```

the Pods are created with sequence numbers:

```text
demo-web-0
demo-web-1
demo-web-2
demo-web-3
demo-web-4
demo-web-5
```

The sequence number is useful for this lab because every landing page can identify which StatefulSet replica served the request.

This project is using StatefulSet primarily for the educational value of stable Pod identity. The application itself is stateless.

---

# Why Three Nodes?

Three Nodes allow the exercise to demonstrate workload distribution.

The target layout is:

```text
Node 1
├── demo-web-x
└── demo-web-x

Node 2
├── demo-web-x
└── demo-web-x

Node 3
├── demo-web-x
└── demo-web-x
```

The exact Pod-to-Node assignment is made by the Kubernetes scheduler.

The manifest uses topology spread constraints to request balanced distribution across the Nodes/availability zones.

Important:

> Kubernetes scheduling expresses placement constraints; it does not mean that Pod ordinal `demo-web-0` is permanently assigned to a particular Node.

If a Pod is recreated, Kubernetes can place it on another suitable Node.

---

# Why Availability Zones?

The AKS Node pool is configured across three Availability Zones:

```text
Zone 1 → Node
Zone 2 → Node
Zone 3 → Node
```

This makes the exercise more realistic and demonstrates how Kubernetes can spread application replicas across failure domains.

The application Pods use topology spread constraints so Kubernetes attempts to maintain an even distribution.

---

# Why ACR?

The container image is not pulled directly from Docker Hub by AKS.

The intended flow is:

```text
Docker Hub
    ↓
ACR import
    ↓
ACR
    ↓
AKS
```

The image is stored in ACR with the tag:

```text
Prod
```

The final image reference has this structure:

```text
<ACR_NAME>.azurecr.io/nginx:Prod
```

The AKS cluster is granted permission to pull from the ACR.

This demonstrates a common Azure container workflow:

```text
Container Image
      ↓
Security / CI/CD
      ↓
ACR
      ↓
AKS
```

---

# Automated Deployment

## Step 1 — Download or clone the repository

Clone the repository:

```powershell
git clone <YOUR_REPOSITORY_URL>
```

Move into the project:

```powershell
cd <YOUR_REPOSITORY_DIRECTORY>
```

Verify the files:

```powershell
Get-ChildItem
```

You should have:

```text
deploy-aks-3node-6pod-lab.ps1
aks-3node-6pod-lab.yaml
```

---

# Step 2 — Allow the PowerShell script to run

If PowerShell blocks local scripts, use a process-level execution policy:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
```

This changes the policy only for the current PowerShell session.

---

# Step 3 — Run the automation

Run:

```powershell
.\deploy-aks-3node-6pod-lab.ps1
```

The script is designed to minimize user interaction.

It asks for the important naming variables and uses defaults for the rest.

Typical inputs include:

```text
Resource Group name
AKS cluster name
ACR name
```

Use globally unique names for the ACR.

For example:

```text
Resource Group:
rg-aks-demo

AKS:
aks-demo

ACR:
aksdemomacr12345
```

---

# Step 4 — What the Script Automates

After the variables are entered, the script handles the main workflow automatically.

Conceptually:

```text
1. Create Resource Group
          ↓
2. Create ACR
          ↓
3. Import NGINX image into ACR
          ↓
4. Create AKS
          ↓
5. Configure AKS access to ACR
          ↓
6. Get AKS credentials
          ↓
7. Prepare Kubernetes manifest
          ↓
8. Deploy StatefulSet
          ↓
9. Deploy LoadBalancer Service
          ↓
10. Wait for Pods
          ↓
11. Display Nodes
          ↓
12. Display Pods
          ↓
13. Display Service / Public IP
```

---

# Step 5 — Verify the AKS Nodes

After deployment:

```powershell
kubectl get nodes -o wide
```

Expected result:

```text
NAME                                      STATUS   ROLES
aks-...-vmss000000                        Ready    <none>
aks-...-vmss000001                        Ready    <none>
aks-...-vmss000002                        Ready    <none>
```

You should have three Ready Nodes.

---

# Step 6 — Verify the Six Pods

Run:

```powershell
kubectl get pods -o wide
```

Expected:

```text
NAME          READY   STATUS    IP            NODE
demo-web-0    1/1     Running   ...           ...
demo-web-1    1/1     Running   ...           ...
demo-web-2    1/1     Running   ...           ...
demo-web-3    1/1     Running   ...           ...
demo-web-4    1/1     Running   ...           ...
demo-web-5    1/1     Running   ...           ...
```

The important columns are:

```text
NAME
STATUS
IP
NODE
```

The `NODE` column tells you where each Pod is running.

---

# Step 7 — Check Pod Distribution

A useful command is:

```powershell
kubectl get pods -o custom-columns="POD:.metadata.name,NODE:.spec.nodeName,IP:.status.podIP,STATUS:.status.phase"
```

Example:

```text
POD          NODE                         IP             STATUS
demo-web-0   aks-...000000                10.244.x.x     Running
demo-web-1   aks-...000001                10.244.x.x     Running
demo-web-2   aks-...000002                10.244.x.x     Running
demo-web-3   aks-...000000                10.244.x.x     Running
demo-web-4   aks-...000001                10.244.x.x     Running
demo-web-5   aks-...000002                10.244.x.x     Running
```

The important learning point is:

```text
6 Pods
   ↓
3 Nodes
```

with Kubernetes attempting to keep the distribution balanced.

---

# Step 8 — Verify the StatefulSet

Run:

```powershell
kubectl get statefulset
```

Expected:

```text
NAME       READY
demo-web   6/6
```

You can get more details:

```powershell
kubectl describe statefulset demo-web
```

---

# Step 9 — Verify the Service

Run:

```powershell
kubectl get services
```

You should see a LoadBalancer Service.

For example:

```text
NAME         TYPE           CLUSTER-IP     EXTERNAL-IP
demo-web     LoadBalancer   10.x.x.x       xx.xx.xx.xx
```

The important value is:

```text
EXTERNAL-IP
```

That is the public IP assigned by Azure.

---

# Step 10 — Access the Application

Get the public IP:

```powershell
kubectl get service demo-web
```

Then open:

```text
http://<EXTERNAL-IP>
```

You can also test with PowerShell:

```powershell
curl.exe http://<EXTERNAL-IP>
```

The response should contain information similar to:

```text
================================
       AKS 3-Node / 6-Pod Demo
================================

Pod Sequence:       3
Pod Name:           demo-web-3
Pod IP:             10.244.x.x

Node:
aks-...-vmss000001

Availability Zone:
2

Image:
<ACR_NAME>.azurecr.io/nginx:Prod

================================
```

---

# Understanding the Landing Page

The page is designed to make Kubernetes scheduling visible.

## Pod Sequence

Example:

```text
demo-web-3
```

The `3` is the StatefulSet ordinal.

## Pod Name

The Kubernetes-generated stable StatefulSet identity:

```text
demo-web-3
```

## Pod IP

The internal IP assigned to the Pod.

Example:

```text
10.244.x.x
```

## Node

The AKS Node hosting the Pod.

Example:

```text
aks-...-vmss000001
```

## Availability Zone

The Azure Availability Zone where the Node is located.

---

# Step 11 — Demonstrate Load Balancing

The easiest way to demonstrate traffic distribution is to make multiple requests.

PowerShell:

```powershell
$IP="<EXTERNAL-IP>"

for ($i=1; $i -le 20; $i++) {
    Write-Host "Request $i"
    curl.exe -s --no-keepalive "http://$IP"
    Write-Host ""
}
```

Because the landing page identifies the Pod and Node, you can observe which replica responds.

You may see:

```text
Request 1 → demo-web-2
Request 2 → demo-web-5
Request 3 → demo-web-0
Request 4 → demo-web-3
...
```

Do not expect strict round-robin ordering.

Kubernetes/Azure load balancing distributes traffic among eligible endpoints; it does not promise an exact sequence such as:

```text
0 → 1 → 2 → 3 → 4 → 5
```

---

# Step 12 — Observe Endpoints

The Service selects Pods and creates endpoints for eligible Pods.

Check them:

```powershell
kubectl get endpoints demo-web
```

You can also inspect EndpointSlices:

```powershell
kubectl get endpointslices
```

EndpointSlices provide the endpoint information used by Kubernetes networking.

---

# Step 13 — Observe the Service Selector

Inspect the Service:

```powershell
kubectl describe service demo-web
```

Look for:

```text
Selector:
```

The selector must match the labels applied to the StatefulSet Pods.

This is the relationship:

```text
Service
   |
   | selector
   v
Pods with matching labels
```

---

# Step 14 — Observe the Workload Distribution

Use:

```powershell
kubectl get pods -o wide
```

Then compare the `NODE` column.

You can also group Pods by Node in PowerShell:

```powershell
kubectl get pods -o custom-columns="POD:.metadata.name,NODE:.spec.nodeName" |
    Select-Object -Skip 1 |
    Group-Object { ($_ -split '\s+')[1] } |
    Format-Table Name, Count
```

The target educational result is approximately:

```text
Node 1 → 2 Pods
Node 2 → 2 Pods
Node 3 → 2 Pods
```

The actual scheduler result should be verified rather than assumed.

---

# Step 15 — Test Pod Self-Healing

This is a useful extension to the lab.

First list the Pods:

```powershell
kubectl get pods -o wide
```

Delete one:

```powershell
kubectl delete pod demo-web-0
```

Then watch:

```powershell
kubectl get pods -w
```

The StatefulSet controller should create a replacement with the same ordinal identity:

```text
demo-web-0
```

This demonstrates one of the important StatefulSet properties:

```text
Pod demo-web-0
      ↓
deleted
      ↓
replacement
      ↓
demo-web-0
```

The replacement may be scheduled on a different Node.

---

# Step 16 — Verify the Replacement Node

After the Pod returns to `Running`:

```powershell
kubectl get pods -o wide
```

Compare:

```text
demo-web-0
```

before and after the failure.

The Pod identity remains:

```text
demo-web-0
```

while the Node assignment can change.

This demonstrates the difference between:

```text
Pod identity
```

and:

```text
Pod placement
```

---

# Troubleshooting

## `ImagePullBackOff`

Check:

```powershell
kubectl describe pod <POD_NAME>
```

Look at:

```text
Events:
```

If you see:

```text
401 Unauthorized
```

the AKS workload likely does not have permission to pull from ACR.

Verify the ACR attachment/configuration and the AKS identity permissions.

---

## Service Has No External IP

Run:

```powershell
kubectl get service demo-web
```

If:

```text
EXTERNAL-IP
<pending>
```

wait and check again:

```powershell
kubectl get service demo-web -w
```

Azure may need time to provision the Load Balancer and public IP.

---

## Pods Are Not Running

Run:

```powershell
kubectl get pods -o wide
```

Then:

```powershell
kubectl describe pod <POD_NAME>
```

Always inspect:

```text
Events:
```

Events normally provide the most useful first indication of why a Pod cannot start.

---

## No Pods Appear

Check the StatefulSet:

```powershell
kubectl get statefulset
```

Then:

```powershell
kubectl describe statefulset demo-web
```

---

## Wrong Namespace

List everything:

```powershell
kubectl get pods -A
```

If a resource belongs to a particular namespace:

```powershell
kubectl get pods -n <namespace>
```

Remember:

```powershell
kubectl get pods
```

only shows Pods in the current namespace.

---

# Useful Commands

## Cluster

```powershell
kubectl cluster-info
```

```powershell
kubectl get nodes -o wide
```

## StatefulSet

```powershell
kubectl get statefulset
```

```powershell
kubectl describe statefulset demo-web
```

## Pods

```powershell
kubectl get pods -o wide
```

```powershell
kubectl get pods -w
```

```powershell
kubectl describe pod <POD_NAME>
```

## Services

```powershell
kubectl get services
```

```powershell
kubectl describe service demo-web
```

## Endpoints

```powershell
kubectl get endpoints demo-web
```

```powershell
kubectl get endpointslices
```

## ACR

```powershell
az acr show --name <ACR_NAME> -o table
```

```powershell
az acr repository show-tags `
    --name <ACR_NAME> `
    --repository nginx `
    -o table
```

---

# Cleanup

The lab creates Azure resources that can generate charges.

When finished, delete the entire Resource Group:

```powershell
az group delete `
    --name <RESOURCE_GROUP_NAME> `
    --yes `
    --no-wait
```

This removes the resources belonging to the lab Resource Group, including the AKS cluster and ACR if they were created in that Resource Group.

Verify the Resource Group:

```powershell
az group show --name <RESOURCE_GROUP_NAME>
```

If deletion is still in progress, wait and check again.

---

# What You Should Learn From This Lab

After completing the exercise, you should be able to explain:

1. How a container image is stored in ACR.
2. How AKS authenticates to ACR to pull a private image.
3. What a StatefulSet does.
4. Why StatefulSet Pods have ordinal names.
5. How six Pods can be distributed across three Nodes.
6. How topology spread constraints influence Pod placement.
7. The difference between a Pod and a Node.
8. The difference between a Service and a Pod.
9. How a LoadBalancer Service exposes an application externally.
10. How Service endpoints connect a Service to Pods.
11. How requests can reach different replicas.
12. How Kubernetes recreates a failed StatefulSet Pod.
13. Why Pod identity and Node placement are different concepts.
14. How to inspect Kubernetes scheduling and networking using `kubectl`.

---

# Lab Architecture Summary

```text
                       Internet
                          |
                          v
                Azure Public IP
                          |
                          v
              Azure Load Balancer
                          |
                          v
               Kubernetes Service
                          |
             +------------+------------+
             |            |            |
             v            v            v
          Pod 0         Pod 1        Pod 2
             |            |            |
             +------------+------------+
                          |
                    Additional Pods
                          |
          +---------------+---------------+
          |               |               |
          v               v               v
       Node 1           Node 2          Node 3
       Zone 1           Zone 2          Zone 3

                    AKS Cluster
                          ^
                          |
                          |
                  ACR image pull
                          |
                          v
                Azure Container Registry
                   nginx:Prod
```

---

# Security and Cost Notes

This is a learning lab, not a production reference architecture.

Before using it in production:

- Review VM sizing.
- Review node-pool architecture.
- Use appropriate network controls.
- Restrict public exposure where possible.
- Use HTTPS/TLS for real applications.
- Apply appropriate RBAC.
- Review ACR permissions.
- Configure monitoring and logging.
- Review resource requests and limits.
- Consider dedicated user node pools for application workloads.
- Consider private AKS/API and private ACR designs where appropriate.

The lab uses a public LoadBalancer intentionally so the application can be accessed easily during the exercise.

Remember to delete the Resource Group when the lab is finished to avoid unnecessary Azure charges.

---

# License

Use and modify this lab for educational and demonstration purposes.
