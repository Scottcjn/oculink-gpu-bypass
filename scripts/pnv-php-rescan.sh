#!/bin/bash
#
# PowerNV PCIe Hotplug Rescan Script
# Works for BOTH internal PCIe slots AND OCuLink external
#
# This script enables GPU detection on POWER8/POWER9 systems
# where OPAL firmware failed to enumerate the GPU at boot.
#
# (c) 2025 RustChain/Elyan Labs - MIT License
#

set -e

LOG_TAG="pnv-php-rescan"
NVIDIA_VENDOR="10de"
AMD_VENDOR="1002"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    logger -t "$LOG_TAG" "$1"
}

# Check for root
if [ "$EUID" -ne 0 ]; then
    echo "ERROR: Must run as root"
    exit 1
fi

log "=== PowerNV PCIe GPU Rescan ==="

# Check if we're on POWER
if [ ! -f /proc/cpuinfo ] || ! grep -qi "power\|ppc" /proc/cpuinfo; then
    log "WARNING: Not detected as POWER system"
fi

# Step 1: Check current GPU state
log "Step 1: Current GPU state..."
NVIDIA_BEFORE=$(lspci -d ${NVIDIA_VENDOR}: 2>/dev/null | wc -l)
AMD_BEFORE=$(lspci -d ${AMD_VENDOR}: 2>/dev/null | wc -l)
log "  NVIDIA devices: $NVIDIA_BEFORE"
log "  AMD devices: $AMD_BEFORE"

# Step 2: Load pnv_php module with bypass mode
log "Step 2: Loading pnv_php hotplug driver..."
if lsmod | grep -q pnv_php; then
    log "  pnv_php already loaded"
else
    # Try loading with bypass mode parameter
    modprobe pnv_php oculink_bypass_mode=1 2>/dev/null || \
    modprobe pnv_php 2>/dev/null || \
    log "  WARNING: Could not load pnv_php module"
fi

# Step 3: Check PHB (PCI Host Bridge) status
log "Step 3: Checking PHB status..."
if [ -d /sys/firmware/opal ]; then
    log "  OPAL firmware detected"

    # List PHBs
    for phb in /sys/devices/pci*; do
        if [ -d "$phb" ]; then
            phb_name=$(basename "$phb")
            log "  PHB: $phb_name"
        fi
    done
fi

# Step 4: Trigger PCIe rescan on all buses
log "Step 4: Triggering PCIe rescan..."

# Method 1: Global rescan
echo 1 > /sys/bus/pci/rescan
log "  Global rescan triggered"

sleep 2

# Method 2: Rescan each PHB individually
for phb in /sys/devices/pci*/pci*; do
    if [ -f "$phb/rescan" ]; then
        echo 1 > "$phb/rescan" 2>/dev/null || true
        log "  Rescanned: $phb"
    fi
done

sleep 3

# Step 5: Check for new devices
log "Step 5: Checking for new GPUs..."
NVIDIA_AFTER=$(lspci -d ${NVIDIA_VENDOR}: 2>/dev/null | wc -l)
AMD_AFTER=$(lspci -d ${AMD_VENDOR}: 2>/dev/null | wc -l)

NEW_NVIDIA=$((NVIDIA_AFTER - NVIDIA_BEFORE))
NEW_AMD=$((AMD_AFTER - AMD_BEFORE))

if [ "$NEW_NVIDIA" -gt 0 ]; then
    log "SUCCESS: Found $NEW_NVIDIA new NVIDIA GPU(s)!"
    lspci -d ${NVIDIA_VENDOR}: -v | head -30

    log ""
    log "Next steps:"
    log "  1. Install NVIDIA driver: ./install-nvidia-power.sh install"
    log "  2. Verify with: nvidia-smi"

elif [ "$NEW_AMD" -gt 0 ]; then
    log "SUCCESS: Found $NEW_AMD new AMD GPU(s)!"
    lspci -d ${AMD_VENDOR}: -v | head -30

    log ""
    log "Loading amdgpu driver..."
    modprobe amdgpu 2>/dev/null || modprobe radeon 2>/dev/null || true

else
    log "No new GPUs detected after rescan"
    log ""
    log "Troubleshooting:"
    log "  1. Is GPU physically installed and powered?"
    log "  2. Check dmesg: dmesg | grep -i 'pci\|nvidia\|gpu'"
    log "  3. Check OPAL logs: cat /sys/firmware/opal/msglog | tail -50"
    log "  4. Try manual slot power-on (see below)"
fi

# Step 6: Show PCIe topology
log ""
log "Step 6: Current PCIe topology..."
lspci -tv | head -40

# Step 7: Check for EEH errors
log ""
log "Step 7: EEH status..."
if [ -f /proc/powerpc/eeh ]; then
    cat /proc/powerpc/eeh
fi

# Show manual power-on instructions
log ""
log "=== Manual Slot Power-On (if needed) ==="
log "If GPU still not detected, try forcing slot power:"
log ""
log "  # Find your PCIe slot (bridge device)"
log "  lspci | grep -i 'bridge'"
log ""
log "  # Force power on (replace XX:XX.X with your bridge)"
log "  setpci -s XX:XX.X CAP_EXP+0x18.w=0x1F"
log ""
log "  # Rescan again"
log "  echo 1 > /sys/bus/pci/rescan"
log ""
log "=== PowerNV PCIe Rescan Complete ==="
