#!/bin/bash
# ============================================================
# kubeadm init
# শুধু CP-01-এ চালাও
# ============================================================

set -e

if [ "$EUID" -ne 0 ]; then
    echo "❌ sudo দিয়ে চালাও"
    exit 1
fi

echo "▶ Initializing K8s cluster on $(hostname)"

# ---------- 1. Check if already initialized ----------
if [ -f /etc/kubernetes/admin.conf ]; then
    echo "⚠️  Cluster already initialized!"
    echo "   Reset করতে হলে: kubeadm reset -f"
    exit 0
fi

# ---------- 2. kubeadm config ----------
echo "  [1/3] Creating kubeadm config..."

cat > /root/kubeadm-config.yaml <<'CONFIG'
apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration
kubernetesVersion: v1.30.0
controlPlaneEndpoint: "10.70.16.237:6443"
networking:
  podSubnet: "10.244.0.0/16"
  serviceSubnet: "10.96.0.0/12"
apiServer:
  certSANs:
    - "10.70.16.237"
    - "10.70.16.238"
    - "10.70.16.239"
    - "10.70.16.240"
    - "10.70.16.241"
    - "10.70.16.242"
    - "k8s-api.local"
etcd:
  local:
    dataDir: /var/lib/etcd
---
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
cgroupDriver: systemd
---
apiVersion: kubeadm.k8s.io/v1beta3
kind: InitConfiguration
localAPIEndpoint:
  advertiseAddress: 10.70.16.237
  bindPort: 6443
nodeRegistration:
  criSocket: unix:///var/run/containerd/containerd.sock
CONFIG

# ---------- 3. Preflight: containerd check ----------
echo "  [2/3] Checking containerd..."
if ! systemctl is-active --quiet containerd; then
    echo "❌ containerd চলছে না"
    systemctl restart containerd
    sleep 3
fi

# ---------- 4. kubeadm init ----------
echo "  [3/3] Running kubeadm init (২-৩ মিনিট লাগবে)..."
kubeadm init --config /root/kubeadm-config.yaml --upload-certs 2>&1 | tee /root/kubeadm-init.log

# ---------- 5. kubectl setup for vm user ----------
echo "  Setting up kubectl for vm user..."
mkdir -p /home/vm/.kube
cp /etc/kubernetes/admin.conf /home/vm/.kube/config
chown -R vm:vm /home/vm/.kube

echo ""
echo "════════════════════════════════════════════"
echo "✅ Cluster initialized successfully!"
echo "════════════════════════════════════════════"
echo ""

# ---------- 6. Show join commands ----------
echo "📌 Join commands saved in /root/kubeadm-init.log"
echo ""
echo "🔍 Verify kubectl:"
echo "   ssh vm@$(hostname -I | awk '{print $1}')"
echo "   kubectl get nodes"
