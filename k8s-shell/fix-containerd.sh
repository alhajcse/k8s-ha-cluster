#!/bin/bash
# ============================================================
# containerd Complete Fix
# Prevention: CRI disabled, sandbox_image missing, wrong config
# ============================================================

set -e

if [ "$EUID" -ne 0 ]; then
    echo "❌ sudo দিয়ে চালাও: sudo bash $0"
    exit 1
fi

echo "════════════════════════════════════════"
echo "  containerd Complete Fix"
echo "  Host: $(hostname)"
echo "════════════════════════════════════════"
echo ""

# ---------- 1. Stop containerd ----------
echo "[1/6] Stopping containerd..."
systemctl stop containerd 2>/dev/null || true

# ---------- 2. Backup old config ----------
echo "[2/6] Backing up old config..."
if [ -f /etc/containerd/config.toml ]; then
    mv /etc/containerd/config.toml /etc/containerd/config.toml.backup-$(date +%Y%m%d-%H%M%S)
fi

# ---------- 3. Generate fresh full config ----------
echo "[3/6] Generating fresh default config..."
mkdir -p /etc/containerd
containerd config default | tee /etc/containerd/config.toml > /dev/null

LINES=$(wc -l < /etc/containerd/config.toml)
echo "         Generated: $LINES lines"

if [ "$LINES" -lt 100 ]; then
    echo "❌ Config too short! Aborting."
    exit 1
fi

# ---------- 4. Fix SystemdCgroup = true ----------
echo "[4/6] Setting SystemdCgroup = true..."
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

if grep -q "SystemdCgroup = true" /etc/containerd/config.toml; then
    echo "         ✓ SystemdCgroup = true"
else
    echo "         ❌ SystemdCgroup change failed!"
    exit 1
fi

# ---------- 5. Fix sandbox_image (auto-detect quote style) ----------
echo "[5/6] Setting sandbox_image = pause:3.9..."

# Try single-quote pattern first (most common in newer containerd)
if grep -q "plugins.'io.containerd.grpc.v1.cri'" /etc/containerd/config.toml; then
    sed -i "s|\[plugins\.'io\.containerd\.grpc\.v1\.cri'\]|[plugins.'io.containerd.grpc.v1.cri']\n    sandbox_image = \"registry.k8s.io/pause:3.9\"|" /etc/containerd/config.toml
    echo "         ✓ Used single-quote pattern"
# Fallback to double-quote pattern
elif grep -q 'plugins."io.containerd.grpc.v1.cri"' /etc/containerd/config.toml; then
    sed -i 's|\[plugins\."io\.containerd\.grpc\.v1\.cri"\]|[plugins."io.containerd.grpc.v1.cri"]\n    sandbox_image = "registry.k8s.io/pause:3.9"|' /etc/containerd/config.toml
    echo "         ✓ Used double-quote pattern"
else
    echo "         ❌ CRI section not found!"
    exit 1
fi

# Remove duplicate sandbox_image if any
if [ "$(grep -c 'sandbox_image' /etc/containerd/config.toml)" -gt 1 ]; then
    # Keep only first occurrence
    awk '!seen[$0]++ || !/sandbox_image/' /etc/containerd/config.toml > /tmp/config.toml
    mv /tmp/config.toml /etc/containerd/config.toml
    echo "         ✓ Removed duplicates"
fi

# ---------- 6. Ensure CRI is enabled ----------
echo "[6/6] Ensuring CRI is enabled..."
sed -i 's/^disabled_plugins = .*/disabled_plugins = []/' /etc/containerd/config.toml

# ---------- Restart + Verify ----------
echo ""
echo "Restarting containerd..."
systemctl restart containerd
systemctl enable containerd
sleep 3

# ---------- Final Verification ----------
echo ""
echo "════════════════════════════════════════"
echo "  Verification"
echo "════════════════════════════════════════"
echo ""

# 1. Config lines
echo "1. Config lines: $(wc -l < /etc/containerd/config.toml)"

# 2. SystemdCgroup
echo -n "2. SystemdCgroup: "
grep "SystemdCgroup = true" /etc/containerd/config.toml > /dev/null && echo "✅" || echo "❌"

# 3. Sandbox image
echo -n "3. sandbox_image: "
grep -q "sandbox_image.*pause" /etc/containerd/config.toml && echo "✅" || echo "❌"

# 4. CRI enabled
echo -n "4. disabled_plugins: "
grep "disabled_plugins = \[\]" /etc/containerd/config.toml > /dev/null && echo "✅" || echo "❌"

# 5. containerd status
echo -n "5. containerd service: "
systemctl is-active containerd

# 6. CRI runtime
echo -n "6. CRI RuntimeReady: "
crictl info 2>/dev/null | grep -A1 '"RuntimeReady"' | grep '"status"' | grep -o 'true' || echo "unknown"

# 7. CRI runtimeType
echo -n "7. runtimeType: "
crictl info 2>/dev/null | grep '"runtimeType"' | head -1 | awk -F'"' '{print $4}' || echo "unknown"

echo ""
if systemctl is-active --quiet containerd && \
   grep -q "SystemdCgroup = true" /etc/containerd/config.toml && \
   grep -q "sandbox_image.*pause" /etc/containerd/config.toml; then
    echo "════════════════════════════════════════"
    echo "  ✅ ALL CHECKS PASSED"
    echo "════════════════════════════════════════"
    exit 0
else
    echo "════════════════════════════════════════"
    echo "  ❌ SOME CHECKS FAILED"
    echo "════════════════════════════════════════"
    exit 1
fi
