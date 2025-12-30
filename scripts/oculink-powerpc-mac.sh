#!/bin/bash
#
# OCuLink GPU Bypass for PowerPC Macs (G5 with PCIe)
# Enables external GPU via OCuLink on Mac G5 towers running Linux
#
# Supported: Power Mac G5 (Late 2005) with PCIe slots
# NOT supported: AGP G5s, G4s (no PCIe)
#
# (c) 2025 RustChain/Elyan Labs - MIT License
#

set -e

LOG_TAG="oculink-mac"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    logger -t "$LOG_TAG" "$1" 2>/dev/null || true
}

detect_mac_model() {
    if [ -f /proc/device-tree/model ]; then
        cat /proc/device-tree/model | tr -d '\0'
    elif [ -f /proc/cpuinfo ]; then
        grep -i "machine\|model" /proc/cpuinfo | head -1
    fi
}

check_pcie_mac() {
    local model=$(detect_mac_model)
    log "Detected Mac: $model"

    # Only PCIe G5s have usable PCIe slots
    case "$model" in
        *PowerMac11,2*|*PowerMac12,1*)
            # Late 2005 Quad / Dual-Core - PCIe
            log "PCIe G5 detected - compatible!"
            return 0
            ;;
        *PowerMac7,2*|*PowerMac7,3*|*PowerMac9,1*)
            # Early G5s - AGP only
            log "ERROR: AGP G5 detected - no PCIe support"
            return 1
            ;;
        *PowerMac*)
            log "WARNING: Unknown PowerMac model - may not have PCIe"
            return 0
            ;;
        *)
            log "Not a PowerMac system"
            return 1
            ;;
    esac
}

# Fix OpenFirmware device tree for GPU
# OF on Macs can be even more restrictive than OPAL
patch_of_device_tree() {
    log "Checking OpenFirmware device tree..."

    # On Macs, the device tree is in /proc/device-tree
    if [ -d /proc/device-tree/pci@f0000000 ]; then
        log "Found PCI root at pci@f0000000"

        # List PCIe devices
        for dev in /proc/device-tree/pci@f0000000/*/; do
            name=$(cat "$dev/name" 2>/dev/null | tr -d '\0')
            vendor=$(cat "$dev/vendor-id" 2>/dev/null | xxd -p 2>/dev/null)
            log "  Device: $name (vendor: $vendor)"
        done
    fi

    # Check HyperTransport/U4 bus (G5 uses this)
    if [ -d /proc/device-tree/ht@0 ]; then
        log "Found HyperTransport bus (U4 chipset)"
    fi
}

# AMD GPU driver setup (more likely to work on PPC)
setup_radeon() {
    log "Setting up Radeon/AMDGPU driver..."

    # radeon driver works better on ppc64 than amdgpu
    # Supported: HD 2xxx - HD 7xxx, R5/R7/R9 (GCN 1.0-1.1)
    if lsmod | grep -q radeon; then
        log "radeon driver already loaded"
    else
        modprobe radeon 2>/dev/null || log "radeon module not available"
    fi

    # amdgpu for newer cards (GCN 1.2+)
    # WARNING: amdgpu has limited ppc64 support
    if lsmod | grep -q amdgpu; then
        log "amdgpu driver already loaded"
    fi
}

# Main
main() {
    log "=== OCuLink GPU Bypass for PowerPC Mac ==="

    if [ "$EUID" -ne 0 ]; then
        echo "ERROR: Must run as root"
        exit 1
    fi

    # Check architecture
    ARCH=$(uname -m)
    case "$ARCH" in
        ppc64|powerpc64)
            log "Architecture: ppc64 (big-endian)"
            log "NOTE: NVIDIA drivers NOT available for big-endian PPC"
            log "      AMD Radeon cards recommended (radeon/amdgpu drivers)"
            ;;
        ppc64le)
            log "Architecture: ppc64le (little-endian)"
            log "NVIDIA and AMD drivers available"
            ;;
        ppc|powerpc)
            log "Architecture: ppc32 - limited GPU support"
            ;;
    esac

    # Check if PCIe Mac
    if ! check_pcie_mac; then
        exit 1
    fi

    # Examine device tree
    patch_of_device_tree

    # PCIe rescan
    log "Rescanning PCIe bus..."
    echo 1 > /sys/bus/pci/rescan
    sleep 3

    # Check for GPUs
    log "Scanning for GPUs..."

    # NVIDIA (unlikely to work on big-endian, but check anyway)
    NVIDIA_COUNT=$(lspci -d 10de: 2>/dev/null | wc -l)
    if [ "$NVIDIA_COUNT" -gt 0 ]; then
        log "NVIDIA GPU detected:"
        lspci -d 10de: -v | head -10
        if [ "$ARCH" = "ppc64" ] || [ "$ARCH" = "ppc64be" ]; then
            log "WARNING: NVIDIA proprietary drivers don't support big-endian PPC"
            log "         nouveau may work for basic display"
        fi
    fi

    # AMD (better PPC support)
    AMD_COUNT=$(lspci -d 1002: 2>/dev/null | wc -l)
    if [ "$AMD_COUNT" -gt 0 ]; then
        log "AMD GPU detected:"
        lspci -d 1002: -v | head -10
        setup_radeon
    fi

    if [ "$NVIDIA_COUNT" -eq 0 ] && [ "$AMD_COUNT" -eq 0 ]; then
        log "No GPU detected after rescan"
        log "Troubleshooting:"
        log "  1. Verify OCuLink cable seated properly"
        log "  2. Check GPU power connection"
        log "  3. Try: setpci -s XX:XX.X COMMAND=0x0007"
        log "  4. Check dmesg: dmesg | grep -i pci"
    fi

    log "=== PowerPC Mac OCuLink Scan Complete ==="
}

main "$@"
