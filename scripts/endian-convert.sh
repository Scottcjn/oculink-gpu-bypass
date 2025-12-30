#!/bin/bash
#
# Endianness Conversion Helper for PowerPC GPU Support
# Converts big-endian PPC systems to little-endian for NVIDIA driver compatibility
#
# The PPC970 (G5) and POWER8/9 CPUs are BI-ENDIAN - they can run either mode!
#
# (c) 2025 RustChain/Elyan Labs - MIT License
#

set -e

LOG_TAG="endian-convert"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

detect_current_endian() {
    # Check current running endianness
    local endian=$(lscpu 2>/dev/null | grep -i "byte order" | awk '{print $3}')
    if [ -z "$endian" ]; then
        # Fallback: check ELF header of running binary
        endian=$(file /bin/ls | grep -o "LSB\|MSB")
        case "$endian" in
            LSB) echo "little" ;;
            MSB) echo "big" ;;
            *) echo "unknown" ;;
        esac
    else
        case "$endian" in
            Little) echo "little" ;;
            Big) echo "big" ;;
            *) echo "unknown" ;;
        esac
    fi
}

detect_cpu_biendian() {
    # Check if CPU supports bi-endian operation
    local cpu_model=""

    if [ -f /proc/cpuinfo ]; then
        cpu_model=$(grep -i "cpu\|model" /proc/cpuinfo | head -1)
    fi

    case "$cpu_model" in
        *970*|*G5*|*PPC970*)
            echo "yes"
            log "PPC970 (G5) detected - bi-endian capable"
            ;;
        *POWER8*|*power8*)
            echo "yes"
            log "POWER8 detected - bi-endian capable"
            ;;
        *POWER9*|*power9*)
            echo "yes"
            log "POWER9 detected - bi-endian capable"
            ;;
        *POWER10*|*power10*)
            echo "yes"
            log "POWER10 detected - bi-endian capable"
            ;;
        *)
            echo "unknown"
            log "Unknown CPU: $cpu_model"
            ;;
    esac
}

# Check for little-endian kernel availability
check_le_kernel() {
    log "Checking for little-endian kernel options..."

    # Check if we're on Ubuntu/Debian
    if command -v apt-cache &>/dev/null; then
        log "Available ppc64el kernels:"
        apt-cache search linux-image | grep -i "ppc64el\|powerpc" || echo "None found in repos"
    fi

    # Check current kernel
    log "Current kernel: $(uname -r)"
    log "Current arch: $(uname -m)"
}

# Instructions for G5 Mac little-endian conversion
g5_le_instructions() {
    cat << 'EOF'
=============================================================
PowerPC G5 Mac -> Little-Endian Conversion Guide
=============================================================

The PPC970 (G5) processor IS bi-endian! You can run ppc64le Linux.

METHOD 1: Install ppc64le Distribution
---------------------------------------
1. Download Void Linux ppc64le (one of few distros supporting G5 LE):
   https://voidlinux.org/download/#ppc64le

2. Or build Gentoo ppc64le:
   https://wiki.gentoo.org/wiki/Handbook:PPC64

3. Boot from USB with yaboot/GRUB configured for LE mode

METHOD 2: Kernel Boot Parameter (if supported)
----------------------------------------------
Some bootloaders support forcing LE mode:
  - In yaboot.conf: append="endian=little"
  - In GRUB: add to kernel line

METHOD 3: Build Custom LE Kernel
--------------------------------
Cross-compile a ppc64le kernel on x86:

  # Install cross compiler
  apt install gcc-powerpc64le-linux-gnu

  # Configure kernel
  make ARCH=powerpc CROSS_COMPILE=powerpc64le-linux-gnu- \
       pseries_le_defconfig

  # Build
  make ARCH=powerpc CROSS_COMPILE=powerpc64le-linux-gnu- -j$(nproc)

FIRMWARE NOTE:
--------------
G5 Macs use OpenFirmware which boots big-endian by default.
The kernel must handle the endian switch during early boot.
Most ppc64le kernels have this support built in.

After switching to ppc64le, NVIDIA drivers should work!
EOF
}

# Instructions for POWER8/9 systems
power_le_instructions() {
    cat << 'EOF'
=============================================================
IBM POWER8/9 -> Little-Endian Mode
=============================================================

POWER8/9 systems typically already run ppc64le (little-endian)
with modern Linux distributions like:
  - Ubuntu 18.04+ ppc64el
  - RHEL 7+ ppc64le
  - SLES 12+ ppc64le

CHECK CURRENT MODE:
  uname -m
  # ppc64le = little-endian (GOOD for NVIDIA)
  # ppc64   = big-endian (need to switch)

If running big-endian POWER:

1. The OPAL firmware supports both modes
2. Reinstall with ppc64le distribution
3. Or use petitboot to boot LE kernel

PETITBOOT (POWER8/9):
  - Access via IPMI/ASMI console
  - Select "Boot Options"
  - Choose ppc64le kernel/initrd

After ppc64le boot, NVIDIA Tesla drivers work natively!
EOF
}

# Create endianness shim for driver compatibility (experimental)
create_endian_shim() {
    log "Creating experimental endianness shim..."

    mkdir -p /home/scott/oculink-gpu-bypass/shim

    cat > /home/scott/oculink-gpu-bypass/shim/nvidia_endian_shim.c << 'SHIMCODE'
/*
 * NVIDIA Endianness Shim for Big-Endian PowerPC
 * EXPERIMENTAL - Proof of concept only
 *
 * This attempts to byte-swap GPU MMIO and DMA operations
 * to allow big-endian systems to communicate with LE GPUs.
 *
 * WARNING: This is highly experimental and may not work!
 */

#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/pci.h>
#include <linux/io.h>
#include <asm/byteorder.h>

MODULE_LICENSE("MIT");
MODULE_AUTHOR("Elyan Labs");
MODULE_DESCRIPTION("Endianness shim for NVIDIA on big-endian PPC");

/* Byte swap helpers */
static inline u32 gpu_readl(void __iomem *addr)
{
    u32 val = readl(addr);
#ifdef __BIG_ENDIAN
    return le32_to_cpu(val);  /* GPU is LE, swap on BE host */
#else
    return val;
#endif
}

static inline void gpu_writel(u32 val, void __iomem *addr)
{
#ifdef __BIG_ENDIAN
    writel(cpu_to_le32(val), addr);  /* Swap before writing */
#else
    writel(val, addr);
#endif
}

/*
 * Hook points needed:
 * 1. PCI BAR MMIO access - wrap readl/writel
 * 2. DMA buffer setup - ensure LE data format
 * 3. Command submission - swap command words
 * 4. Interrupt handling - swap status registers
 *
 * This requires either:
 * - Modifying nouveau source directly
 * - Creating an IOMMU-based translation layer
 * - Binary patching NVIDIA driver (very hard)
 */

static int __init endian_shim_init(void)
{
    pr_info("NVIDIA endian shim loaded (experimental)\n");

#ifdef __BIG_ENDIAN
    pr_info("Running on big-endian system - shim active\n");
#else
    pr_info("Running on little-endian - shim not needed\n");
#endif

    return 0;
}

static void __exit endian_shim_exit(void)
{
    pr_info("NVIDIA endian shim unloaded\n");
}

module_init(endian_shim_init);
module_exit(endian_shim_exit);
SHIMCODE

    log "Shim source created at /home/scott/oculink-gpu-bypass/shim/nvidia_endian_shim.c"
    log "NOTE: This is experimental - prefer running ppc64le natively"
}

# Main
main() {
    log "=== PowerPC Endianness Conversion Helper ==="

    CURRENT_ENDIAN=$(detect_current_endian)
    BIENDIAN=$(detect_cpu_biendian)

    log "Current endianness: $CURRENT_ENDIAN"
    log "CPU bi-endian capable: $BIENDIAN"

    case "${1:-check}" in
        check)
            check_le_kernel

            if [ "$CURRENT_ENDIAN" = "little" ]; then
                log "Already running little-endian - NVIDIA drivers compatible!"
            else
                log "Running big-endian - conversion needed for NVIDIA"

                if [ "$BIENDIAN" = "yes" ]; then
                    log "Good news: Your CPU supports little-endian mode!"
                fi
            fi
            ;;

        g5-guide)
            g5_le_instructions
            ;;

        power-guide)
            power_le_instructions
            ;;

        create-shim)
            create_endian_shim
            ;;

        *)
            echo "Usage: $0 [check|g5-guide|power-guide|create-shim]"
            echo ""
            echo "  check       - Check current endianness and CPU capabilities"
            echo "  g5-guide    - Instructions for G5 Mac LE conversion"
            echo "  power-guide - Instructions for POWER8/9 LE mode"
            echo "  create-shim - Create experimental endian shim (advanced)"
            exit 1
            ;;
    esac

    log "=== Done ==="
}

main "$@"
