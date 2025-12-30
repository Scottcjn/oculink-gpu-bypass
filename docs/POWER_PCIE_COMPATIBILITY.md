# POWER8/POWER9 PCIe Device Compatibility List

This document lists PCIe devices known to work on IBM POWER8 and POWER9 systems.

**Key Requirement:** Open source drivers. Proprietary drivers (NVIDIA) only work on ppc64le with specific versions.

## GPUs - NVIDIA (ppc64le only)

### Officially Supported by IBM/NVIDIA

| GPU | POWER8 | POWER9 | Driver | Notes |
|-----|--------|--------|--------|-------|
| Tesla K40 | ✅ | ✅ | 346.x+ | S824L certified |
| Tesla K80 | ✅ | ✅ | 375.x+ | Dual GPU |
| Tesla M40 | ✅ | ✅ | 375.x+ | 24GB VRAM |
| Tesla P100 (PCIe) | ✅ | ✅ | 384.x+ | Pascal |
| Tesla P100 (NVLink) | ❌ | ✅ | 384.x+ | Requires NVLink |
| Tesla V100 (PCIe) | ⚠️ | ✅ | 410.x+ | Limited POWER8 |
| Tesla V100 (NVLink) | ❌ | ✅ | 410.x+ | AC922 only |
| Tesla T4 | ❌ | ✅ | 418.x+ | Turing |

**Driver versions for ppc64le:**
- CUDA 10.2 + Driver 440.64 - Last with POWER8 support
- CUDA 11.x + Driver 450.x+ - POWER9 only

### GeForce (Community Tested)

| GPU | Status | Notes |
|-----|--------|-------|
| GeForce 9500 GT | ✅ Works | Very old, nouveau |
| GeForce GTX 760 | ✅ Works | Kepler, nouveau |
| GeForce GTX 1080 | ⚠️ Partial | nouveau only, no CUDA |

## GPUs - AMD (Recommended for Open Source)

AMD GPUs work with open source `amdgpu` or `radeon` drivers on both big-endian and little-endian POWER.

### Tested Working on POWER9

| GPU | Driver | Notes |
|-----|--------|-------|
| **Radeon HD 5570** | radeon | Passive cooling available |
| **Radeon HD 5850** | radeon | Disable onboard VGA first |
| **Radeon HD 6450** | radeon | Low profile available |
| **Radeon HD 6850** | radeon | Good budget option |
| **Radeon HD 7790** | radeon | GCN 1.0 |
| **Radeon HD 7850** | radeon | GCN 1.0 |
| **Radeon HD 7950** | radeon | GCN 1.0, 3GB |
| **Radeon R5 220/230** | radeon | Low power |
| **Radeon R7 240** | radeon | DDR3/GDDR5 versions |
| **Radeon R9 290X** | radeon | Hawaii, high power |
| **Radeon R9 Nano** | amdgpu | Fiji, compact |
| **RX 480** | amdgpu | Polaris, 8GB |
| **RX 550** | amdgpu | Low profile available |
| **RX 560/560X/560D** | amdgpu | Polaris |
| **RX 580** | amdgpu | Polaris, 8GB, popular |
| **RX Vega 56** | amdgpu | Requires patches, unstable |
| **RX Vega 64** | amdgpu | Kernel 5.5+, no bootloader display |
| **RX 5500/5600/5700** | amdgpu | RDNA, kernel 5.4+ |
| **RX 5700 XT** | amdgpu | RDNA |
| **RX 6600** | amdgpu | RDNA2 |
| **RX 6700 XT** | amdgpu | RDNA2 |
| **RX 6800/6900 XT** | amdgpu | RDNA2, high-end |
| **RX 7600** | amdgpu | RDNA3 |
| **RX 7800 XT** | amdgpu | RDNA3 |

### AMD Professional (Workstation)

| GPU | Driver | Notes |
|-----|--------|-------|
| Radeon Pro WX4100 | amdgpu | Low profile |
| Radeon Pro WX5100 | amdgpu | 8GB |
| Radeon Pro WX7100 | amdgpu | 8GB |
| Radeon Pro W5500 | amdgpu | RDNA |

## Network Cards

### 10GbE+ NICs (Tested Working)

| Card | Chipset | Driver | Notes |
|------|---------|--------|-------|
| Mellanox ConnectX-3 Pro | MT27520 | mlx4 | Already in S824 |
| Mellanox ConnectX-4/5/6 | Various | mlx5 | Up to 200Gb |
| Chelsio T520-SO-CR | T5 | cxgb4 | 10Gb SFP+ |
| Chelsio T6225-SO-CR | T6 | cxgb4 | 25Gb |
| Intel X520/X540 | 82599ES | ixgbe | 10Gb |
| ASUS XG-C100F | AQC107 | atlantic | 10Gb SFP+ |
| Silicom PE210G2SPI9 | 82599 | ixgbe | Dual 10Gb |

### 1GbE NICs

| Card | Chipset | Driver | Notes |
|------|---------|--------|-------|
| Broadcom BCM5719 | BCM5719 | tg3 | Quad port |
| Intel I350 | I350 | igb | Quad port |
| Intel I210 | I210 | igb | Single port |

## Storage Controllers

### NVMe SSDs (Tested Working)

| Drive | Notes |
|-------|-------|
| Samsung 950 PRO | NVMe 1.1 |
| Samsung 960 EVO/PRO | NVMe 1.2 |
| Samsung 970 EVO/PRO | NVMe 1.3 |
| Samsung 980 PRO | NVMe 1.4, PCIe 4.0 |
| Samsung 990 PRO | NVMe 2.0 |
| Intel Optane 900P/905P | 3D XPoint |
| Intel DC P3600/P3700 | Enterprise |
| WD Black NVMe | Consumer |
| Kingston KC3000 | PCIe 4.0 |

### SAS/SATA HBAs

| Card | Chipset | Driver | Notes |
|------|---------|--------|-------|
| LSI 9300-8i | SAS3008 | mpt3sas | 12Gb SAS |
| LSI 9200-8i | SAS2008 | mpt2sas | 6Gb SAS |
| Dell PERC H700 | LSI | megaraid | RAID |
| Broadcom 9460-8i | SAS3516 | megaraid | RAID |
| Marvell 88SE9235 | 88SE9235 | ahci | SATA |

## USB Controllers

| Card | Chipset | Driver | Notes |
|------|---------|--------|-------|
| Various | Renesas uPD720201 | xhci_hcd | USB 3.0 |
| Various | ASMedia ASM1142 | xhci_hcd | USB 3.1 |
| Various | ASMedia ASM3142 | xhci_hcd | USB 3.1 Gen 2 |
| TI TUSB7340 | TUSB7340 | xhci_hcd | Already in S824 |

## Known Issues & Workarounds

### NVIDIA on POWER8

1. **OPAL Enumeration**: OPAL firmware may not enumerate NVIDIA GPUs
   - **Workaround**: Use PCIe hotplug rescan after boot
   - See: `scripts/pnv-php-rescan.sh`

2. **Driver Version**: Only CUDA 10.2 / Driver 440.x supports POWER8
   - Newer drivers dropped POWER8 support

3. **NVLink**: Not available on POWER8 (PCIe only)

### AMD on POWER

1. **Bootloader Display**: Vega and newer cards may not show bootloader/petitboot
   - System boots fine, display works in Linux

2. **Disable Onboard VGA**: Some cards require disabling AST2500
   ```bash
   # In petitboot, disable onboard VGA
   # Or add to kernel cmdline: modprobe.blacklist=ast
   ```

3. **Firmware**: RDNA cards need firmware from linux-firmware package
   ```bash
   apt install firmware-amd-graphics  # Debian/Ubuntu
   ```

### General PCIe Issues

1. **EEH Errors**: POWER's Enhanced Error Handling may fence slots
   ```bash
   # Check EEH status
   cat /proc/powerpc/eeh

   # Recovery script
   ./scripts/eeh-recovery.sh recover
   ```

2. **Hot-plug**: Many devices require cold boot, not hot-plug
   - Install device, power off completely, power on

3. **Slot Power**: Some slots need manual power-on
   ```bash
   setpci -s XX:XX.X CAP_EXP+0x18.w=0x1F
   ```

## References

- [Raptor CS POWER9 HCL](https://wiki.raptorcs.com/wiki/POWER9_Hardware_Compatibility_List/PCIe_Devices)
- [IBM POWER8 CUDA Redpaper](https://www.redbooks.ibm.com/redpapers/pdfs/redp5169.pdf)
- [IBM AC922 Technical Overview](https://www.redbooks.ibm.com/redpapers/pdfs/redp5494.pdf)
- [NVIDIA Tesla Driver Archive](https://www.nvidia.com/Download/index.aspx)
- [AMD GPU Firmware](https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git)

## Contributing

Found a device that works (or doesn't)? Please submit a PR or issue to update this list!

Tested on:
- IBM POWER8 S824 (8286-42A)
- Raptor Talos II / Blackbird (POWER9)
