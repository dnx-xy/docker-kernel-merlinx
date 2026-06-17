#!/bin/bash
set -euo pipefail

# Build kernel for merlinx (Redmi Note 9) on Ubuntu x86_64
# Produces AnyKernel3 flashable zip

KERNEL_DIR="$(cd "$(dirname "$0")" && pwd)"
OUT_DIR="$KERNEL_DIR/out"
ZIP_NAME="ShockwaveKernel-Docker-$(date +%Y%m%d-%H%M).zip"
CLANG_VERSION="21.0.0git-20250425-release"
CLANG_URL="https://github.com/ZyCromerZ/Clang/releases/download/${CLANG_VERSION}/Clang-${CLANG_VERSION}.tar.gz"
CLANG_DIR="/opt/neutron-clang"

# Color output
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# -------------------- Dependencies --------------------
install_deps() {
    info "Installing dependencies..."
    sudo apt-get update
    sudo apt-get install -y bc bison build-essential ccache curl flex \
        libssl-dev zip zlib1g-dev libncurses-dev python3 \
        gcc-aarch64-linux-gnu gcc-arm-linux-gnueabi cpio
}

# -------------------- Toolchain --------------------
setup_toolchain() {
    if [ -f "$CLANG_DIR/bin/clang" ]; then
        info "Neutron Clang already installed at $CLANG_DIR"
    else
        info "Downloading Neutron Clang..."
        sudo mkdir -p "$CLANG_DIR"
        cd /tmp
        curl -LSs "$CLANG_URL" -o clang.tar.gz
        sudo tar -xzf clang.tar.gz -C "$CLANG_DIR"
        rm clang.tar.gz
        info "Neutron Clang installed"
    fi
    export PATH="$CLANG_DIR/bin:$PATH"
}

# -------------------- Build --------------------
build_kernel() {
    info "Configuring kernel..."
    mkdir -p "$OUT_DIR"
    cd "$KERNEL_DIR"

    make ARCH=arm64 CC=clang LD=ld.lld \
        AR=llvm-ar NM=llvm-nm OBJCOPY=llvm-objcopy \
        STRIP=llvm-strip OBJDUMP=llvm-objdump READELF=llvm-readelf \
        CROSS_COMPILE=aarch64-linux-gnu- \
        CROSS_COMPILE_ARM32=arm-linux-gnueabi- \
        LLVM=1 LLVM_IAS=1 -j"$(nproc)" \
        O="$OUT_DIR" \
        merlin_defconfig

    info "Building kernel..."
    make ARCH=arm64 CC=clang LD=ld.lld \
        AR=llvm-ar NM=llvm-nm OBJCOPY=llvm-objcopy \
        STRIP=llvm-strip OBJDUMP=llvm-objdump READELF=llvm-readelf \
        CROSS_COMPILE=aarch64-linux-gnu- \
        CROSS_COMPILE_ARM32=arm-linux-gnueabi- \
        LLVM=1 LLVM_IAS=1 \
        CONFIG_NO_ERROR_ON_MISMATCH=y \
        O="$OUT_DIR" \
        -j"$(nproc)" 2>&1 | tee build.log
}

# -------------------- Package --------------------
package() {
    info "Packaging AnyKernel3 zip..."
    local temp_dir="$OUT_DIR/AnyKernel3"

    if [ -d "$temp_dir" ]; then
        cd "$temp_dir" && git pull
    else
        git clone --depth=1 https://github.com/osm0sis/AnyKernel3 "$temp_dir"
    fi

    cp "$OUT_DIR/arch/arm64/boot/Image.gz-dtb" "$temp_dir/"
    cp "$OUT_DIR/arch/arm64/boot/dts/mediatek/"*.dtbo "$temp_dir/" 2>/dev/null || true

    cd "$temp_dir"
    sed -i 's/do.devicecheck=1/do.devicecheck=0/g' anykernel.sh
    sed -i 's!BLOCK=/dev/block/platform/omap/omap_hsmmc.0/by-name/boot;!BLOCK=auto;!g' anykernel.sh
    sed -i 's/IS_SLOT_DEVICE=0;/is_slot_device=auto;/g' anykernel.sh

    zip -r9 "$KERNEL_DIR/$ZIP_NAME" * -x .git README.md '*placeholder'
    info "Package created: $KERNEL_DIR/$ZIP_NAME"
}

# -------------------- Main --------------------
case "${1:-all}" in
    deps)     install_deps ;;
    clang)    setup_toolchain ;;
    build)    setup_toolchain; build_kernel ;;
    package)  package ;;
    all)
        install_deps
        setup_toolchain
        build_kernel
        package
        ;;
    *)
        echo "Usage: $0 [deps|clang|build|package|all]"
        exit 1
        ;;
esac
