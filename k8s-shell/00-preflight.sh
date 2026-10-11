#!/bin/bash
# ============================================================
# Preflight Check — সব VM Ready কিনা verify
# ============================================================

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "════════════════════════════════════════"
echo "  Preflight Check — 5 VMs"
echo "════════════════════════════════════════"
echo ""

ALL_OK=true

for ip in 237 238 239 240 241; do
    echo "━━━ 10.70.16.$ip ━━━"
    
    RESULT=$(ssh vm@$ip 'bash -s' <<'CHECK' 2>/dev/null
# 1. containerd active
CD=$(systemctl is-active containerd 2>/dev/null)
if [ "$CD" = "active" ]; then
    echo "  ✅ containerd: active"
else
    echo "  ❌ containerd: $CD"
fi

# 2. Config lines
LINES=$(wc -l < /etc/containerd/config.toml 2>/dev/null || echo "0")
if [ "$LINES" -gt 100 ]; then
    echo "  ✅ Config: $LINES lines"
else
    echo "  ❌ Config: $LINES lines (too short)"
fi

# 3. SystemdCgroup
if grep -q "SystemdCgroup = true" /etc/containerd/config.toml 2>/dev/null; then
    echo "  ✅ SystemdCgroup: true"
else
    echo "  ❌ SystemdCgroup: NOT set"
fi

# 4. sandbox_image
if grep -q "sandbox_image.*pause" /etc/containerd/config.toml 2>/dev/null; then
    echo "  ✅ sandbox_image: pause:3.9"
else
    echo "  ❌ sandbox_image: missing"
fi

# 5. CRI disabled_plugins
if grep -q "disabled_plugins = \[\]" /etc/containerd/config.toml 2>/dev/null; then
    echo "  ✅ CRI: enabled"
else
    echo "  ❌ CRI: disabled"
fi

# 6. CRI runtime ready
CRI=$(sudo crictl info 2>/dev/null | grep -A1 '"RuntimeReady"' | grep '"status"' | grep -o 'true' | head -1)
if [ "$CRI" = "true" ]; then
    echo "  ✅ CRI RuntimeReady: true"
else
    echo "  ⚠️  CRI RuntimeReady: $CRI"
fi

# 7. kubeadm installed
if command -v kubeadm >/dev/null; then
    echo "  ✅ kubeadm: $(kubeadm version -o short)"
else
    echo "  ❌ kubeadm: NOT installed"
fi

# 8. kubelet installed
if command -v kubelet >/dev/null; then
    echo "  ✅ kubelet: installed"
else
    echo "  ❌ kubelet: NOT installed"
fi

# 9. Swap off
SWAP=$(free -h | awk '/Swap:/ {print $2}')
if [ "$SWAP" = "0B" ]; then
    echo "  ✅ Swap: disabled"
else
    echo "  ❌ Swap: $SWAP (must be off)"
fi

# 10. kube-vip (CP only)
if [ -f /etc/kubernetes/manifests/kube-vip.yaml ]; then
    echo "  ✅ kube-vip: manifest present"
fi
CHECK
)
    
    echo "$RESULT"
    echo ""
done

echo "════════════════════════════════════════"
echo "  If all ✅ — Ready for kubeadm init"
echo "  If any ❌ — Run fix-containerd.sh first"
echo "════════════════════════════════════════"
