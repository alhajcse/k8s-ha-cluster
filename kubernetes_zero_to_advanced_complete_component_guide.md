---
author: Alhaj Uddin
date: 2026-10-14
level: Beginner to Advanced
subtitle: Architecture, Components, Networking, Storage,
  Security, HA, Observability ও Troubleshooting
tags:
- kubernetes
- devops
- sre
- platform-engineering
title: Kubernetes Zero to Advanced --- Complete Component Guide
---

# Kubernetes Zero to Advanced

## Complete Component Guide
Purpose: Understand what each important Kubernetes component is, why it is needed, 
how components interact with one another, what happens when a component fails, and how to 
troubleshoot issues step by step. This is a learning guide. Before running any command, 
verify your cluster version, network ranges, credentials, and environment.

## Table of Contents

1.  Learning path and prerequisite
2.  What Is Kubernetes and What Problems Does It Solve?
3.  Core architecture and control loop
4.  API objects and API Server request flow
5.  Control Plane components
6.  Worker node components
7.  etcd and cluster state
8.  Workload resources: From Pod to CronJob
9.  Service and service discovery
10. Kubernetes networking and CNI
11. kube-proxy, iptables, IPVS and eBPF
12. DNS and CoreDNS
13. Ingress, Gateway API and external traffic
14. ConfigMap, Secret, ServiceAccount and RBAC
15. Scheduling, resources, QoS and autoscaling
16. Storage: PV, PVC, CSI, StorageClass and Longhorn
17. Stateful workloads and database caveats
18. Health probes and application lifecycle
19. Security architecture
20. Observability: metrics, logs, traces
21. Helm, Kustomize, GitOps and delivery
22. High Availability and disaster recovery
23. Cluster installation concepts and version management
24. Troubleshooting playbook
25. Failure impact matrix
26. Hands-on lab progression
27. Production-readiness checklist
28. Glossary and official references

------------------------------------------------------------------------

# 1. Learning Path and Prerequisites

The most effective way to learn Kubernetes is not to memorize components, but to understand the flow of requests, packets, state, and failures.

## 1.1 Prerequisite

Before starting Kubernetes, make sure you understand the following topics at least at a basic level:

-   Linux: process, systemd, filesystem, permissions, logs
-   Networking: IP, subnet/CIDR, gateway, routing, ARP, DNS, TCP/UDP,
    ports, NAT, firewall
-   Containers: image, container, registry, namespaces, cgroups,
    container runtime
-   YAML and the command line
-   Git: commit, branch, pull request
-   Basic storage: filesystem, mount, block device, backup
-   TLS certificates: The concepts of public and private keys

For your KVM lab, the first milestone should be to establish network connectivity between two physical PCs/hosts, 
configure Linux bridge networking, and successfully test VM-to-VM ping and SSH.There is no need to install Kubernetes 
until this milestone is successful. Otherwise, you may mistakenly diagnose a networking problem as a Kubernetes problem.


## 1.2 Learning Stages

| Stage | What You Will Learn | Completion Test |
|---|---|---|
| 0 | Linux, TCP/IP, and bridge networking | Two VMs can ping and SSH into each other. |
| 1 | Containers, images, and runtimes | You can run a container and view its logs. |
| 2 | Pods, Deployments, and Services | You can deploy an application and access it through a Service. |
| 3 | DNS, CNI, and NetworkPolicy | You can test Pod-to-Pod connectivity and Service DNS resolution. |
| 4 | Configuration, Secrets, probes, and resources | You understand application configuration and restart behavior. |
| 5 | PV, PVC, and StorageClass | Data persists even after a Pod restarts. |
| 6 | RBAC, TLS, and security | You can configure least-privilege access. |
| 7 | Monitoring, logs, and backups | You can detect failures and recover from them. |
| 8 | High availability (HA), upgrades, and GitOps | You understand the impact of node or component failures and how to recover. |

---

# 2. What Is Kubernetes?

Kubernetes is an orchestration platform for deploying, scheduling, scaling, and maintaining containerized workloads. It allows you to declare the desired state of your applications, while its control loops attempt to bring the actual state closer to the desired state.

**Example:** Suppose you specify `replicas: 3` in a Deployment. If a Pod crashes, the controller attempts to create a replacement Pod. The Scheduler selects a suitable node, and the kubelet on that node uses the container runtime to start the container.

## 2.1 What Kubernetes Is Not

- It does not write application code for you.
- It does not automatically design database replication or failover strategies.
- It does not provide a load balancer, persistent storage, or CNI networking in every environment by itself.
- It is not a replacement for a backup strategy.
- Creating a Kubernetes cluster does not automatically make your applications secure or highly available.

## 2.2 Desired State vs. Actual State

- **Desired state:** The target declared in API objects, such as three replicas.
- **Actual state:** What is currently running in the cluster.
- **Controller:** Observes the actual state and makes changes to move it toward the desired state.
- **Reconciliation loop:** Observe → Compare → Act → Repeat.

Kubernetes generally relies on declarative configuration rather than a sequence of imperative instructions. However, imperative commands are also useful for debugging and learning.

------------------------------------------------------------------------

# 3. Core Architecture

A Kubernetes cluster logically has two main parts.

## 3.1 Control Plane

The Control Plane manages the cluster's desired state and scheduling. Main components:

-   kube-apiserver
-   etcd
-   kube-scheduler
-   kube-controller-manager
-   cloud-controller-manager (if cloud integration is needed)

## 3.2 Worker Node

Worker nodes run application Pods. Main components:

-   kubelet
-   container runtime, e.g., containerd
-   kube-proxy (if used in the cluster)
-   CNI plugin/agent
-   CSI node plugin, monitoring agent, and other DaemonSets — if installed

## 3.3 High-level flow

``` text
Developer / CI
     |
     | kubectl / automation
     v
kube-apiserver <------> etcd
     |
     +------> scheduler
     |
     +------> controllers
                  |
                  v
             API objects update
                  |
                  v
              kubelet (node)
                  |
                  v
           container runtime
                  |
                  v
                 Pods
```

This diagram is conceptual. In reality, most components read/write state through the API Server; components do not directly command each other.

------------------------------------------------------------------------

# 4. Kubernetes API Objects and API Server Flow

## 4.1 API object

A Kubernetes object is the declared state of a resource in the cluster. 
Common object fields:

-   `apiVersion`: API version
-   `kind`: object type
-   `metadata`: name, namespace, labels, annotations
-   `spec`: desired state
-   `status`: observed state; usually updated by controllers and system components
    update করে

Example:

``` yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
  namespace: default
spec:
  replicas: 2
  selector:
    matchLabels:
      app: web
  template:
    metadata:
      labels:
        app: web
    spec:
      containers:
        - name: nginx
          image: nginx:stable
          ports:
            - containerPort: 80
```

In production, pin image tags; using digests per your supply-chain policy may be more
reproducible. Avoid relying on latest.

## 4.2 The `kubectl apply` flow

1.  `kubectl` reads the manifest and sends an authenticated HTTPS request to the API Server.
2.  The API Server authenticates the request.
3.  The authorization policy --- usually RBAC --- checks permissions.
4.  Admission plugins/webhooks may validate or mutate the object.
5.  The API Server persists the object in etcd.
6.  The relevant controller watches the object.
7.  The Deployment controller creates/updates a ReplicaSet.
8.  The ReplicaSet controller creates Pods.
9.  The scheduler selects a node for unscheduled Pods.
10. The node's kubelet sees the Pod specification and runs the container via the runtime.
11. Status is reported back to the API `kubectl get` reads and displays the status.

Not every object follows the same path in the same way; the flow above is a general example for a Deployment.

## 4.3 Authentication, Authorization, Admission

-   **Authentication:** who made the request?
-   **Authorization:** what is that identity allowed to do?
-   **Admission:** does the object need to be validated or modified before/while being accepted?

`403 Forbidden` usually means the authenticated identity was denied authorization; however, when diagnosing errors, 
read the API response body and server logs. It alone is not proof of an etcd failure.

------------------------------------------------------------------------

# 5. Control Plane Components

## 5.1 kube-apiserver

**Role:** The front door to the Kubernetes API. `kubectl`, controllers, scheduler, kubelet, and other API clients communicate with the API Server.

**Responsibilities:**
- Expose the REST API
- Authentication, authorization, and admission control
- Validate API objects
- Read/write state with the storage layer
- Allow clients to observe changes via the Watch API

**Common port:** TCP 6443. Verify according to the actual port configuration.

**Debug commands**

```bash
kubectl cluster-info
kubectl get --raw='/readyz?verbose'
kubectl get --raw='/livez?verbose'
kubectl get pods -n kube-system -o wide
sudo journalctl -u kubelet -n 100 --no-pager
```

In a kubeadm setup, the API Server usually runs as a static Pod on a control-plane node. Therefore, `systemctl status kube-apiserver` is not the correct check in many kubeadm clusters; check the static Pod and container runtime status instead.

**Failure impact:**
- If all API Server endpoints are unavailable, new API operations will fail.
- Existing containers do not stop immediately; the node's local kubelet/runtime may continue working for some time.
- Controllers, scheduling, rollout, and API-based management are affected.
- In an HA setup, cluster API availability may be maintained if another healthy API Server endpoint is working.

## 5.2 kube-scheduler

**Role:** Selects which node a Pod will run on. The scheduler generally does not create Pods; it assigns Pods to nodes.

**Considerations:**
- CPU/RAM requests and available capacity
- nodeSelector and node affinity
- taints/tolerations
- topology spread constraints and pod affinity/anti-affinity
- volumes and topology constraints
- scheduling policies/plugins

**Debug**

```bash
kubectl get pods -A
kubectl describe pod <pod-name> -n <namespace>
kubectl get events -A --sort-by=.lastTimestamp
kubectl get nodes -o wide
```

If a Pod is `Pending`, check the Events section of `describe pod`. Causes may include `Insufficient cpu`, `Insufficient memory`, taints, affinity, or volume binding.

**Failure impact:** Already running Pods generally continue running; new unscheduled Pods do not receive node assignments.

## 5.3 kube-controller-manager

**Role:** Runs multiple controllers. Each controller reconciles the desired state and actual state of its own resource.

Examples:
- Deployment/ReplicaSet controllers
- Node controller
- Job controller
- EndpointSlice controller
- Namespace controller
- ServiceAccount controller  
  (The component arrangement may differ depending on version/configuration.)

**Example:** `replicas: 3`, but there are two Pods. The ReplicaSet controller tries to create the third Pod.

**Failure impact:** Some reconciliation may stop; existing Pods are not necessarily stopped immediately.

## 5.4 cloud-controller-manager

It can manage cloud-specific integration separately, such as:
- Cloud node metadata
- Cloud route management
- Cloud Load Balancer
- Some parts of cloud volume integration

It is not mandatory in every cluster. A bare-metal lab usually runs a cluster without cloud provider integration.

## 5.5 Control Plane HA

Multiple API Servers, leader election for scheduler/controller-manager, and etcd quorum are part of HA design. Creating only three control-plane VMs does not guarantee HA; 
a load balancer, failure domains, certificates, routing, etcd health, backup, and operational recovery are also needed.

------------------------------------------------------------------------

# 6. Worker Node Components

## 6.1 kubelet

**Role:** The node agent on each node. It watches Pod specifications from the API Server and works with the container runtime and other node components to run the desired Pods.

**Responsibilities:**
- Manage Pod lifecycle
- Use CRI with the container runtime
- Manage liveness/readiness/startup probes
- Report node and Pod status
- CSI/kubelet integration in volume mount orchestration
- Part of resource monitoring and eviction behavior

**Common port:** TCP 10250 (kubelet API); access must be tightly restricted.

**Debug**

```bash
sudo systemctl status kubelet
sudo journalctl -u kubelet -n 200 --no-pager
kubectl describe node <node-name>
kubectl get nodes -o wide
```

A kubelet API disconnect does not immediately make the Node `NotReady`; it depends on status reporting, timeouts, and node controller behavior.

## 6.2 Container runtime

Kubernetes uses the Container Runtime Interface (CRI) with the container runtime. A common runtime is containerd; below the runtime there may be an OCI runtime such as `runc`.

**containerd's work:**
- Image pull and content store
- Container snapshots/filesystem layers
- Container task lifecycle
- Runtime integration

**Debug**

```bash
sudo systemctl status containerd
sudo journalctl -u containerd -n 100 --no-pager
sudo crictl info
sudo crictl ps -a
sudo crictl images
```

If `crictl` is not installed/configured, you must first set it up according to your OS and runtime.

## 6.3 kube-proxy

The traditional component that implements Service virtual IP and NodePort traffic. It observes Service and EndpointSlice state and maintains node networking rules/programming.

In some clusters, a CNI/eBPF implementation may replace kube-proxy. Therefore, do not conclude that a cluster is wrong just because `kube-proxy` is absent; verify the cluster networking design.

## 6.4 Node-level add-ons

These are not core control-plane components, but they can be important in a production cluster:

- CNI agent (Calico, Cilium, etc.)
- CSI node plugin
- node-exporter
- log collector
- security agent
- storage agent
- GPU/device plugin

These usually run as DaemonSets, but the deployment pattern may differ by product.

------------------------------------------------------------------------

# 7. etcd --- Cluster State Store

etcd is a distributed, consistent key-value store. The persistent state of Kubernetes API objects is kept here.

## 7.1 Ports and quorum

- TCP 2379: client traffic
- TCP 2380: etcd peer traffic

Ports must be verified according to deployment and configuration.

The quorum of a three-member etcd cluster is generally 2. If one member is lost, the remaining two can maintain consensus. If two members are lost, quorum is lost and writes/consensus-dependent operations may become unavailable.

## 7.2 Stacked vs external etcd

- **Stacked etcd:** The etcd member is colocated with each control-plane node.
- **External etcd:** etcd runs on separate nodes.

A stacked design may be easier to manage, but a control-plane node failure also affects the etcd member. External etcd can separate failure domains, but infrastructure and operations become more complex.

## 7.3 Backup and restore

- Take regular snapshots.
- Copy snapshots to another failure domain.
- Run restore drills.
- Store certificates, configuration, and recovery steps with the backup.
- Do not be satisfied by seeing a backup success log; test the restore.

To maintain etcd in a kubeadm cluster, follow the version-matched procedure in the official documentation. An incorrect restore can lose cluster state.

Official docs: https://etcd.io/docs/ and https://kubernetes.io/docs/tasks/administer-cluster/configure-upgrade-etcd/

------------------------------------------------------------------------

# 8. Workload Resources: Pod to CronJob

## 8.1 Pod

A Pod is the smallest deployable unit in Kubernetes scheduling. A Pod can contain one or more closely coupled containers; they share a network namespace and Pod-level storage volumes.

**Keep in mind:**
- Container ≠ Pod
- Pod IP may be ephemeral.
- If a Pod is deleted/recreated, it may get a new Pod UID and a new IP.
- Generally, it is better to manage Pods with a Deployment, StatefulSet, or Job rather than as standalone Pods.

## 8.2 ReplicaSet

Maintains a specified number of matching Pods. Usually a Deployment manages ReplicaSets; direct use of ReplicaSet is less common.

## 8.3 Deployment

For stateless application rollout, scaling, and rollback.

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
spec:
  replicas: 3
  selector:
    matchLabels:
      app: web
  template:
    metadata:
      labels:
        app: web
    spec:
      containers:
        - name: nginx
          image: nginx:stable
          ports:
            - containerPort: 80
          resources:
            requests:
              cpu: "100m"
              memory: "128Mi"
            limits:
              cpu: "500m"
              memory: "256Mi"
```

This manifest is a learning example. In production, add probes, securityContext, image pinning, PodDisruptionBudget, topology rules, and configuration.

## 8.4 StatefulSet

For workloads that need stable identity and per-Pod storage identity. StatefulSet itself does not implement database replication, leader election, or data consistency.

It may require:
- Headless Service
- `volumeClaimTemplates`
- Ordered startup/shutdown semantics
- Application-level replication/consensus
- Backup/restore and recovery procedures

## 8.5 DaemonSet

Usually runs one Pod on each eligible node. Examples: CNI agents, log collectors, node monitoring agents, CSI node plugins. Due to taints, tolerations, and node selectors, the Pod may not run on all nodes.

## 8.6 Job

For finite task completion, such as migration or batch processing. `backoffLimit`, completion count, parallelism, and active deadline can be configured.

## 8.7 CronJob

Creates Jobs according to a schedule. It does not itself ensure backup correctness. Consider concurrency policy, missed schedule behavior, history limits, and job idempotency.

## 8.8 Init containers and sidecars

- **Init container:** Completes prerequisite tasks before the main container starts.
- **Sidecar:** A helper container running alongside the same Pod—such as a proxy or log/telemetry helper. Native sidecar semantics must be verified according to the version.

------------------------------------------------------------------------

# 9. Service and Service Discovery

Pod IPs can change. A Service provides a stable access abstraction and relates to backend Pods via selector/EndpointSlice.

## 9.1 ClusterIP

The default type for service access inside the cluster.

```yaml
apiVersion: v1
kind: Service
metadata:
  name: web
spec:
  type: ClusterIP
  selector:
    app: web
  ports:
    - name: http
      port: 80
      targetPort: 80
```

## 9.2 NodePort

Exposes the Service on a specific port on each eligible node's IP. The default range is generally 30000–32767, but cluster configuration can change it.

```yaml
apiVersion: v1
kind: Service
metadata:
  name: web-nodeport
spec:
  type: NodePort
  selector:
    app: web
  ports:
    - port: 80
      targetPort: 80
      nodePort: 30080
```

Access: `http://<node-ip>:30080`—if routing, firewall, Service implementation, and backend readiness are correct.

## 9.3 LoadBalancer

Provides an external IP/endpoint through cloud provider integration or a bare-metal Load Balancer implementation. On bare-metal, MetalLB or another supported design may be needed; simply setting `type: LoadBalancer` does not guarantee an IP.

## 9.4 ExternalName

Provides a DNS CNAME alias; it does not proxy or forward packets.

## 9.5 Headless Service

`clusterIP: None`. Useful for exposing individual Pod endpoints in DNS, especially for StatefulSets.

## 9.6 EndpointSlice

Holds backend endpoint information for a Service and scales better than the older Endpoints API. Inspect it if there is a Service selector mismatch or readiness issue.

```bash
kubectl get svc -A
kubectl get endpointslices -A
kubectl describe svc <service-name>
```

------------------------------------------------------------------------

# 10. Kubernetes Networking and CNI

In networking, think of three separate questions separately:

1. Is there node-to-node IP connectivity?
2. Is there Pod-to-Pod connectivity?
3. Does Service IP/NodePort traffic reach the backend Pod?

Just because one layer is correct does not mean another layer is correct.

## 10.1 What does CNI do?

Container Network Interface (CNI) is an interface for container networking plugin integration. The cluster's CNI implementation manages parts of Pod network attachment, IP allocation, routing/encapsulation, and policy enforcement.

Examples:
- Calico
- Cilium
- Flannel
- other compatible CNIs

Before installing a CNI in the same cluster, verify Kubernetes version, kernel, routing mode, IP ranges, and compatibility.

## 10.2 Pod CIDR vs Service CIDR vs Node subnet

- **Node subnet:** the network of physical/VM node IPs
- **Pod CIDR:** the network for Pod IP allocation
- **Service CIDR:** the virtual Service IP allocation range

These CIDRs should not overlap with each other. Also check for conflicts with VPN, home LAN, and upstream routes.

## 10.3 Pod-to-Pod packet journey

On the same node, Pod traffic may go through the local veth/bridge/eBPF datapath. On different nodes, traffic may be routed or may use encapsulation like VXLAN/IP-in-IP. The specific packet journey depends on the CNI configuration.

```text
Pod A
  -> Pod network interface
  -> node datapath / CNI rules
  -> (optional encapsulation or routed network)
  -> destination node
  -> destination Pod network interface
  -> Pod B
```

## 10.4 Calico

Calico may play a role in routing/BGP, IP-in-IP or VXLAN, policy enforcement, and IP allocation depending on the deployment. Not all modes are active in all installations.

Debug:

```bash
kubectl get pods -A -o wide
kubectl get pods -A | grep -i calico
ip route
ip -br addr
ip neigh
```

## 10.5 NetworkPolicy

NetworkPolicy defines Pod-level ingress/egress rules. Enforcement requires a compatible network plugin. Without a default policy, traffic for Pods in a namespace is generally allowed—until a policy isolates the traffic.

When writing a policy, do not forget DNS egress, monitoring, health checks, service-to-service traffic, and external dependencies.

------------------------------------------------------------------------

# 11. kube-proxy, iptables, IPVS and eBPF

## 11.1 kube-proxy

Observes Service/EndpointSlice changes and maintains node datapath rules. Historically/common modes include iptables and IPVS. Verify the supported modes and migration guidance for the current Kubernetes release from version-matched documentation.

## 11.2 iptables

Can use Netfilter rules to send Service traffic to the backend. Commands to inspect rule chains and counters may vary depending on the Linux distribution and cluster implementation.

```bash
sudo iptables-save | grep -E 'KUBE-|CALI-'
sudo nft list ruleset
```

In the iptables-nft backend, the `iptables` command may work with the nftables layer. Therefore, do not guess the entire network path just by looking at `iptables -L` output.

## 11.3 IPVS

A mode for implementing Service load balancing using Linux IP Virtual Server. Do not consider it a mandatory performance upgrade for all clusters; consider version support, operational complexity, and measured workload.

## 11.4 eBPF datapath

Some networking solutions like Cilium can implement Service routing, policy, and observability with eBPF; in some configurations, kube-proxy replacement is also possible. This is a cluster-specific design decision.

------------------------------------------------------------------------

# 12. DNS and CoreDNS

CoreDNS provides cluster DNS service. A Pod's `/etc/resolv.conf` usually contains the cluster DNS service IP and has search domains set.

From a Pod:

```bash
nslookup kubernetes.default
nslookup <service-name>.<namespace>.svc.cluster.local
```

Debug:

```bash
kubectl get pods -n kube-system -o wide
kubectl get svc -n kube-system
kubectl logs -n kube-system -l k8s-app=kube-dns --tail=100
```

If the label/namespace is different, the selector-based command must be changed.

Possible causes of DNS failure:
- CoreDNS Pods unavailable
- DNS Service/EndpointSlice issues
- CNI or Service routing issues
- UDP/TCP 53 blocked in NetworkPolicy
- Incorrect search domain or resolver configuration
- Upstream DNS failure

CoreDNS can also do external DNS forwarding, but it depends on the Corefile and upstream configuration.

------------------------------------------------------------------------
# 13. Ingress, Gateway API and External Traffic

## 13.1 Ingress

Ingress exposes HTTP/HTTPS routing rules. An Ingress object alone does not handle traffic; a compatible Ingress controller is required.

Common flow:

```text
Client
 -> DNS
 -> external Load Balancer / HAProxy
 -> node port or controller endpoint
 -> Ingress controller
 -> Kubernetes Service
 -> backend Pod
```

## 13.2 Gateway API

Gateway API is a more expressive API model for Kubernetes networking. Resources such as GatewayClass, Gateway, and HTTPRoute may be used. Verify controller support and feature availability according to version/provider.

## 13.3 TLS

TLS termination may occur at the external load balancer, Ingress/Gateway controller, or application layer. Consider certificate renewals, private-key permissions, hostname match, and internal service encryption.

## 13.4 Debug checklist

- Is DNS resolving to the correct IP?
- Is the external endpoint reachable?
- Is the firewall/security group allowing the port?
- Is the controller Pod Ready?
- Is the IngressClass/GatewayClass correct?
- Does the host/path rule match?
- Are there Ready endpoints in the Service's EndpointSlice?
- Is the TLS certificate/secret valid?

------------------------------------------------------------------------

# 14. ConfigMap, Secret, ServiceAccount and RBAC

## 14.1 ConfigMap

Keeps non-sensitive configuration data separate from the image. A ConfigMap can be mounted as a volume or consumed as environment variables. Changing environment variables generally requires a Pod restart; mounted files take time to update and the application must support reloading.

## 14.2 Secret

A Kubernetes object that carries sensitive data. Base64 encoding is not encryption. The security of a Secret depends on encryption at rest, RBAC, API access, audit, etcd protection, and delivery practices.

Learning example:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: app-secret
type: Opaque
stringData:
  username: app-user
  password: replace-me-before-use
```

Do not commit this to a public repository with real credentials. `replace-me-before-use` is only a placeholder.

## 14.3 ServiceAccount

The API identity for a Pod or workload. If the application does not need Kubernetes API access, consider disabling unnecessary token automount. Secure integration of workload identity varies by cluster/provider.

## 14.4 RBAC

- **Role:** namespace-scoped permissions
- **RoleBinding:** binds Role/ClusterRole permissions in a namespace
- **ClusterRole:** cluster-wide or reusable permissions definition
- **ClusterRoleBinding:** cluster-wide binding

Follow least privilege. Do not give `cluster-admin` to normal application workloads.

Debug:

```bash
kubectl auth can-i get pods -n default
kubectl auth can-i create deployments -n default
kubectl get roles,rolebindings -A
kubectl get clusterroles,clusterrolebindings
```

To impersonate (`--as`), the caller needs appropriate impersonation permission.

------------------------------------------------------------------------

# 15. Scheduling, Resources, QoS and Autoscaling

## 15.1 Requests and limits

- **Requests:** used by the scheduler for capacity placement; also the basis for runtime resource management.
- **Limits:** used to set CPU/memory resource usage limits.
- Exceeding a CPU limit can cause throttling.
- Exceeding a memory limit can cause the container to be OOM killed.

Measure requests from real workloads; over-requesting wastes cluster capacity, under-requesting increases contention.

## 15.2 QoS classes

Kubernetes generally assigns Guaranteed, Burstable, and BestEffort QoS classes. The QoS class depends on resource requests/limits configuration; it is not a direct substitute for application business priority.

## 15.3 Taints and tolerations

Taints create scheduling/placement restrictions on a node. A toleration allows a Pod to tolerate that taint; it does not itself schedule the Pod to a specific node.

## 15.4 Affinity and topology spread

Node affinity, Pod affinity/anti-affinity, and topology spread constraints control workload placement. These are important for zone/node failure, data locality, and replica distribution.

## 15.5 HPA, VPA, Cluster Autoscaler

- **HPA:** changes replica count based on metrics.
- **VPA:** can provide Pod resource request recommendations or updates; behavior varies by mode and configuration.
- **Cluster Autoscaler:** can increase/decrease node group capacity on supported infrastructure.

Using HPA requires a metrics pipeline and correct resource requests/metrics. CPU utilization-based scaling is generally calculated relative to CPU requests.

------------------------------------------------------------------------

# 16. Storage: PV, PVC, StorageClass, CSI and Longhorn

## 16.1 Core concepts

- **Volume:** mounted storage abstraction for a Pod's containers.
- **PV (PersistentVolume):** cluster storage resource.
- **PVC (PersistentVolumeClaim):** storage request from a workload.
- **StorageClass:** policy/class for dynamic provisioning.
- **CSI:** Container Storage Interface; Kubernetes integration with storage systems.
- **Snapshot/backup:** separate capability; availability and data recovery strategy are not the same.

## 16.2 Access modes

The semantics of `ReadWriteOnce`, `ReadOnlyMany`, `ReadWriteMany`, and `ReadWriteOncePod` must be verified according to the storage driver and Kubernetes version. Seeing an access mode does not mean the same volume can be assumed safe for concurrent multi-writer use.

## 16.3 Longhorn

Longhorn is a distributed block storage system for Kubernetes. Verify installation requirements, kernel modules, iSCSI/NVMe-oF requirements, supported OS, and Kubernetes compatibility from official version-specific documentation.

High-level components may include (depending on deployment/version):
- Longhorn Manager
- Instance Manager
- Volume Engine
- Replicas
- CSI components
- UI and backup integrations

More replicas does not mean backup. Independent backup is needed against accidental deletion, application corruption, or ransomware.

## 16.4 Storage troubleshooting

```bash
kubectl get storageclass
kubectl get pv
kubectl get pvc -A
kubectl describe pvc <claim-name> -n <namespace>
kubectl get pods -A | grep -i csi
kubectl get events -A --sort-by=.lastTimestamp
```

Common causes:
- StorageClass missing or no default
- PVC/PV access mode mismatch
- provisioner/CSI unavailable
- insufficient capacity
- node topology conflict
- permissions/mount errors
- Longhorn prerequisite/module failure
- replica node/disk unavailable

## 16.5 Database warning

StatefulSet + PVC does not create a PostgreSQL cluster. PostgreSQL HA requires separate design for replication, leader election/failover, fencing, backup, restore, connection routing, split-brain prevention, and upgrade procedures.

------------------------------------------------------------------------

# 17. Health Probes and Application Lifecycle

## 17.1 Startup probe

If the application takes a long time to start, a startup probe can be used before liveness/readiness checks.

## 17.2 Readiness probe

Helps determine whether a Pod is ready to receive traffic. If readiness fails, the Pod is generally removed from endpoint traffic selection; it is not an instruction to restart the container.

## 17.3 Liveness probe

If the application is stuck or unhealthy, kubelet can restart the container. An overly aggressive liveness probe can cause a healthy application to restart repeatedly.

## 17.4 Graceful termination

The application must handle SIGTERM, termination grace period, connection draining, and in-flight request completion. Rolling update does not automatically mean zero downtime; readiness, capacity, disruption budget, and application behavior are important.

------------------------------------------------------------------------

# 18. Security Architecture

Security must be layered:

1. **Host security:** patching, SSH hardening, OS firewall, access control
2. **API security:** TLS, authentication, authorization, audit
3. **Workload security:** non-root, read-only filesystem, dropped capabilities
4. **Network security:** NetworkPolicy, restricted control-plane ports
5. **Secret security:** encryption at rest, external secret manager, rotation
6. **Supply chain:** trusted images, scanning, signing/verification, pinned digests
7. **Admission policy:** Pod Security Standards or policy engine
8. **Runtime detection:** audit/runtime monitoring
9. **Backup security:** isolated access, immutable/offsite copies
10. **Operational security:** incident response, patching, tested recovery

Example security context:

```yaml
securityContext:
  runAsNonRoot: true
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true
  capabilities:
    drop: ["ALL"]
```

These settings will not work directly on every image; verify application write paths, user IDs, and required capabilities. In addition to security context, consider Pod-level `seccompProfile`, service account, network policy, and image policy.

------------------------------------------------------------------------

# 19. Observability: Metrics, Logs and Traces

## 19.1 Metrics

Prometheus-compatible metrics can show CPU, memory, request rate, error rate, latency, saturation, node health, and application business metrics.

Possible components:
- Prometheus
- node-exporter
- kube-state-metrics
- Grafana
- Alertmanager

## 19.2 Logs

Container stdout/stderr logs are written to the runtime/host; a retention and collection design is needed. Loki, Elasticsearch/OpenSearch, or a managed logging system can be used.

## 19.3 Traces

Distributed tracing helps with service-to-service request path, latency breakdown, and dependency analysis. OpenTelemetry instrumentation/collector and a compatible backend can be used.

## 19.4 Alerts

Alerts should not just be about high CPU; they should be tied to user-visible symptoms and service-level objectives:
- availability
- latency percentiles
- error rate
- queue lag
- saturation
- storage capacity
- certificate expiry
- backup/restore status

If the monitoring stack is inside the cluster, it too may become unavailable during a cluster outage. Consider out-of-band monitoring or an external alerting path.

------------------------------------------------------------------------

# 20. Helm, Kustomize, GitOps and Delivery

## 20.1 Helm

Packages, templates, configures, and manages the release lifecycle of Kubernetes manifests. Before installing a chart, review values and rendered manifests.

```bash
helm repo list
helm show values <repo/chart>
helm template <release> <repo/chart> -f values.yaml
```

## 20.2 Kustomize

Helps customize environment-specific manifests using bases and overlays. `kubectl kustomize` or `kubectl apply -k` can be used.

## 20.3 GitOps

The desired state is stored in Git, and a controller reconciles the live cluster with the repository state. Argo CD and Flux are common examples. Secrets should not be stored in plaintext in the repository; an encryption/external secret workflow is needed.

## 20.4 CI/CD pipeline

Typical pipeline:
1. Build
2. Unit/integration tests
3. Image scan
4. Image publish
5. Manifest/chart validation
6. Deployment approval/promotion
7. Rollout monitoring
8. Rollback/recovery path

For production deployment, keep immutable image references, environment separation, and an audit trail.

------------------------------------------------------------------------

# 21. High Availability and Disaster Recovery

## 21.1 HA layers

- Control plane API endpoints
- etcd quorum
- Worker node redundancy
- Application replicas
- Network path redundancy
- Storage replication
- DNS and external entry point
- Monitoring/alerting
- Backup and restore

## 21.2 Quorum

A three-member etcd cluster can generally tolerate one member failure; if two members are unavailable, quorum is lost. Odd-numbered members are common due to quorum trade-offs. Increasing member count does not automatically make all failures easier to tolerate.

## 21.3 Failure domains

If replicas are on the same physical host, rack, power source, or network path, they may become unavailable together in the same failure. Plan distribution using topology spread and anti-affinity.

## 21.4 Backup vs replication

- **Replication:** helps maintain availability and data copies; corruption/deletion can also be replicated.
- **Backup:** provides a recoverable copy from a specific point in time.
- **DR:** recovery process and tested runbook in an alternate failure domain.

Determine RPO (how much data loss is acceptable) and RTO (how long an outage is acceptable) from business requirements.

------------------------------------------------------------------------

# 22. Cluster Installation Concepts and Version Management

No single installation method is best for every environment. kubeadm, managed Kubernetes services, and other distributions have different operational models.

## 22.1 Role of kubeadm

kubeadm automates bootstrap and some cluster lifecycle tasks; it does not itself install/design all CNI, persistent storage, ingress, monitoring, backup, and production operations.

## 22.2 Version compatibility

Keep a version matrix for a cluster:
- Kubernetes control plane
- kubelet
- kubectl
- container runtime
- CNI
- CSI/storage
- ingress/gateway controller
- Helm charts/operators
- monitoring stack

Before upgrading:
1. Read release notes.
2. Check deprecated APIs.
3. Verify add-on compatibility.
4. Take etcd/application backup.
5. Test upgrade in staging.
6. Understand rollback/recovery limitations.
7. Follow official upgrade rules for one version hop at a time.

Do not write a specific "latest version" and leave a long-lived guide static. Keep a `Last verified` date and tested version matrix in the documentation.

------------------------------------------------------------------------

# 23. Troubleshooting Playbook

First determine the symptom, scope, and recent change. Do not blindly restart Pods or flush rules.

## 23.1 First-response commands

```bash
kubectl get nodes -o wide
kubectl get pods -A -o wide
kubectl get events -A --sort-by=.lastTimestamp
kubectl cluster-info
kubectl get svc,endpointslices -A
```

## 23.2 Pod Pending

1. `kubectl describe pod ...`
2. Read the Events.
3. Check resource requests, taints/tolerations, affinity, and node selectors.
4. Check PVC/StorageClass status.
5. Verify scheduler health and node capacity.

## 23.3 ImagePullBackOff

1. Is the image name/tag/digest correct?
2. Is the registry DNS/network reachable?
3. Are private registry credentials/`imagePullSecrets` correct?
4. Is there a registry rate limit or certificate issue?
5. Are node architecture and image platform compatible?

## 23.4 CrashLoopBackOff

1. `kubectl logs <pod> -c <container>`
2. `kubectl logs <pod> -c <container> --previous`
3. `kubectl describe pod`
4. Check exit code, OOMKilled, probes, config, permissions, and dependency status.

## 23.5 Service does not connect

1. Service selector vs Pod labels
2. Ready endpoints in EndpointSlice
3. `port` vs `targetPort`
4. Is the Pod itself listening?
5. CNI/pod routing
6. kube-proxy or replacement datapath
7. NetworkPolicy
8. Firewall and MTU

## 23.6 DNS does not work

1. Are CoreDNS Pods Ready?
2. Are the DNS Service/EndpointSlice correct?
3. What does the Pod's `/etc/resolv.conf` show?
4. Is UDP/TCP 53 traffic allowed?
5. Are the Service DNS name and namespace correct?
6. If external DNS, is the upstream resolver correct?

## 23.7 Node NotReady

1. `kubectl describe node`
2. Node's SSH/console access
3. `systemctl status kubelet`
4. containerd health
5. disk pressure, memory pressure, inode exhaustion
6. node-to-control-plane connectivity, time sync, and certificates
7. CNI agent health

## 23.8 PVC Pending

1. `kubectl describe pvc`
2. StorageClass provisioner/default class
3. CSI controller/node plugin
4. capacity, topology, and access modes
5. storage system events/logs
6. volume attachment/mount state

## 23.9 API Server unreachable

1. Client endpoint/DNS/LB
2. TCP 6443 reachability
3. API Server health/readiness
4. Certificates/time synchronization
5. Control-plane node resources
6. etcd health/quorum
7. firewall/routing

------------------------------------------------------------------------

# 24. Failure Impact Matrix

This is a conceptual matrix of general behavior; exact impact depends on cluster design, component implementation, and failure duration.

| Component failure | General possible impact |
|-------------------|-------------------------|
| All API Servers unavailable | API operations, scheduling/control loops, and management are disrupted |
| One API Server unavailable, others healthy | If HA endpoint is correct, cluster API can continue |
| etcd quorum lost | API state persistence/consensus-dependent operations may fail |
| Scheduler unavailable | New unscheduled Pods are not scheduled; running Pods generally continue |
| Controller manager unavailable | Reconciliation delayed/stopped; running Pods are not stopped immediately |
| kubelet unavailable on one node | Node status may later become NotReady; local workload behavior depends on runtime |
| container runtime unavailable on one node | Container lifecycle and new starts on that node are affected |
| CNI/datapath failure | Pod networking/policy/routing may be disrupted |
| kube-proxy failure (if used) | Service/NodePort rules may become stale or unavailable |
| CoreDNS unavailable | Cluster DNS queries may fail; direct IP traffic does not always fail |
| CSI/storage failure | New mount/provisioning and some existing volume operations are disrupted |
| Ingress controller unavailable | External HTTP/HTTPS traffic through it is disrupted |
| Monitoring unavailable | Detection/diagnosis weakens; applications may still run |

------------------------------------------------------------------------

# 25. Hands-on Lab Progression

Do not install all add-ons at once in this roadmap. Test each milestone before moving on.

## Lab 0 — Two-PC network foundation

- Document the IP/subnet/gateway of both hosts.
- Test host-to-host connectivity on the same switch.
- Verify KVM bridge (`br0`) and VM NIC configuration.
- Test VM-to-VM ping, SSH, DNS, and internet routing separately.
- Learn `ip -br addr`, `ip route`, `ip neigh`, `bridge link`, `tcpdump`.

**Pass criteria:** VM-to-VM ping/SSH is reliable; you can diagnose gateway and DNS failures separately.

## Lab 1 — Container basics

- Run a test image.
- Test port mapping, environment variables, volume mounts, and logs.
- Simulate container restart and image pull failure.

## Lab 2 — Single-node Kubernetes

- Follow the version-matched official guide.
- Verify the cluster is healthy.
- Test Pod, Deployment, Service, and DNS.
- Document component versions and installation decisions.

## Lab 3 — Multi-node cluster

- Validate control plane and worker networking.
- Test CNI status, Node Ready status, and cross-node Pod connectivity.
- Draw the NodePort traffic path diagram.

## Lab 4 — Workloads and policies

- Deployment scaling/rollout/rollback
- ConfigMap/Secret
- probes/resources
- RBAC
- NetworkPolicy

## Lab 5 — Storage

- StorageClass/PVC
- Data persistence after Pod delete/recreate
- volume detach/reattach behavior
- backup and restore drill

## Lab 6 — Observability

- node/pod metrics
- centralized logs
- alerts
- application traces
- failure drill and incident timeline

## Lab 7 — HA and operations

- control-plane endpoint/LB
- etcd backup/restore
- node drain
- version upgrade rehearsal
- GitOps
- disaster recovery exercise

------------------------------------------------------------------------

# 26. Production-readiness Checklist

## Platform

- [ ] Supported Kubernetes release and documented version matrix
- [ ] Control-plane endpoint HA design
- [ ] etcd backup and tested restore
- [ ] Node capacity planning
- [ ] CNI/CSI compatibility
- [ ] Non-overlapping network CIDRs

## Workloads

- [ ] Requests/limits
- [ ] Startup/readiness/liveness probes
- [ ] Graceful termination
- [ ] Multiple replicas where needed
- [ ] Pod topology spread / disruption planning
- [ ] Image pinning and image scanning

## Security

- [ ] Least-privilege RBAC
- [ ] Secret protection and rotation
- [ ] NetworkPolicy strategy
- [ ] Non-root workloads where possible
- [ ] Restricted API/kubelet access
- [ ] Audit and patch process

## Data

- [ ] Storage capacity alerts
- [ ] Independent backup
- [ ] Restore test
- [ ] RPO/RTO agreed
- [ ] Database HA implemented at application/database layer

## Operations

- [ ] Metrics, logs, traces
- [ ] Alert ownership and escalation
- [ ] Runbooks
- [ ] Upgrade plan
- [ ] Incident and rollback process
- [ ] External/out-of-band monitoring where appropriate

------------------------------------------------------------------------

# 27. Glossary

- **API Server:** The front door to the Kubernetes API.
- **etcd:** Persistent cluster state store.
- **Scheduler:** Selects a node for a Pod.
- **Controller:** Reconciles desired state.
- **kubelet:** Manages Pod lifecycle on a node.
- **Container runtime:** Runs and manages containers.
- **CNI:** Pod networking plugin integration.
- **CSI:** Storage plugin integration.
- **Pod:** The smallest deployable unit in scheduling.
- **Deployment:** Stateless rollout/replica management.
- **StatefulSet:** Stable identity/storage pattern.
- **DaemonSet:** Node-level Pods on eligible nodes.
- **Service:** Stable network endpoint abstraction.
- **EndpointSlice:** Representation of Service backend endpoints.
- **Ingress/Gateway:** External HTTP(S) routing API/controller pattern.
- **ConfigMap:** Non-sensitive configuration object.
- **Secret:** Object carrying sensitive data; not encryption by itself.
- **RBAC:** Role-based API authorization.
- **HPA:** Metrics-based replica autoscaling.
- **PVC:** Storage request.
- **StorageClass:** Storage provisioning policy.
- **GitOps:** Automated reconciliation of Git-declared desired state.
- **RPO:** Maximum acceptable data loss window in recovery.
- **RTO:** Target time limit for service recovery.

------------------------------------------------------------------------

# 28. Official References

Use official documentation as the primary source; verify version-specific details, deprecated APIs, and installation commands there.

- Kubernetes concepts: https://kubernetes.io/docs/concepts/
- Kubernetes architecture: https://kubernetes.io/docs/concepts/architecture/
- Kubernetes components: https://kubernetes.io/docs/concepts/overview/components/
- Workloads: https://kubernetes.io/docs/concepts/workloads/
- Services and networking: https://kubernetes.io/docs/concepts/services-networking/
- NetworkPolicy: https://kubernetes.io/docs/concepts/services-networking/network-policies/
- Storage: https://kubernetes.io/docs/concepts/storage/
- Security: https://kubernetes.io/docs/concepts/security/
- Resource management: https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/
- Troubleshooting: https://kubernetes.io/docs/tasks/debug/
- kubeadm: https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/
- Kubernetes release information: https://kubernetes.io/releases/
- etcd documentation: https://etcd.io/docs/
- Calico documentation: https://docs.tigera.io/calico/
- Cilium documentation: https://docs.cilium.io/
- Longhorn documentation: https://longhorn.io/docs/
- Prometheus documentation: https://prometheus.io/docs/
- OpenTelemetry documentation: https://opentelemetry.io/docs/

------------------------------------------------------------------------

## Final note

Kubernetes mastery is not just about writing YAML. The real goal is to understand the end-to-end flow: how a request reaches the API Server, how an object is persisted in etcd, how a controller reconciles, how the scheduler selects a node, how kubelet uses the container runtime, how a packet reaches a Pod/Service, how storage is attached, and how to recover from failures.

For each lab, keep three things: **architecture diagram, verification commands, and failure/recovery notes**. This will turn your documentation from learning notes into a real operational runbook.
