#!/bin/bash
# ============================================================
# kube-vip Setup
# শুধু Control Plane VM-এ চালাও
# ============================================================

set -e

VIP="$1"

if [ -z "$VIP" ]; then
    echo "❌ Usage: bash 01-kube-vip.sh <VIP-IP>"
    echo "   Example: bash 01-kube-vip.sh 10.70.16.237"
    exit 1
fi

if [ "$EUID" -ne 0 ]; then
    echo "❌ sudo দিয়ে চালাও"
    exit 1
fi

echo "▶ kube-vip setup on $(hostname)"
echo "  VIP: $VIP"

# ---------- 1. Interface detect ----------
INTERFACE=$(ip -o -4 route show to default | awk '{print $5}' | head -1)
echo "  Interface: $INTERFACE"

# ---------- 2. Manifest dir ----------
mkdir -p /etc/kubernetes/manifests

# ---------- 3. Pull kube-vip image ----------
echo "  Pulling kube-vip image..."
ctr -n k8s.io image pull ghcr.io/kube-vip/kube-vip:v0.8.0

# ---------- 4. Generate manifest ----------
echo "  Generating manifest..."
ctr -n k8s.io run --rm --net-host \
    ghcr.io/kube-vip/kube-vip:v0.8.0 vip \
    /kube-vip manifest pod \
    --interface "$INTERFACE" \
    --address "$VIP" \
    --controlplane \
    --services \
    --arp \
    --leaderElection \
    > /etc/kubernetes/manifests/kube-vip.yaml

# ---------- 5. Verify ----------
if [ -f /etc/kubernetes/manifests/kube-vip.yaml ]; then
    echo "  Manifest: /etc/kubernetes/manifests/kube-vip.yaml"
    echo "✅ kube-vip ready on $(hostname)"
else
    echo "❌ kube-vip manifest তৈরি হয়নি"
    exit 1
fi
