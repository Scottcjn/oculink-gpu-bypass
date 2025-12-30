# Big-Endian to Little-Endian Conversion for GPU Drivers

## The Problem

NVIDIA proprietary drivers only support **little-endian** architectures:
- x86_64 (LE)
- aarch64 (LE)
- ppc64le (LE) ← POWER8/9 little-endian

They do NOT support:
- ppc64 (BE) ← Big-endian PowerPC
- ppc (BE) ← 32-bit PowerPC

## The Good News: Bi-Endian CPUs

PowerPC processors are **bi-endian** - they can run in either mode!

| CPU | Bi-Endian | Notes |
|-----|-----------|-------|
| PPC970 (G5) | ✅ Yes | Mac G5 towers |
| POWER7 | ✅ Yes | IBM servers |
| POWER8 | ✅ Yes | IBM servers, default LE |
| POWER9 | ✅ Yes | IBM servers |
| PPC74xx (G4) | ❌ No | Big-endian only |
| PPC603/604 | ❌ No | Big-endian only |

## Solution Paths

### Path 1: Native Little-Endian (Recommended)

**Best option**: Run a ppc64le distribution natively.

For **Power Mac G5**:
```bash
# Void Linux is one of the few distros with G5 ppc64le support
# Download: https://voidlinux.org/download/#ppc64le

# Or build Gentoo ppc64le from source
# Guide: https://wiki.gentoo.org/wiki/Handbook:PPC64/Installation
```

For **IBM POWER8/9**:
```bash
# Most modern distros default to ppc64le
# Ubuntu: ubuntu-20.04-live-server-ppc64el.iso
# RHEL: rhel-8-ppc64le.iso

# Check current mode:
uname -m
# ppc64le = good
# ppc64 = need to reinstall LE
```

### Path 2: Kernel-Level Endian Switch

The Linux kernel can switch endianness at boot on bi-endian CPUs:

```c
// Early boot code in arch/powerpc/kernel/head_64.S
// Sets MSR[LE] bit to switch to little-endian mode
```

**Boot process**:
1. OpenFirmware/OPAL starts big-endian
2. Kernel loads in BE mode
3. Kernel switches to LE mode in early init
4. Userspace runs entirely LE

### Path 3: Endianness Translation Layer (Experimental)

For systems that MUST stay big-endian, we can create a translation layer:

```
┌─────────────────────────────────────────────────────────┐
│ Big-Endian Userspace                                    │
│                                                         │
│  Application ──► Endian Shim ──► GPU Driver ──► GPU    │
│       │              │               │           │      │
│      BE data    byte-swap        LE data      LE HW    │
└─────────────────────────────────────────────────────────┘
```

#### What needs byte-swapping:

1. **MMIO Registers** - GPU control registers are LE
   ```c
   // Instead of:
   writel(value, gpu_reg);

   // Use:
   writel(cpu_to_le32(value), gpu_reg);
   ```

2. **DMA Buffers** - Command buffers must be LE
   ```c
   // Swap entire command buffer before submission
   for (i = 0; i < cmd_size/4; i++)
       cmd_buf[i] = cpu_to_le32(cmd_buf[i]);
   ```

3. **PCIe Config Space** - Already handled by kernel

4. **Interrupts/Status** - Read status in LE format

### Path 4: Nouveau Driver (Open Source)

The **nouveau** open-source NVIDIA driver CAN be patched for big-endian:

```bash
# Clone nouveau
git clone https://github.com/skeggsb/nouveau.git

# Key files needing endian fixes:
# - nvkm/subdev/bar/
# - nvkm/engine/fifo/
# - nvkm/subdev/fb/
```

**Nouveau BE Patch Points**:

```c
// In nvkm/subdev/bar/nv50.c
// Change MMIO accessors to handle endianness:

static inline u32 nvkm_rd32(struct nvkm_device *d, u32 addr)
{
    u32 val = ioread32(d->mmio + addr);
#ifdef __BIG_ENDIAN
    return le32_to_cpu(val);
#else
    return val;
#endif
}
```

### Path 5: QEMU/KVM with LE Guest (Fallback)

Run a little-endian VM on big-endian host with GPU passthrough:

```bash
# On BE host, run LE guest
qemu-system-ppc64 \
    -machine pseries \
    -cpu POWER8 \
    -m 16G \
    -device vfio-pci,host=0000:01:00.0 \
    -bios /path/to/slof.bin \
    -kernel /path/to/vmlinux-ppc64le \
    -append "root=/dev/vda"
```

**Limitations**: Performance overhead from virtualization

## Recommended Approach by System

| System | Recommendation | Effort |
|--------|----------------|--------|
| Power Mac G5 | Install Void Linux ppc64le | Medium |
| POWER8 (BE) | Reinstall Ubuntu ppc64el | Low |
| POWER9 | Already ppc64le default | None |
| G4 Mac | Use AMD GPU + radeon driver | Medium |
| G3/earlier | Not practical for GPU compute | N/A |

## G5 Mac Little-Endian Installation

### Step 1: Prepare Boot Media

```bash
# On x86 Linux, create bootable USB
wget https://repo.voidlinux.org/live/current/void-live-ppc64le-*.iso
dd if=void-live-ppc64le-*.iso of=/dev/sdX bs=4M status=progress
```

### Step 2: Boot into OpenFirmware

1. Power on G5, hold **Cmd+Option+O+F**
2. At OF prompt:
   ```
   boot usb0/disk:2,\\:tbxi
   ```

### Step 3: Install System

```bash
# Void installer handles LE kernel automatically
void-installer

# Or manual Gentoo:
# Follow: https://wiki.gentoo.org/wiki/Handbook:PPC64
```

### Step 4: Configure Bootloader

```bash
# yaboot.conf for LE kernel
image=/boot/vmlinux-ppc64le
    label=linux
    read-only
    append="root=/dev/sda2"
```

### Step 5: Install NVIDIA Driver

```bash
# Now that you're running ppc64le:
./install-nvidia-power.sh install
```

## Kernel Cross-Compilation Reference

Build ppc64le kernel on x86:

```bash
# Install toolchain
apt install gcc-powerpc64le-linux-gnu binutils-powerpc64le-linux-gnu

# Get kernel source
wget https://cdn.kernel.org/pub/linux/kernel/v5.x/linux-5.4.tar.xz
tar xf linux-5.4.tar.xz && cd linux-5.4

# Configure for ppc64le
make ARCH=powerpc CROSS_COMPILE=powerpc64le-linux-gnu- pseries_le_defconfig

# Enable GPU support
make ARCH=powerpc CROSS_COMPILE=powerpc64le-linux-gnu- menuconfig
# Enable: Device Drivers → Graphics → DRM → NVIDIA (nouveau or nvidia)

# Build
make ARCH=powerpc CROSS_COMPILE=powerpc64le-linux-gnu- -j$(nproc)

# Output: arch/powerpc/boot/zImage.pseries
```

## Testing Endianness

```bash
# Check current endianness
python3 -c "import sys; print(sys.byteorder)"
# 'little' or 'big'

# Check kernel
file /boot/vmlinux* | grep -i endian

# Check running binary
file /bin/ls
# LSB = little-endian
# MSB = big-endian

# Check CPU capability
grep -i endian /proc/cpuinfo
```

## References

- [Void Linux PPC64LE](https://voidlinux.org/download/#ppc64le)
- [Gentoo PPC64 Handbook](https://wiki.gentoo.org/wiki/Handbook:PPC64)
- [Linux PowerPC Little-Endian](https://wiki.raptorcs.com/wiki/Little-endian)
- [Nouveau Driver Source](https://github.com/skeggsb/nouveau)
- [IBM POWER Endianness](https://www.ibm.com/docs/en/linux-on-systems?topic=lpplrm-linux-power-little-endian)
