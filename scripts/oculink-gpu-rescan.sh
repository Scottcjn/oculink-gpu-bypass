#!/bin/bash
#
# OCuLink GPU Bypass - PCIe Rescan Script
# For IBM POWER8/POWER9 and PowerPC Mac systems
#
# This script forces Linux to rescan the PCIe bus after an OCuLink GPU
# is connected, bypassing OpenFirmware/OPAL enumeration issues.
#
# Usage: sudo ./oculink-gpu-rescan.sh [--slot SLOT_ID]
#
# (c) 2025 RustChain/Elyan Labs - MIT License
#

set -e

LOG_TAG="oculink-gpu"
NVIDIA_VENDOR="10de"
AMD_VENDOR="1002"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    logger -t "$LOG_TAG" "$1"
}

detect_arch() {
    local arch=$(uname -m)
    case "$arch" in
        ppc64le)
            echo "power-le"
            ;;
        ppc64)
            echo "power-be"
            ;;
        ppc|powerpc)
            echo "powerpc-32"
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

# Check for root
if [ "$EUID" -ne 0 ]; then
    echo "ERROR: Must run as root"
    exit 1
fi

ARCH=$(detect_arch)
log "Detected architecture: $ARCH"

# Parse arguments
SLOT_ID=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --slot)
            SLOT_ID="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [--slot SLOT_ID]"
            echo "  --slot SLOT_ID  Rescan specific PCIe slot (e.g., 0000:00:01.0)"
            exit 0
            ;;
        *)
            shift
            ;;
    esac
done

log "=== OCuLink GPU Bypass - PCIe Rescan ==="

# Step 1: Disable EEH temporarily (POWER systems only)
if [ "$ARCH" = "power-le" ] || [ "$ARCH" = "power-be" ]; then
    log "POWER system detected - checking EEH state"
    if [ -f /proc/powerpc/eeh ]; then
        EEH_STATE=$(cat /proc/powerpc/eeh 2>/dev/null | head -1)
        log "Current EEH state: $EEH_STATE"
    fi

    # Check OPAL messages for PCIe issues
    if [ -f /sys/firmware/opal/msglog ]; then
        OPAL_ERRORS=$(grep -i "pci.*error\|eeh\|phb.*fail" /sys/firmware/opal/msglog 2>/dev/null | tail -5)
        if [ -n "$OPAL_ERRORS" ]; then
            log "WARNING: OPAL PCIe errors detected:"
            echo "$OPAL_ERRORS" | while read line; do log "  $line"; done
        fi
    fi
fi

# Step 2: Save current PCIe state
log "Saving current PCIe topology..."
BEFORE_DEVICES=$(lspci -n 2>/dev/null | wc -l)
log "Current device count: $BEFORE_DEVICES"

# Step 3: Check for existing GPUs
log "Checking for existing GPUs..."
EXISTING_NVIDIA=$(lspci -d ${NVIDIA_VENDOR}: 2>/dev/null | wc -l)
EXISTING_AMD=$(lspci -d ${AMD_VENDOR}: 2>/dev/null | wc -l)
log "Existing NVIDIA devices: $EXISTING_NVIDIA"
log "Existing AMD devices: $EXISTING_AMD"

# Step 4: Remove and rescan specific slot OR full bus rescan
if [ -n "$SLOT_ID" ]; then
    log "Rescanning specific slot: $SLOT_ID"

    SLOT_PATH="/sys/bus/pci/devices/$SLOT_ID"
    if [ -d "$SLOT_PATH" ]; then
        log "Removing device at $SLOT_ID..."
        echo 1 > "$SLOT_PATH/remove" 2>/dev/null || true
        sleep 1
    fi

    # Find parent bridge and rescan
    PARENT_PATH=$(dirname "$SLOT_PATH")
    if [ -f "$PARENT_PATH/rescan" ]; then
        log "Rescanning parent bridge..."
        echo 1 > "$PARENT_PATH/rescan"
    fi
else
    log "Performing full PCIe bus rescan..."
    echo 1 > /sys/bus/pci/rescan
fi

sleep 3

# Step 5: Check for new devices
AFTER_DEVICES=$(lspci -n 2>/dev/null | wc -l)
NEW_DEVICES=$((AFTER_DEVICES - BEFORE_DEVICES))
log "Device count after rescan: $AFTER_DEVICES (${NEW_DEVICES} new)"

# Step 6: Check for GPUs
NEW_NVIDIA=$(lspci -d ${NVIDIA_VENDOR}: 2>/dev/null | wc -l)
NEW_AMD=$(lspci -d ${AMD_VENDOR}: 2>/dev/null | wc -l)

if [ "$NEW_NVIDIA" -gt "$EXISTING_NVIDIA" ]; then
    log "SUCCESS: New NVIDIA GPU detected!"
    lspci -d ${NVIDIA_VENDOR}: -v | head -20

    # Try to load NVIDIA driver
    if modinfo nvidia &>/dev/null; then
        log "Loading NVIDIA driver..."
        modprobe nvidia || log "WARNING: Failed to load nvidia module"
    else
        log "NVIDIA driver not installed - run install-nvidia-power.sh"
    fi

elif [ "$NEW_AMD" -gt "$EXISTING_AMD" ]; then
    log "SUCCESS: New AMD GPU detected!"
    lspci -d ${AMD_VENDOR}: -v | head -20

    # AMD drivers usually load automatically via amdgpu
    if lsmod | grep -q amdgpu; then
        log "amdgpu driver already loaded"
    else
        log "Loading amdgpu driver..."
        modprobe amdgpu || log "WARNING: Failed to load amdgpu module"
    fi
else
    log "No new GPU detected"
    log "Troubleshooting steps:"
    log "  1. Check OCuLink cable connection"
    log "  2. Ensure GPU has external power connected"
    log "  3. Check dmesg for errors: dmesg | tail -50"
    log "  4. Try specific slot rescan: $0 --slot 0000:XX:XX.0"
fi

# Step 7: Final PCIe status
log "=== Final PCIe Status ==="
lspci -tv | head -30

# Check for GPU in device tree (POWER systems)
if [ "$ARCH" = "power-le" ] || [ "$ARCH" = "power-be" ]; then
    log "Checking POWER device tree..."
    if ls /proc/device-tree/pciex@*/pci@0/ 2>/dev/null | grep -q nvidia; then
        log "GPU found in device tree"
    fi
fi

log "=== OCuLink GPU Rescan Complete ==="
