### Port plan

| Port | Purpose | State |
|---|---|---|
| `6443` | Kubernetes API HAProxy | Existing; do not change during ingress setup |
| `30080` | Proposed Traefik HTTP NodePort | Not yet confirmed or installed |
| `30443` | Proposed Traefik HTTPS NodePort | Not yet confirmed or installed |
| `30400` | Longhorn frontend NodePort | Existing |

Recheck NodePort allocation immediately before installation. Do not assume `30080` and `30443` are free based only on an earlier snapshot.

---

## 7. Pre-Install Checks

Run on `node3-vm-01` just before installation:

```bash
kubectl get svc -A -o wide
kubectl get nodes -o wide
kubectl get nodes -o custom-columns=NAME:.metadata.name,TAINTS:.spec.taints
```

**Why:** Confirms the current Services, node addresses, readiness, and scheduling taints immediately before making a change.

Confirm that NodePorts `30080` and `30443` are not already allocated. The earlier recorded Service output showed Longhorn on `30400`, but state can change over time.

## Traefik chart version
Official chart repository:
```
helm repo add traefik https://traefik.github.io/charts
helm repo update
helm search repo traefik/traefik --versions | head -20
```
Ypur cluster version v1.30.14; follow minor version of Traefik

39.x chart version
```
helm search repo traefik/traefik --versions | grep '39\.'
```

Chart metadata
```
helm show chart traefik/traefik --version 39.0.9
```
Follow kubeVersion, version and appVersion

NodePort configuration verify
```
helm show values traefik/traefik --version 39.0.9 \
  | grep -n -A 45 '^  web:'

helm show values traefik/traefik --version 39.0.9 \
  | grep -n -A 45 '^  websecure:'

helm show values traefik/traefik --version 39.0.9 \
  | grep -n -A 20 '^service:'

  ```


Cluster port conflict verify
```
kubectl get nodes
kubectl get svc -A | grep NodePort || true
helm list -A
```

### Compatibility warning

The cluster uses Kubernetes `v1.30.14`, an old minor release. Before production use, verify the chosen Traefik chart's 
supported Kubernetes versions and plan an upgrade to a currently supported Kubernetes release. Do not assume the newest chart is compatible merely because Helm can download it.

---

## 8. traefik/values.yaml

The following is a **draft**, not a confirmed working configuration. Confirm the exact 
NodePort field names and nesting in the full values for chart version `39.0.9` before using it.

```cd ~/Documents/k8s-ha-cluster
mkdir -p traefik

cat > traefik/values.yaml <<'YAML'
deployment:
  enabled: true
  kind: Deployment
  replicas: 2

service:
  enabled: true
  type: NodePort

ports:
  web:
    port: 8000
    exposedPort: 80
    nodePort: 30080
    expose:
      default: true

  websecure:
    port: 8443
    exposedPort: 443
    nodePort: 30443
    expose:
      default: true

providers:
  kubernetesIngress:
    enabled: true
  kubernetesCRD:
    enabled: true

ingressClass:
  enabled: true
  isDefaultClass: false
  name: traefik
YAML
```

Do not treat this draft as a validated configuration. Inspect the full chart values and rendered Service manifest first.

2. Configuration server copy if needed
```
scp traefik/values.yaml vm@10.70.16.237:/tmp/traefik-values.yaml
```

### 8.1 Render chart manifests locally (no installation)

After correcting the values file to match the chart schema:

```bash
helm repo add traefik https://traefik.github.io/charts
helm repo update

helm template traefik traefik/traefik \
  --version 39.0.9 \
  --namespace traefik \
  --values /tmp/traefik-values.yaml \
  > /tmp/traefik-rendered.yaml
```

**Why:** Renders the Kubernetes manifests locally so they can be inspected without creating resources in the cluster.

generated configuration verify:
```
grep -n -E 'kind: (Deployment|Service|IngressClass)|nodePort:|replicas:|type: NodePort' \
  /tmp/traefik-rendered.yaml
```

Confirm that the rendered Service has type `NodePort` and the intended HTTP/HTTPS NodePorts before continuing.

### 8.2 Namespace create and Server-side dry run (does not persist resources)

```bash
kubectl create namespace traefik \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl apply --dry-run=server -f /tmp/traefik-rendered.yaml
```

**Why:** Asks the API server to validate the rendered objects without saving them. A successful dry run 
does not guarantee that Pods will schedule, images will pull, or network traffic will work.

If this reports errors, stop and resolve them before installation.

### 8.3 Install only after compatibility and validation checks pass

**Cluster-changing command — do not run until all checks above pass:**

```bash
helm upgrade --install traefik traefik/traefik \
  --version 39.0.9 \
  --namespace traefik \
  --values /tmp/traefik-values.yaml \
  --wait \
  --timeout 5m
```

### 8.4 Verify after installation

```bash
kubectl get pods,svc -n traefik -o wide
kubectl get ingressclass
```

**Why:** Checks Pod placement/readiness, Service type and ports, and whether the Deployment rollout completed.

Expected only after a successful installation: two ready Traefik replicas and a NodePort Service exposing the verified ports. If the chart creates a differently named Deployment, use `kubectl get deploy -n traefik` to find its actual name.
