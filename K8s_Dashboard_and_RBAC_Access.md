# Kubernetes Dashboard — Installation, RBAC & Access

> **Cluster:** 3× Control-Plane (HA) + 2× Worker | **K8s:** v1.30.14 | **Dashboard:** kubernetes-dashboard v7.x
> **Last Updated:** 2026-10-18

---

## Overview

This document covers the complete setup of the Kubernetes Dashboard, two distinct access roles (Admin / Developer), and their access control (RBAC).

### Architecture

```
┌──────────────────────────────────────────────────────────┐
│  Browser (https://10.70.16.237:30874)                    │
│                          │                                │
│                          ▼                                │
│  ┌────────────────────────────────────────────────┐      │
│  │  kubernetes-dashboard-kong-proxy (NodePort)    │      │
│  │  NodePort: 30874 → ContainerPort: 443          │      │
│  └────────────┬───────────────────────────────────┘      │
│               │                                           │
│               ▼                                           │
│  ┌────────────────────────────────────────────────┐      │
│  │  kong → api / auth / web / metrics-scraper     │      │
│  └────────────┬───────────────────────────────────┘      │
│               │                                           │
│               ▼                                           │
│  ┌────────────────────────────────────────────────┐      │
│  │  Kubernetes API Server (Bearer Token auth)     │      │
│  └────────────────────────────────────────────────┘      │
└──────────────────────────────────────────────────────────┘
```

### Role Matrix

| Role | Scope | Permissions | Token SA |
|---|---|---|---|
| **Admin** | Cluster-wide | Full (`cluster-admin`) | `dashboard-admin` |
| **Developer** | `demo` namespace | Full edit (pods, deployments, configmaps, secrets, etc.) | `dashboard-developer` |

---

## 1. Installation

### 1.1 Helm Repository

> **Note:** The old URL (`https://kubernetes.github.io/dashboard/`) was archived in 2026. Use the new URL below.

```bash
# Remove old repo if present
helm repo remove kubernetes-dashboard 2>/dev/null

# Add the correct (new) repo
helm repo add kubernetes-dashboard https://kubernetes-retired.github.io/dashboard/
helm repo update
```

### 1.2 Install Dashboard

```bash
helm upgrade --install kubernetes-dashboard \
  kubernetes-dashboard/kubernetes-dashboard \
  --create-namespace \
  --namespace kubernetes-dashboard
```

### 1.3 Verify

```bash
kubectl -n kubernetes-dashboard get pods
```

**Expected pods (all `1/1 Running`):**

| Pod | Role |
|---|---|
| `kubernetes-dashboard-api-*` | API server |
| `kubernetes-dashboard-auth-*` | Authentication |
| `kubernetes-dashboard-kong-*` | Gateway/Proxy |
| `kubernetes-dashboard-metrics-scraper-*` | Metrics scraper |
| `kubernetes-dashboard-web-*` | Web UI |

> **Tip:** Kong may stay `Init:0/1` for 1–2 minutes — this is normal. Wait with `kubectl -n kubernetes-dashboard get pods -w`.

---

## 2. ServiceAccounts & RBAC

### 2.1 Admin ServiceAccount

**File:** `bootstrap/rbac/admin-user.yaml`

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: dashboard-admin
  namespace: kubernetes-dashboard
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: dashboard-admin-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
  - kind: ServiceAccount
    name: dashboard-admin
    namespace: kubernetes-dashboard
```

**Setup (quick commands):**

```bash
kubectl -n kubernetes-dashboard create serviceaccount dashboard-admin

kubectl create clusterrolebinding dashboard-admin-binding \
  --clusterrole=cluster-admin \
  --serviceaccount=kubernetes-dashboard:dashboard-admin
```

### 2.2 Developer ServiceAccount (scoped to `demo` namespace)

**File:** `bootstrap/rbac/developer-user.yaml`

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: dashboard-developer
  namespace: kubernetes-dashboard
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: demo
  name: developer-role
rules:
  - apiGroups: ["", "apps", "batch", "extensions", "networking.k8s.io"]
    resources:
      - pods
      - pods/log
      - pods/exec
      - deployments
      - replicasets
      - statefulsets
      - services
      - configmaps
      - secrets
      - jobs
      - cronjobs
      - ingresses
      - events
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: developer-rolebinding
  namespace: demo
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: developer-role
subjects:
  - kind: ServiceAccount
    name: dashboard-developer
    namespace: kubernetes-dashboard
```

**Setup (quick commands):**

```bash
kubectl -n kubernetes-dashboard create serviceaccount dashboard-developer

kubectl -n demo create rolebinding developer-rolebinding \
  --clusterrole=edit \
  --serviceaccount=kubernetes-dashboard:dashboard-developer
```

> **Note:** The `edit` ClusterRole is bound to the `demo` namespace via a `RoleBinding` — the developer can edit resources in `demo` but has no access elsewhere in the cluster.

### 2.3 (Optional) Namespace Lister — to populate the UI dropdown

The Dashboard UI calls `list namespaces` to populate its namespace dropdown. If the Developer lacks that permission, **the dropdown appears empty** (even though access to `demo` works). To fix:

**File:** `bootstrap/rbac/developer-viewer.yaml`

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: namespace-lister
rules:
  - apiGroups: [""]
    resources: ["namespaces"]
    verbs: ["get", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: developer-namespace-lister
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: namespace-lister
subjects:
  - kind: ServiceAccount
    name: dashboard-developer
    namespace: kubernetes-dashboard
```

**Trade-off:** The developer can see the **names** of all namespaces (e.g., `kube-system`, `monitoring`), but gets Forbidden when trying to access their contents.

---

## 3. Access Methods

### 3.1 Method 1: NodePort (Production-ready, recommended) 

```bash
kubectl -n kubernetes-dashboard patch svc kubernetes-dashboard-kong-proxy \
  -p '{"spec":{"type":"NodePort"}}'

kubectl -n kubernetes-dashboard get svc kubernetes-dashboard-kong-proxy
```

**Example output:**
```
NAME                              TYPE       CLUSTER-IP      PORT(S)
kubernetes-dashboard-kong-proxy   NodePort   10.98.229.158   443:30874/TCP
                                                                  ↑
```

**In browser (any node IP):**
```
https://10.70.16.237:30874
https://10.70.16.238:30874
https://10.70.16.239:30874
https://10.70.16.240:30874
https://10.70.16.241:30874
```

> **Resets on Helm upgrade:** `helm upgrade` can revert the Service to `ClusterIP` — re-apply the patch. To make it permanent via Helm values:
> ```bash
> helm upgrade kubernetes-dashboard kubernetes-dashboard/kubernetes-dashboard \
>   -n kubernetes-dashboard \
>   --set kong.proxy.type=NodePort --reuse-values
> ```

### 3.2 Method 2: Port-Forward (Local development)

```bash
# With SSH tunnel (for remote VM)
kubectl -n kubernetes-dashboard port-forward \
  svc/kubernetes-dashboard-kong-proxy 8443:443

# Bind to all VM interfaces
kubectl -n kubernetes-dashboard port-forward \
  --address 0.0.0.0 \
  svc/kubernetes-dashboard-kong-proxy 8443:443
```

**In browser:** `https://localhost:8443` (with SSH tunnel) or `https://10.70.16.237:8443` (with `--address 0.0.0.0`)

### 3.3 Method 3: Traefik Ingress (domain-based)

**File:** `bootstrap/dashboard/ingress.yaml`

```yaml
apiVersion: traefik.io/v1alpha1
kind: ServersTransport
metadata:
  name: dashboard-skip-tls
  namespace: kubernetes-dashboard
spec:
  insecureSkipVerify: true
---
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: kubernetes-dashboard
  namespace: kubernetes-dashboard
spec:
  entryPoints: [websecure]
  routes:
    - match: Host(`dashboard.local`)
      kind: Rule
      services:
        - name: kubernetes-dashboard-kong-proxy
          port: 443
          serversTransport: dashboard-skip-tls
```

**`/etc/hosts`:** `10.70.16.237  dashboard.local`

**In browser:** `https://dashboard.local`

---

## 4. Token Generation

### 4.1 Admin Token

```bash
# Display on screen
kubectl -n kubernetes-dashboard create token dashboard-admin --duration=24h

# Save to file
kubectl -n kubernetes-dashboard create token dashboard-admin --duration=24h > /tmp/admin.token
```

### 4.2 Developer Token

```bash
kubectl -n kubernetes-dashboard create token dashboard-developer --duration=24h > /tmp/dev.token
```

### 4.3 Token Characteristics

| Flag | Duration | Use case |
|---|---|---|
| (default) | 1 hour | Short-lived (safer) |
| `--duration=8h` | 8 hours | One shift |
| `--duration=24h` | 24 hours | Lab / dev |
| `--duration=168h` | 7 days |  Not for production |

> ** Expiry:** When the token expires you'll get an `Invalid token` error. Generate a new one with the same command.

---

## 5. Verification

### 5.1 Browser Test

| Step | Expected |
|---|---|
| Open `https://10.70.16.237:30874` | "Your connection is not private" |
| Advanced → Proceed | Login screen |
| Paste Admin token → Sign in | Sidebar shows Nodes, Namespaces, PV, Storage Classes |
| Sign out → Paste Dev token | Only `demo` namespace resources visible |
| `/#/pod?namespace=kube-system` (dev) | **403 Forbidden** |

### 5.2 CLI Verification (most reliable)

```bash
# Admin
kubectl auth can-i '*' '*' \
  --as=system:serviceaccount:kubernetes-dashboard:dashboard-admin
# → yes

# Developer
kubectl auth can-i delete pods -n demo \
  --as=system:serviceaccount:kubernetes-dashboard:dashboard-developer
# → yes

kubectl auth can-i get pods -n kube-system \
  --as=system:serviceaccount:kubernetes-dashboard:dashboard-developer
# → no

kubectl auth can-i list nodes \
  --as=system:serviceaccount:kubernetes-dashboard:dashboard-developer
# → no
```

### 5.3 API Verification (curl)

```bash
ADMIN_TOKEN=$(kubectl -n kubernetes-dashboard create token dashboard-admin --duration=5m)
DEV_TOKEN=$(kubectl -n kubernetes-dashboard create token dashboard-developer --duration=5m)

# Admin — all namespaces
curl -sk https://10.70.16.237:30874/api/v1/namespaces \
  -H "Authorization: Bearer $ADMIN_TOKEN" | jq -r '.items[].metadata.name'

# Dev — pods in demo
curl -sk https://10.70.16.237:30874/api/v1/namespaces/demo/pods \
  -H "Authorization: Bearer $DEV_TOKEN" | jq -r '.items[].metadata.name'

# Dev — forbidden for kube-system
curl -sk https://10.70.16.237:30874/api/v1/namespaces/kube-system/pods \
  -H "Authorization: Bearer $DEV_TOKEN" | jq -r '.message'
# → "pods is forbidden: User ... cannot list resource ..."
```

---

## 6. Troubleshooting

### 6.1 Common Issues

| Issue | Cause | Solution |
|---|---|---|
| `repo ... is not a valid chart repository` (404) | Old URL | Use new URL: `https://kubernetes-retired.github.io/dashboard/` |
| `failed to create token: serviceaccounts "..." not found` | SA not created | Run `create serviceaccount` first |
| `Invalid token` | Token expired | Generate a new token |
| `ERR_CONNECTION_TIMED_OUT` | NodePort blocked | Check `sudo ufw status` / firewall |
| `ERR_CONNECTION_REFUSED` | Kong pod down | `kubectl -n kubernetes-dashboard get pods` |
| Developer UI shows nothing | Dropdown can't list namespaces | Add §2.3 Namespace Lister, or open `/#/pod?namespace=demo` directly |
| Blank page after login | Kong/API pod broken | Check Kong/API logs |
| `no such file /tmp/admin.token` | `/tmp` cleared | Regenerate the token |

### 6.2 Diagnostic Commands

```bash
# Pods ready?
kubectl -n kubernetes-dashboard get pods

# Why is Kong stuck?
kubectl -n kubernetes-dashboard describe pod -l app.kubernetes.io/name=kong | tail -30
kubectl -n kubernetes-dashboard logs -l app.kubernetes.io/name=kong --tail=30

# Events
kubectl -n kubernetes-dashboard get events --sort-by=.lastTimestamp | tail -20

# curl from the VM
curl -kv https://10.70.16.237:30874/ 2>&1 | grep -E 'HTTP|< HTTP'

# Firewall
sudo ufw status | grep 30874
```

---

## 7. Complete Runbook (Copy-Paste)

```bash
# ─────────────────────────────────────────────
# 1. Installation
# ─────────────────────────────────────────────
helm repo remove kubernetes-dashboard 2>/dev/null || true
helm repo add kubernetes-dashboard https://kubernetes-retired.github.io/dashboard/
helm repo update

helm upgrade --install kubernetes-dashboard \
  kubernetes-dashboard/kubernetes-dashboard \
  --create-namespace --namespace kubernetes-dashboard

kubectl -n kubernetes-dashboard get pods -w
# Press Ctrl+C once everything is 1/1 Running

# ─────────────────────────────────────────────
# 2. ServiceAccounts & RBAC
# ─────────────────────────────────────────────
# Admin
kubectl -n kubernetes-dashboard create serviceaccount dashboard-admin
kubectl create clusterrolebinding dashboard-admin-binding \
  --clusterrole=cluster-admin \
  --serviceaccount=kubernetes-dashboard:dashboard-admin

# Developer
kubectl -n kubernetes-dashboard create serviceaccount dashboard-developer
kubectl -n demo create rolebinding developer-rolebinding \
  --clusterrole=edit \
  --serviceaccount=kubernetes-dashboard:dashboard-developer

# (Optional) populate namespace dropdown
kubectl apply -f bootstrap/rbac/developer-viewer.yaml

# ─────────────────────────────────────────────
# 3. NodePort
# ─────────────────────────────────────────────
kubectl -n kubernetes-dashboard patch svc kubernetes-dashboard-kong-proxy \
  -p '{"spec":{"type":"NodePort"}}'
kubectl -n kubernetes-dashboard get svc kubernetes-dashboard-kong-proxy
# 443:30874/TCP ← note the NodePort

# ─────────────────────────────────────────────
# 4. Tokens
# ─────────────────────────────────────────────
kubectl -n kubernetes-dashboard create token dashboard-admin --duration=24h
kubectl -n kubernetes-dashboard create token dashboard-developer --duration=24h

# ─────────────────────────────────────────────
# 5. Verify (4 × yes/no)
# ─────────────────────────────────────────────
kubectl auth can-i '*' '*' --as=system:serviceaccount:kubernetes-dashboard:dashboard-admin
kubectl auth can-i delete pods -n demo --as=system:serviceaccount:kubernetes-dashboard:dashboard-developer
kubectl auth can-i get pods -n kube-system --as=system:serviceaccount:kubernetes-dashboard:dashboard-developer
kubectl auth can-i list nodes --as=system:serviceaccount:kubernetes-dashboard:dashboard-developer

# ─────────────────────────────────────────────
# 6. Browser
# ─────────────────────────────────────────────
# https://10.70.16.237:30874
#   → Advanced → Proceed
#   → Paste token → Sign in
```

---

## 8. Security Notes

| Aspect | Recommendation |
|---|---|
| **Token TTL** | In production use `--duration=8h` max |
| **Cluster-admin** | Break-glass access only; use read-only or scoped Roles in production |
| **NodePort** | Restrict firewall to trusted source IPs only |
| **TLS** | Self-signed → use Let's Encrypt/cert-manager for valid certs in production |
| **NetworkPolicy** | Allow ingress to the Kong pod only from office IPs |
| **Token rotation** | Revoke old tokens and generate fresh ones after 24h |
| **Audit log** | Log all ServiceAccount `dashboard-admin` actions via `audit-policy.yaml` |

### Example restriction (NetworkPolicy)

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: dashboard-allow-office-only
  namespace: kubernetes-dashboard
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: kong
  policyTypes: [Ingress]
  ingress:
    - from:
        - ipBlock:
            cidr: 10.70.16.0/24    # Office subnet
      ports:
        - protocol: TCP
          port: 8443
```

---

## 9. References

- [Kubernetes Dashboard (retired repo)](https://github.com/kubernetes-retired/dashboard)
- [Helm Chart](https://github.com/kubernetes-retired/dashboard/tree/master/charts/helm-chart/kubernetes-dashboard)
- [RBAC Authorization](https://kubernetes.io/docs/reference/access-authn-authz/rbac/)
- [ServiceAccount Tokens](https://kubernetes.io/docs/reference/access-authn-authz/service-accounts-admin/#create-token)
