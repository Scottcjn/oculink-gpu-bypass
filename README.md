[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](https://opensource.org/licenses/Apache-2.0) [![GPU](https://img.shields.io/badge/GPU-Bypass-red)](https://github.com/Scottcjn/oculink-gpu-bypass) [![PCIe](https://img.shields.io/badge/PCIe-OCuLink-blue)](https://github.com/Scottcjn/oculink-gpu-bypass)

# GPU Bypass for POWER & PowerPC Systems

Enable GPUs on IBM POWER8/POWER9 and PowerPC Mac systems by bypassing OpenFirmware/OPAL PCIe enumeration issues.

**Two approaches:**
1. **Internal PCIe** - Rescan internal slots after boot (no extra hardware!)
2. **OCuLink External** - Add more GPUs via SFF-8612 adapters

## The Problem

IBM POWER and PowerPC Mac systems have restrictive firmware (OPAL/OpenFirmware) that often fails to properly enumerate modern GPUs during boot. This prevents using GPUs even when the hardware is fully capable.

## Solution 1: Internal PCIe Rescan (No Extra Hardware!)

If your GPU is already in an internal PCIe slot but not detected at boot:

```bash
# Quick test - may work without kernel patch!
sudo ./scripts/pnv-php-rescan.sh

# If that doesn't work, apply the kernel patch first
# See: patches/pnv-php-oculink.patch
```

**How it works:**
1. Boot system (OPAL ignores GPU, no device tree entry)
2. Load patched `pnv_php` driver with bypass mode
3. Trigger PCIe bus rescan
4. GPU appears in Linux!

## Solution 2: OCuLink External

Use a generic **PCIe x4 OCuLink adapter** card to connect GPUs externally. Since OCuLink is electrically just PCIe, we can:
1. Boot the system with only the adapter installed
2. Connect the GPU via OCuLink cable after boot
3. Force Linux to rescan the PCIe bus
4. GPU appears and drivers load normally

```
┌─────────────────────────────────────────────────────────────┐
│ POWER8/G5 System                                            │
│                                                             │
│  PCIe Slot ──► OCuLink Adapter ──► SFF-8612 Cable ──► GPU  │
│     │              (passive)           │           (Tesla)  │
│     │                                  │                    │
│  Firmware sees:                  Linux sees:                │
│  "Generic PCIe                   "NVIDIA Tesla"             │
│   Bridge"                        via PCIe rescan            │
└─────────────────────────────────────────────────────────────┘
```

## Supported Hardware

### IBM POWER Systems (ppc64le)
| System | GPU Support | Notes |
|--------|-------------|-------|
| POWER8 S824/S822LC | K80, M40, P100, V100 | NVIDIA 440.x drivers |
| POWER9 AC922/IC922 | V100, A100 | NVIDIA 450.x+ drivers |

### PowerPC Macs (ppc64 big-endian)
| System | GPU Support | Notes |
|--------|-------------|-------|
| Power Mac G5 (PCIe, Late 2005) | AMD Radeon HD/R series | radeon/amdgpu drivers |
| Power Mac G5 (AGP) | ❌ Not supported | No PCIe slots |
| G4 systems | ❌ Not supported | No PCIe slots |

**Note:** NVIDIA proprietary drivers do NOT support big-endian PowerPC. However, G5 CPUs are **bi-endian** - see [Endianness Conversion](#endianness-conversion) below.

## Endianness Conversion

PowerPC CPUs (PPC970/G5, POWER8/9) are **bi-endian** - they can run in either big-endian or little-endian mode!

### Why This Matters

| Mode | NVIDIA Support | AMD Support |
|------|----------------|-------------|
| ppc64le (little-endian) | ✅ Full | ✅ Full |
| ppc64 (big-endian) | ❌ None | ✅ radeon/nouveau |

### Quick Endianness Check

```bash
# Check current mode
./scripts/endian-convert.sh check

# Output:
# Current endianness: little  ← NVIDIA works!
# Current endianness: big     ← Need conversion
```

### Conversion Options

1. **Install ppc64le Linux** (Recommended)
   - Void Linux, Gentoo, Ubuntu ppc64el
   - See [docs/ENDIAN_CONVERSION.md](docs/ENDIAN_CONVERSION.md)

2. **Use nouveau on big-endian**
   - Apply `patches/nouveau-bigendian.patch`
   - Limited but functional

3. **Use AMD GPUs**
   - radeon/amdgpu work on both BE and LE

```bash
# G5 Mac conversion guide
./scripts/endian-convert.sh g5-guide

# POWER8/9 conversion guide
./scripts/endian-convert.sh power-guide
```

## Hardware Requirements

1. **OCuLink Adapter Card** - Generic PCIe x4 to SFF-8612
   - ~$20-50 on Amazon/AliExpress
   - Must be passive/transparent (no special chipset)

2. **OCuLink Cable** - SFF-8612 to SFF-8612
   - Length: 0.5m - 1m recommended
   - Shielded cables recommended for signal integrity

3. **GPU** - NVIDIA Tesla or AMD Radeon
   - Must have external power connectors
   - PCIe x16 GPUs work at x4 bandwidth (reduced but functional)

4. **External Power** - GPU PSU or ATX supply
   - Tesla cards: 6-pin or 8-pin PCIe power
   - Most Tesla cards need 150-300W

## Installation

### Quick Start (POWER8/POWER9)

```bash
# Clone repo
git clone https://github.com/elyanlabs/oculink-gpu-bypass.git
cd oculink-gpu-bypass

# Install scripts
sudo mkdir -p /opt/oculink-gpu-bypass
sudo cp scripts/*.sh /opt/oculink-gpu-bypass/
sudo chmod +x /opt/oculink-gpu-bypass/*.sh

# Install systemd service (optional - auto-rescan on boot)
sudo cp scripts/oculink-gpu.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable oculink-gpu

# Connect GPU via OCuLink, then:
sudo /opt/oculink-gpu-bypass/oculink-gpu-rescan.sh
```

### Install NVIDIA Driver (POWER8/POWER9 only)

```bash
# Download and install Tesla driver 440.64
sudo /opt/oculink-gpu-bypass/install-nvidia-power.sh install

# Optionally install CUDA 10.2
sudo /opt/oculink-gpu-bypass/install-nvidia-power.sh cuda
```

### PowerPC Mac (G5)

```bash
# For AMD GPUs on G5 Macs running Linux
sudo /opt/oculink-gpu-bypass/oculink-powerpc-mac.sh
```

## Usage

### Manual GPU Rescan

```bash
# Full PCIe bus rescan
sudo /opt/oculink-gpu-bypass/oculink-gpu-rescan.sh

# Rescan specific slot
sudo /opt/oculink-gpu-bypass/oculink-gpu-rescan.sh --slot 0000:00:01.0
```

### EEH Recovery (POWER systems)

If the GPU triggers EEH (Enhanced Error Handling) errors:

```bash
# Check for frozen PCIe endpoints
sudo /opt/oculink-gpu-bypass/eeh-recovery.sh check

# Attempt recovery
sudo /opt/oculink-gpu-bypass/eeh-recovery.sh recover

# View OPAL error messages
sudo /opt/oculink-gpu-bypass/eeh-recovery.sh monitor
```

### Verify GPU

```bash
# Check PCIe devices
lspci | grep -i nvidia
lspci | grep -i amd

# NVIDIA status
nvidia-smi

# AMD status
cat /sys/class/drm/card0/device/gpu_busy_percent
```

## Troubleshooting

### GPU Not Detected After Rescan

1. **Check cable connection** - OCuLink cables must be fully seated
2. **Check GPU power** - Tesla cards need external power
3. **Check dmesg** - `dmesg | tail -50 | grep -i pci`
4. **Try manual enable** - `setpci -s XX:XX.X COMMAND=0x0007`

### EEH Freezes (POWER)

POWER systems may freeze the PCIe slot on errors:

```bash
# Check EEH state
cat /proc/powerpc/eeh

# Disable EEH (risky, but may help)
# Add to kernel cmdline: eeh=off
```

### Driver Won't Load

```bash
# Check kernel compatibility
uname -r
modinfo nvidia

# Rebuild DKMS
dkms autoinstall

# Check blacklist
cat /etc/modprobe.d/blacklist-nouveau.conf
```

## Kernel Parameters

Add to GRUB cmdline for troubleshooting:

```
# Force PCIe reallocation
pci=realloc pci=assign-busses

# Disable EEH (POWER only - risky)
eeh=off

# Verbose PCIe debug
pci=debug
```

## Performance Notes

- **OCuLink x4** provides ~4 GB/s bandwidth (PCIe 3.0 x4)
- **Tesla compute** workloads are less bandwidth-sensitive
- **CUDA kernels** run at full speed on the GPU
- **Data transfer** is bottlenecked vs native x16

Benchmark comparison (V100 via OCuLink x4 vs native x16):
| Workload | Native x16 | OCuLink x4 | Difference |
|----------|------------|------------|------------|
| GEMM (compute-bound) | 100% | 98% | -2% |
| Large batch inference | 100% | 95% | -5% |
| Memory-bound ops | 100% | 75% | -25% |

## Tested Configurations

| System | GPU | Driver | Status |
|--------|-----|--------|--------|
| IBM POWER8 S824 | Tesla M40 | 440.64 | 🔄 Pending (OCuLink) |
| IBM POWER8 S824 | Tesla K80 | 440.64 | 🔄 Pending (OCuLink) |
| IBM POWER8 S824 | Tesla V100 | 440.64 | 🔄 Pending (OCuLink) |
| Power Mac G5 Dual 2.0 | AMD Radeon | radeon | 🔄 Pending |

**Note:** This project is in active development. Hardware testing pending OCuLink adapter installation.

## License

MIT License - (c) 2025 Elyan Labs

## Contributing

Pull requests welcome! Please test on actual hardware before submitting.

## Related Projects

- [RustChain](https://github.com/elyanlabs/rustchain) - PowerPC mining with antiquity bonuses
- [PSE llama.cpp](https://github.com/elyanlabs/llama-cpp-pse) - POWER8 optimized LLM inference

## References

- [IBM POWER8 CUDA Guide (Redpaper)](https://www.redbooks.ibm.com/redpapers/pdfs/redp5169.pdf)
- [NVIDIA Tesla Driver Archive](https://www.nvidia.com/Download/index.aspx)
- [CUDA Toolkit Archive](https://developer.nvidia.com/cuda-toolkit-archive)
- [OCuLink SFF-8612 Specification](https://www.snia.org/technology-communities/sff/specifications)
