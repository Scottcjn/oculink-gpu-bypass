#!/bin/bash
#
# EEH (Enhanced Error Handling) Recovery Script for IBM POWER
# Handles PCIe errors that can occur with OCuLink GPU bypass
#
# (c) 2025 RustChain/Elyan Labs - MIT License
#

LOG_TAG="eeh-recovery"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    logger -t "$LOG_TAG" "$1"
}

if [ "$EUID" -ne 0 ]; then
    echo "ERROR: Must run as root"
    exit 1
fi

# Check if running on POWER
if [ ! -f /proc/powerpc/eeh ]; then
    log "WARNING: Not a POWER system or EEH not available"
    exit 0
fi

log "=== EEH Recovery Script ==="

# Check EEH state
EEH_STATE=$(cat /proc/powerpc/eeh 2>/dev/null)
log "EEH State: $EEH_STATE"

# Check for frozen PEs (Partitionable Endpoints)
check_frozen_pe() {
    log "Checking for frozen PCIe devices..."

    for pe_dir in /sys/bus/pci/devices/*/eeh_pe_state; do
        if [ -f "$pe_dir" ]; then
            state=$(cat "$pe_dir" 2>/dev/null)
            device=$(dirname "$pe_dir" | xargs basename)

            if [ "$state" != "0" ] && [ "$state" != "none" ]; then
                log "FROZEN PE detected: $device (state: $state)"
                echo "$device"
            fi
        fi
    done
}

# Recover frozen PE
recover_pe() {
    local device=$1
    local pe_path="/sys/bus/pci/devices/$device"

    log "Attempting recovery for $device..."

    # Method 1: Trigger EEH recovery via sysfs
    if [ -f "$pe_path/eeh_pe_config_addr" ]; then
        config_addr=$(cat "$pe_path/eeh_pe_config_addr" 2>/dev/null)
        log "PE config address: $config_addr"
    fi

    # Method 2: Remove and rescan
    if [ -f "$pe_path/remove" ]; then
        log "Removing device $device..."
        echo 1 > "$pe_path/remove" 2>/dev/null || true
        sleep 2

        log "Rescanning PCIe bus..."
        echo 1 > /sys/bus/pci/rescan
        sleep 2
    fi

    # Method 3: Reset via setpci (last resort)
    # setpci -s $device COMMAND=0x0006

    log "Recovery attempt complete for $device"
}

# Monitor OPAL messages for EEH events
monitor_opal() {
    log "Checking OPAL messages for EEH events..."

    if [ -f /sys/firmware/opal/msglog ]; then
        grep -i "eeh\|phb.*freeze\|pci.*error" /sys/firmware/opal/msglog 2>/dev/null | tail -20
    fi
}

# Clear EEH error logs
clear_errors() {
    log "Clearing EEH error state..."

    # Clear kernel EEH counters
    if [ -d /sys/kernel/debug/powerpc ]; then
        for eeh_file in /sys/kernel/debug/powerpc/eeh_*; do
            if [ -w "$eeh_file" ]; then
                echo 0 > "$eeh_file" 2>/dev/null || true
            fi
        done
    fi
}

# Main
case "${1:-check}" in
    check)
        log "Checking EEH status..."
        FROZEN=$(check_frozen_pe)
        if [ -n "$FROZEN" ]; then
            log "Frozen PEs found:"
            echo "$FROZEN"
            exit 1
        else
            log "No frozen PEs detected"
            exit 0
        fi
        ;;
    recover)
        FROZEN=$(check_frozen_pe)
        if [ -n "$FROZEN" ]; then
            for pe in $FROZEN; do
                recover_pe "$pe"
            done
        else
            log "No frozen PEs to recover"
        fi
        ;;
    monitor)
        monitor_opal
        ;;
    clear)
        clear_errors
        ;;
    *)
        echo "Usage: $0 [check|recover|monitor|clear]"
        echo "  check   - Check for frozen PCIe endpoints"
        echo "  recover - Attempt to recover frozen endpoints"
        echo "  monitor - Show OPAL EEH messages"
        echo "  clear   - Clear EEH error counters"
        exit 1
        ;;
esac

log "=== EEH Recovery Complete ==="
