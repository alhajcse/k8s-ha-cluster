# HAProxy Migration & New Kubernetes Worker Node Join

## Context

This document explains, step by step, how to remove the old HAProxy
server (`10.70.16.234`) from an existing Kubernetes cluster, convert it
into a new worker node, and configure a new HAProxy server
(`10.70.16.235`) as the Kubernetes API endpoint.

> **Warning:** These operations can disrupt a production-like cluster.
> Stopping HAProxy on `10.70.16.234` may affect API connectivity. Before
> proceeding, verify the current API endpoint, certificate SANs,
> services running on `.235`, backups, and the rollback plan. In
> particular, if Prometheus, Grafana, Loki, or other monitoring services
> are running on `.235`, plan the HAProxy deployment so those services
> are not disrupted.

## Target Architecture

-   **New HAProxy:** `10.70.16.235` --- DNS alias `k8s-api.local`
-   **Control Plane:** `10.70.16.237`, `10.70.16.238`, `10.70.16.239`
-   **Worker Nodes:** `10.70.16.240`, `10.70.16.241`, and the new worker
    `10.70.16.234` (`node1-vm-03`)

------------------------------------------------------------------------

## Phase 1: Set Up the New HAProxy (`.235`) and Stop the Old HAProxy (`.234`)

### 1.1 Stop the Old HAProxy (`.234`)

Since `.234` will become a Kubernetes worker node, HAProxy must be
stopped on that host. **First verify how HAProxy is running, then use
only the applicable method.**

If it runs as a systemd service:

``` bash
ssh vm@10.70.16.234 \
  "sudo systemctl stop haproxy && sudo systemctl disable haproxy"
```

If it runs as a Docker container, inspect it first:

``` bash
ssh vm@10.70.16.234 "docker ps --filter name=haproxy"
```

After verifying that it is the correct container, remove it if
necessary:

``` bash
ssh vm@10.70.16.234 "docker rm -f haproxy"
```

> Do not blindly run `docker rm -f node-exporter`. Node Exporter may be
> required for monitoring; converting the host into a Kubernetes worker
> does not automatically mean it must be removed.

### 1.2 Configure the New HAProxy (`.235`)

On the new HAProxy server, add the Kubernetes API frontend/backend
configuration to `/etc/haproxy/haproxy.cfg`. Merge the following block
with the existing configuration; do not overwrite the entire file.

``` haproxy
frontend k8s_api_frontend
    bind *:6443
    mode tcp
    option tcplog
    default_backend k8s_api_backend

backend k8s_api_backend
    mode tcp
    option tcp-check
    balance roundrobin
    server cp1 10.70.16.237:6443 check
    server cp2 10.70.16.238:6443 check
    server cp3 10.70.16.239:6443 check
```

Validate the configuration:

``` bash
sudo haproxy -c -f /etc/haproxy/haproxy.cfg
```

If validation succeeds, restart HAProxy:

``` bash
sudo systemctl restart haproxy
sudo systemctl status haproxy --no-pager
```

**Note:** If HAProxy runs in a Docker container,
`systemctl restart haproxy` may not apply. Use the deployment method for
your Docker Compose setup instead.

### 1.3 API Endpoint DNS and Certificate SANs

Ensure that `k8s-api.local` resolves to `10.70.16.235` on every
control-plane node, worker node, and your local laptop.

To add an entry to `/etc/hosts` on a Linux host:

``` bash
echo "10.70.16.235 k8s-api.local" | sudo tee -a /etc/hosts
```

Before adding the entry on each host, check for duplicates:

``` bash
grep -n 'k8s-api.local' /etc/hosts
```

Verify name resolution:

``` bash
getent hosts k8s-api.local
```

> **Important:** `/etc/hosts` only provides name resolution; it does not
> modify the TLS certificate SANs. The Kubernetes API server certificate
> must include `k8s-api.local` as a SAN. If it does not, using the DNS
> name in kubeconfig may still produce an `x509` certificate error.
> Verify the certificate before making changes.

------------------------------------------------------------------------

## Phase 2: Update Kubernetes Configuration

Before migrating to the new API endpoint, verify the current
configuration and cluster health on the control-plane and worker nodes.
Do not run bulk `sed` commands against Kubernetes configuration without
backups.

### 2.1 Inspect and Back Up Node Kubeconfigs

The following loop creates backups of `/etc/kubernetes/*.conf` on each
node. Run it only after confirming that `k8s-api.local:6443` is
reachable through the new HAProxy and that the certificate SAN is
correct.

``` bash
for ip in \
  10.70.16.237 \
  10.70.16.238 \
  10.70.16.239 \
  10.70.16.240 \
  10.70.16.241
do
  echo "Checking $ip..."

  ssh vm@"$ip" '
    set -e
    sudo grep -RniE "server: https://" /etc/kubernetes/*.conf 2>/dev/null || true
    sudo tar -czf "/tmp/kubernetes-conf-backup-$(date +%Y%m%d-%H%M%S).tar.gz" \
      /etc/kubernetes/*.conf
  '
done
```

> **Do not run a bulk replacement like the one below without a plan.**
> Whether every `.237` address needs to be replaced depends on the file.
> Control-plane configuration, kubelet client configuration, and the
> admin kubeconfig have different purposes. Review the `grep` output,
> then change and validate one node at a time.

To inspect the API endpoints in Kubernetes configuration files:

``` bash
sudo grep -RniE '10\.70\.16\.(234|237)|server: https://' /etc/kubernetes/*.conf
```

If a specific kubeconfig needs its API server URL changed to
`https://k8s-api.local:6443`, back up that file and edit it selectively.
Do not blindly modify every `.conf` file.

### 2.2 Update the Local Laptop Kubeconfig

Back up the local kubeconfig:

``` bash
cp ~/.kube/config ~/.kube/config.backup-$(date +%Y%m%d-%H%M%S)
```

Inspect the current endpoint:

``` bash
kubectl config view --minify
```

Set the `clusters[].cluster.server` field for the intended cluster
context in `~/.kube/config` to `https://k8s-api.local:6443`. If multiple
clusters or contexts exist, update the intended context rather than
running a global `sed` replacement.

Verify the change:

``` bash
kubectl cluster-info
kubectl get nodes -o wide
```

------------------------------------------------------------------------

## Phase 3: Prepare the New Worker Node (`.234`)

### 3.1 Reset and Clean Up (`.234`)

**Warning:** `kubeadm reset` removes Kubernetes configuration from this
node. Verify the IP address and hostname, and run it only on
`10.70.16.234`.

``` bash
ssh vm@10.70.16.234 'hostname; ip -brief address'
```

After confirming that this is the correct node:

``` bash
ssh vm@10.70.16.234 "sudo kubeadm reset -f"
ssh vm@10.70.16.234 "sudo rm -rf /etc/cni/net.d"
```

If a local kubeconfig exists in the `vm` user's home directory and you
intend to remove it, inspect it first:

``` bash
ssh vm@10.70.16.234 'ls -la ~/.kube 2>/dev/null || true'
```

Then, if required:

``` bash
ssh vm@10.70.16.234 "rm -rf ~/.kube"
```

### 3.2 Verify the Containerd CRI Configuration

The previous error was:

``` text
[ERROR CRI]: container runtime is not running
```

First inspect the service and configuration:

``` bash
ssh vm@10.70.16.234 \
  "sudo systemctl status containerd --no-pager; sudo containerd config dump | head -n 40"
```

Do not move or remove `/etc/containerd/config.toml` without creating a
backup. If resetting the configuration is necessary, back it up and
create a CRI configuration compatible with your Kubernetes version. Then
run:

``` bash
ssh vm@10.70.16.234 "sudo systemctl restart containerd"
ssh vm@10.70.16.234 "sudo systemctl status containerd --no-pager"
ssh vm@10.70.16.234 "sudo crictl info"
```

> Removing `containerd config.toml` is not the right solution in every
> environment. Inspect the containerd configuration, `SystemdCgroup`
> setting, and CRI plugin status before changing anything.

### 3.3 Prepare the VM with Ansible

From the repository root, run the playbook for `.234`:

``` bash
ansible-playbook \
  -i ansible/inventory/local/hosts.ini \
  ansible/playbooks/site.yml \
  --limit 10.70.16.234
```

If the host is identified by a hostname rather than its IP address in
the Ansible inventory, use the correct inventory host pattern with
`--limit`.

After preparation, verify:

``` bash
ssh vm@10.70.16.234 \
  "sudo systemctl is-active containerd; kubeadm version; kubelet --version"
```

------------------------------------------------------------------------

## Phase 4: Join the New Worker Node to the Cluster

### 4.1 Generate a Join Command

Generate a new join command on control-plane node `10.70.16.237`:

``` bash
ssh vm@10.70.16.237 \
  "sudo kubeadm token create --print-join-command"
```

The output contains a token and CA certificate hash. Treat the token as
sensitive and do not publish it in a public repository or chat.

### 4.2 Join Through the New Endpoint (`.234`)

First confirm that the control-plane API is reachable through
`k8s-api.local:6443` and certificate validation works.

Then connect to `.234`:

``` bash
ssh vm@10.70.16.234
```

Run the join command using the actual token and hash returned by the
control-plane command:

``` bash
sudo kubeadm join k8s-api.local:6443 \
  --token <YOUR_TOKEN> \
  --discovery-token-ca-cert-hash sha256:<YOUR_CA_CERT_HASH>
```

Replace `<YOUR_TOKEN>` and `<YOUR_CA_CERT_HASH>` with the actual values
from the command output. Do not run the command with the angle-bracket
placeholders unchanged.

------------------------------------------------------------------------

## Phase 5: Verification

### 5.1 Check Node Status

From a control-plane node:

``` bash
ssh vm@10.70.16.237 \
  "sudo kubectl --kubeconfig=/etc/kubernetes/admin.conf get nodes -o wide"
```

All nodes should eventually report `Ready`. The new worker's name will
match its actual hostname.

Example output:

``` text
NAME          STATUS   ROLES           VERSION
k8s-cp-02     Ready    control-plane   v1.30.14
k8s-cp-03     Ready    control-plane   v1.30.14
node1-vm-03   Ready    <none>          v1.30.14
node3-vm-01   Ready    control-plane   v1.30.14
node4-vm-01   Ready    <none>          v1.30.14
node4-vm-02   Ready    <none>          v1.30.14
```

Node names, roles, and versions may differ from this example; use the
actual cluster output.

### 5.2 Check the API Endpoint

On the new HAProxy host, `10.70.16.235`:

``` bash
sudo ss -lntp | grep ':6443'
```

Test the API endpoint:

``` bash
curl -k https://k8s-api.local:6443/healthz
```

`curl -k` bypasses certificate verification and is only a connectivity
smoke test. Do not use `-k` for production verification.

A better validation is:

``` bash
kubectl --server=https://k8s-api.local:6443 \
  --certificate-authority=/path/to/cluster-ca.crt \
  get --raw=/healthz
```

Replace `/path/to/cluster-ca.crt` with the correct CA certificate path.

### 5.3 Verify HAProxy Backend Health / Stats

If an HAProxy Stats frontend is already configured, open its configured
URL in a browser. For example, `http://10.70.16.235:7000/` will work
only if the HAProxy configuration enables the Stats listener on that
address and port.

On the Stats page, verify that all three backends---`cp1`, `cp2`, and
`cp3`---under `k8s_api_backend` show `UP`.

If HAProxy Stats has not been configured, port `7000` will not become
available automatically. Add the configuration and validate it first.

------------------------------------------------------------------------

## Rollback Checklist

If API connectivity is lost during migration:

1.  Check HAProxy backend health and reachability of port `6443` on the
    control-plane nodes.
2.  Restore the required previous endpoint from the backups of
    `~/.kube/config` and node configuration.
3.  Before restarting the old HAProxy on `.234`, confirm whether `.234`
    has already been reset or joined as a worker and ensure its role is
    clear in the rollback plan.
4.  Verify cluster status with `kubectl get nodes`.
5.  Avoid further cleanup until all nodes are `Ready` and the new API
    endpoint is stable.

## Final Validation Checklist

-   [ ] `k8s-api.local` resolves to `10.70.16.235` from every required
    host.
-   [ ] The API server certificate includes `k8s-api.local` as a SAN.
-   [ ] HAProxy configuration validation succeeds.
-   [ ] All three control-plane backends show `UP`.
-   [ ] `kubectl get nodes` works from the local laptop.
-   [ ] `10.70.16.234` has joined as a worker node.
-   [ ] All Kubernetes nodes are `Ready`.
-   [ ] Monitoring services remain operational.
-   [ ] Rollback backups are stored in a safe location.
