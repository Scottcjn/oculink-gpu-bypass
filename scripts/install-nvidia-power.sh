#!/bin/bash
#
# NVIDIA Tesla Driver Installer for IBM POWER8/POWER9 (ppc64le)
# Supports: K80, M40, P100, V100, V100S, T4
#
# (c) 2025 RustChain/Elyan Labs - MIT License
#

set -e

DRIVER_VERSION="440.64.00"
CUDA_VERSION="10.2"
DRIVER_URL="https://us.download.nvidia.com/tesla/${DRIVER_VERSION}/NVIDIA-Linux-ppc64le-${DRIVER_VERSION}.run"
CUDA_URL="https://developer.download.nvidia.com/compute/cuda/${CUDA_VERSION}/local_installers/cuda_${CUDA_VERSION}.89_440.33.01_linux_ppc64le.run"

INSTALL_DIR="/opt/nvidia-power"
LOG_FILE="/var/log/nvidia-power-install.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

check_arch() {
    local arch=$(uname -m)
    if [ "$arch" != "ppc64le" ]; then
        log "ERROR: This script requires ppc64le architecture (got: $arch)"
        log "For big-endian ppc64, NVIDIA drivers are NOT available."
        exit 1
    fi
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo "ERROR: Must run as root"
        exit 1
    fi
}

install_dependencies() {
    log "Installing build dependencies..."

    if command -v apt-get &>/dev/null; then
        apt-get update
        apt-get install -y \
            build-essential \
            linux-headers-$(uname -r) \
            dkms \
            wget \
            pkg-config \
            libglvnd-dev \
            libgl1-mesa-dev
    elif command -v yum &>/dev/null; then
        yum install -y \
            kernel-devel-$(uname -r) \
            kernel-headers-$(uname -r) \
            gcc \
            make \
            dkms \
            wget
    fi
}

download_driver() {
    log "Downloading NVIDIA driver ${DRIVER_VERSION} for ppc64le..."
    mkdir -p "$INSTALL_DIR"

    if [ ! -f "$INSTALL_DIR/NVIDIA-Linux-ppc64le-${DRIVER_VERSION}.run" ]; then
        wget -O "$INSTALL_DIR/NVIDIA-Linux-ppc64le-${DRIVER_VERSION}.run" "$DRIVER_URL"
    else
        log "Driver already downloaded"
    fi

    chmod +x "$INSTALL_DIR/NVIDIA-Linux-ppc64le-${DRIVER_VERSION}.run"
}

download_cuda() {
    log "Downloading CUDA ${CUDA_VERSION} toolkit for ppc64le..."

    if [ ! -f "$INSTALL_DIR/cuda_${CUDA_VERSION}_ppc64le.run" ]; then
        wget -O "$INSTALL_DIR/cuda_${CUDA_VERSION}_ppc64le.run" "$CUDA_URL"
    else
        log "CUDA toolkit already downloaded"
    fi

    chmod +x "$INSTALL_DIR/cuda_${CUDA_VERSION}_ppc64le.run"
}

blacklist_nouveau() {
    log "Blacklisting nouveau driver..."

    cat > /etc/modprobe.d/blacklist-nouveau.conf << 'EOF'
blacklist nouveau
options nouveau modeset=0
EOF

    # Rebuild initramfs
    if command -v update-initramfs &>/dev/null; then
        update-initramfs -u
    elif command -v dracut &>/dev/null; then
        dracut --force
    fi
}

install_driver() {
    log "Installing NVIDIA driver..."

    # Unload nouveau if loaded
    if lsmod | grep -q nouveau; then
        log "Unloading nouveau..."
        rmmod nouveau 2>/dev/null || true
    fi

    # Run installer
    "$INSTALL_DIR/NVIDIA-Linux-ppc64le-${DRIVER_VERSION}.run" \
        --silent \
        --no-questions \
        --dkms \
        --no-drm \
        --disable-nouveau \
        2>&1 | tee -a "$LOG_FILE"

    # Load module
    log "Loading nvidia module..."
    modprobe nvidia

    # Verify
    if nvidia-smi &>/dev/null; then
        log "SUCCESS: NVIDIA driver installed!"
        nvidia-smi
    else
        log "ERROR: nvidia-smi failed - check $LOG_FILE"
        exit 1
    fi
}

install_cuda() {
    log "Installing CUDA toolkit..."

    "$INSTALL_DIR/cuda_${CUDA_VERSION}_ppc64le.run" \
        --silent \
        --toolkit \
        --no-drm \
        2>&1 | tee -a "$LOG_FILE"

    # Add to path
    cat >> /etc/profile.d/cuda.sh << 'EOF'
export PATH=/usr/local/cuda/bin:$PATH
export LD_LIBRARY_PATH=/usr/local/cuda/lib64:$LD_LIBRARY_PATH
EOF

    log "CUDA installed to /usr/local/cuda"
}

create_systemd_service() {
    log "Creating nvidia-persistenced service..."

    cat > /etc/systemd/system/nvidia-persistenced.service << 'EOF'
[Unit]
Description=NVIDIA Persistence Daemon
Wants=syslog.target
After=syslog.target

[Service]
Type=forking
ExecStart=/usr/bin/nvidia-persistenced --user root
ExecStopPost=/bin/rm -rf /var/run/nvidia-persistenced

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable nvidia-persistenced
    systemctl start nvidia-persistenced
}

# Main
main() {
    log "=== NVIDIA Tesla Driver Installer for POWER ==="
    log "Driver version: $DRIVER_VERSION"
    log "CUDA version: $CUDA_VERSION"

    check_root
    check_arch

    case "${1:-install}" in
        install)
            install_dependencies
            download_driver
            blacklist_nouveau
            install_driver
            create_systemd_service
            log "=== Installation Complete ==="
            log "Run 'nvidia-smi' to verify GPU detection"
            ;;
        cuda)
            download_cuda
            install_cuda
            log "=== CUDA Installation Complete ==="
            log "Source /etc/profile.d/cuda.sh or log out/in"
            ;;
        download-only)
            download_driver
            download_cuda
            log "Files downloaded to $INSTALL_DIR"
            ;;
        *)
            echo "Usage: $0 [install|cuda|download-only]"
            exit 1
            ;;
    esac
}

main "$@"
