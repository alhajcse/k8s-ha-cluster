#!/bin/bash
# ============================================================
# Calico CNI Installation
# ============================================================

set -e

if [ "$EUID" -ne 0 ]; then
    echo "❌ sudo দিয়ে চালাও"
    exit 1
fi

export KUBECONFIG=/home/vm/.kube/config

echo "════════════════════════════════════════════════"
echo "  Calico CNI Installation"
echo "  Host: $(hostname)"
echo "  $(date)"
echo "════════════════════════════════════════════════"

# ---------- GUARD: Already installed? ----------
if kubectl get ns tigera-operator &>/dev/null; then
    echo ""
    echo "⚠️  Calico already installed!"
    kubectl get pods -n calico-system 2>/dev/null || true
    exit 0
fi

# ---------- 1. Install Tigera operator ----------
echo ""
echo "[1/4] Installing Tigera operator..."
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.28.0/manifests/tigera-operator.yaml

# ---------- 2. Wait for operator ----------
echo ""
echo "[2/4] Waiting for operator (max 5 min)..."
kubectl wait --for=condition=Available deployment/tigera-operator \
    -n tigera-operator --timeout=300s
echo "   ✅ Operator ready"

# ---------- 3. Apply Installation CR ----------
echo ""
echo "[3/4] Applying Calico Installation..."
cat <<'CALICO' | kubectl apply -f -
apiVersion: operator.tigera.io/v1
kind: Installation
metadata:
  name: default
spec:
  calicoNetwork:
    ipPools:
      - blockSize: 26
        cidr: 10.244.0.0/16
        encapsulation: IPIP
        natOutgoing: Enabled
        nodeSelector: all()
CALICO

# ---------- 4. Wait for Calico pods ----------
echo ""
echo "[4/4] Waiting for Calico pods (max 10 min)..."
sleep 20

# Wait for namespace
for i in {1..30}; do
    if kubectl get ns calico-system &>/dev/null; then
        echo "   ✅ calico-system namespace ready"
        break
    fi
    sleep 10
done

# Wait for pods
kubectl wait --for=condition=Ready pods --all \
    -n calico-system --timeout=600s

# ---------- Verify ----------
echo ""
echo "════════════════════════════════════════════════"
echo "  Verification"
echo "════════════════════════════════════════════════"
echo ""
echo "▶ Calico pods:"
kubectl get pods -n calico-system

echo ""
echo "▶ Waiting for node Ready (max 2 min)..."
for i in {1..12}; do
    STATUS=$(kubectl get nodes -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}')
    if [ "$STATUS" = "True" ]; then
        echo "   ✅ Node is Ready!"
        break
    fi
    echo "   Waiting... ($i/12)"
    sleep 10
done

echo ""
echo "▶ Final status:"
kubectl get nodes -o wide

echo ""
echo "▶ CoreDNS:"
kubectl get pods -n kube-system -l k8s-app=kube-dns

echo ""
echo "════════════════════════════════════════════════"
echo "  ✅ Calico Installation Complete"
echo "════════════════════════════════════════════════"
