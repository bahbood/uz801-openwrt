#!/bin/bash
set -e

# ============================================================
# UZ801 OpenWrt reproducible build
# Target: FY UZ801 V3 / V3.2 - MSM8916
# ============================================================

BUILD_PACKAGES_ONLY=0

if [ "$1" = "-packages" ]; then
    BUILD_PACKAGES_ONLY=1
fi

# ------------------------------------------------------------
# Fixed versions
# ------------------------------------------------------------

OPENWRT_VERSION="v25.12.5"
OPENWRT_REPO="https://git.openwrt.org/openwrt/openwrt.git"

AWG_VERSION="v25.12.5"
AWG_REPO="https://github.com/Slava-Shchipunov/awg-openwrt.git"

# ------------------------------------------------------------
# Fixed dependency commits used by the UZ801 target
# ------------------------------------------------------------

QHYPSTUB_COMMIT="fca3c513b6fb5e5b8fabae21dac1f4a5c0b51bc6"
LK2ND_COMMIT="87ccbc5a5502d4dd8183bf3a4279d90704330fb9"
QTESTSIGN_COMMIT="f3df53a5f0e37ccee076541f30f9d5b8340fc2d3"

QRTR_COMMIT="5923eea97377f4a3ed9121b358fd919e3659db7b"
RMTFS_COMMIT="586372e575f5cc1a7cbb170219ab6df98f394cae"

# ------------------------------------------------------------
# Basic checks
# ------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo
echo "============================================================"
echo " UZ801 OpenWrt reproducible build"
echo "============================================================"
echo
echo "OpenWrt : $OPENWRT_VERSION"
echo "AWG     : $AWG_VERSION"
echo

if [ ! -f "diffconfig_uz801" ]; then
    echo "ERROR: diffconfig_uz801 not found."
    exit 1
fi

if [ ! -d "msm89xx" ]; then
    echo "ERROR: msm89xx directory not found."
    exit 1
fi

if [ ! -d "packages" ]; then
    echo "ERROR: packages directory not found."
    exit 1
fi

# ------------------------------------------------------------
# Debian dependencies
# ------------------------------------------------------------

export DEBIAN_FRONTEND=noninteractive

echo "[1/10] Installing build dependencies..."

sudo -E apt-get update -qq

sudo -E apt-get install -y --no-install-recommends \
    build-essential \
    clang \
    flex \
    bison \
    g++ \
    gawk \
    gcc-multilib \
    g++-multilib \
    gettext \
    git \
    libncurses5-dev \
    libssl-dev \
    python3-setuptools \
    rsync \
    swig \
    unzip \
    zlib1g-dev \
    file \
    wget \
    python3-cryptography \
    mkbootimg \
    qemu-utils \
    asciidoc \
    help2man \
    xsltproc \
    bc \
    binutils \
    bzip2 \
    make \
    patch \
    time \
    device-tree-compiler \
    e2fsprogs \
    fdisk \
    util-linux \
    nano \
    perl \
    perl-modules \
    python3-dev \
    xz-utils \
    zstd \
    zip \
    libelf-dev \
    libfdt-dev \
    gcc-arm-none-eabi \
    binutils-arm-none-eabi

# ------------------------------------------------------------
# OpenWrt source
# ------------------------------------------------------------

echo
echo "[2/10] Preparing OpenWrt $OPENWRT_VERSION..."

if [ ! -d "openwrt" ]; then

    echo "Cloning OpenWrt..."

    git clone \
        --branch "$OPENWRT_VERSION" \
        --depth 1 \
        "$OPENWRT_REPO" \
        openwrt

else

    echo "OpenWrt directory already exists."

    cd openwrt

    CURRENT_VERSION="$(git describe --tags --exact-match 2>/dev/null || true)"

    if [ "$CURRENT_VERSION" != "$OPENWRT_VERSION" ]; then

        echo
        echo "ERROR:"
        echo "Existing OpenWrt source is:"
        echo "  ${CURRENT_VERSION:-unknown}"
        echo
        echo "Expected:"
        echo "  $OPENWRT_VERSION"
        echo
        echo "Remove the existing openwrt directory or checkout"
        echo "the required version manually."
        exit 1
    fi

    cd "$SCRIPT_DIR"
fi

# Verify exact OpenWrt revision

OPENWRT_COMMIT="$(git -C openwrt rev-parse HEAD)"

echo
echo "OpenWrt commit:"
echo "$OPENWRT_COMMIT"

# ------------------------------------------------------------
# Apply UZ801 patches
# ------------------------------------------------------------

echo
echo "[3/10] Applying UZ801 mac80211 patches..."

chmod +x ./apply_patches.sh

./apply_patches.sh openwrt

# ------------------------------------------------------------
# Copy target files
# ------------------------------------------------------------

echo
echo "[4/10] Installing UZ801 target files..."

mkdir -p openwrt/target/linux/msm89xx
mkdir -p openwrt/package/msm8916

cp -a msm89xx/. \
    openwrt/target/linux/msm89xx/

cp -a packages/. \
    openwrt/package/msm8916/

# ------------------------------------------------------------
# Verify important UZ801 files
# ------------------------------------------------------------

echo
echo "[5/10] Verifying UZ801 source tree..."

REQUIRED_FILES=(
    "openwrt/target/linux/msm89xx/Makefile"
    "openwrt/target/linux/msm89xx/image/Makefile"
    "openwrt/target/linux/msm89xx/modules.mk"
)

for FILE in "${REQUIRED_FILES[@]}"; do
    if [ ! -f "$FILE" ]; then
        echo "ERROR: Missing $FILE"
        exit 1
    fi
done

# ------------------------------------------------------------
# Feeds
# ------------------------------------------------------------

cd openwrt

echo
echo "[6/10] Updating OpenWrt feeds..."

./scripts/feeds update -a
./scripts/feeds install -a

cd "$SCRIPT_DIR"

# ------------------------------------------------------------
# AmneziaWG
# ------------------------------------------------------------

echo
echo "[7/10] Installing AmneziaWG $AWG_VERSION..."

if [ ! -d "awg-src" ]; then

    git clone \
        --branch "$AWG_VERSION" \
        --depth 1 \
        "$AWG_REPO" \
        awg-src

else

    echo "awg-src already exists."

    CURRENT_AWG="$(git -C awg-src describe --tags --exact-match 2>/dev/null || true)"

    if [ "$CURRENT_AWG" != "$AWG_VERSION" ]; then
        echo
        echo "ERROR:"
        echo "Existing AWG source is:"
        echo "  ${CURRENT_AWG:-unknown}"
        echo
        echo "Expected:"
        echo "  $AWG_VERSION"
        exit 1
    fi
fi

# Remove previous copies if they exist

rm -rf \
    openwrt/package/kmod-amneziawg \
    openwrt/package/amneziawg-tools \
    openwrt/package/luci-proto-amneziawg

cp -a awg-src/kmod-amneziawg \
    openwrt/package/

cp -a awg-src/amneziawg-tools \
    openwrt/package/

cp -a awg-src/luci-proto-amneziawg \
    openwrt/package/

AWG_COMMIT="$(git -C awg-src rev-parse HEAD)"

echo
echo "AmneziaWG commit:"
echo "$AWG_COMMIT"

# ------------------------------------------------------------
# Configuration
# ------------------------------------------------------------

echo
echo "[8/10] Applying UZ801 configuration..."

cd openwrt

cp ../diffconfig_uz801 .config

make defconfig

echo
echo "Final target:"
grep '^CONFIG_TARGET_' .config | grep -E \
    'msm89xx|msm8916|yiming'

echo
echo "Important packages:"
grep '^CONFIG_PACKAGE_' .config | grep -E \
    'qmi|qrtr|rmtfs|wcn|modem|zhihe|sms|amnezia|firewall|dnsmasq'

cd "$SCRIPT_DIR"

# ------------------------------------------------------------
# Download sources
# ------------------------------------------------------------

echo
echo "[9/10] Downloading sources..."

cd openwrt

CORES="$(nproc 2>/dev/null || echo 2)"

echo "Build jobs: $CORES"

make download -j"$CORES"

# ------------------------------------------------------------
# Build
# ------------------------------------------------------------

echo
echo "[10/10] Starting OpenWrt build..."
echo

if [ "$BUILD_PACKAGES_ONLY" -eq 1 ]; then

    echo "============================================================"
    echo " PACKAGE-ONLY BUILD"
    echo "============================================================"

    make tools/install -j"$CORES"

    make toolchain/install -j"$CORES"

    make target/linux/compile -j"$CORES" \
        || make target/linux/compile -j1 V=s

    echo
    echo "Building UZ801 custom packages..."

    for pkg_dir in ../packages/*; do

        if [ -d "$pkg_dir" ]; then

            pkg_name="$(basename "$pkg_dir")"

            echo
            echo "------------------------------------------------------------"
            echo "Building package: $pkg_name"
            echo "------------------------------------------------------------"

            make "package/msm8916/$pkg_name/compile" -j"$CORES" \
                || make "package/msm8916/$pkg_name/compile" -j1 V=s
        fi

    done

    echo
    echo "Building AmneziaWG packages..."

    make "package/kmod-amneziawg/compile" -j"$CORES" \
        || make "package/kmod-amneziawg/compile" -j1 V=s

    make "package/amneziawg-tools/compile" -j"$CORES" \
        || make "package/amneziawg-tools/compile" -j1 V=s

    make "package/luci-proto-amneziawg/compile" -j"$CORES" \
        || make "package/luci-proto-amneziawg/compile" -j1 V=s

    echo
    echo "============================================================"
    echo " Package build completed"
    echo "============================================================"

    echo
    echo "Packages:"
    find bin/packages -type f \
        \( -name '*amneziawg*' -o -name '*qmi*' -o -name '*rmtfs*' \) \
        -print

else

    make -j"$CORES" \
        || make -j1 V=s

    echo
    echo "============================================================"
    echo " Firmware build completed"
    echo "============================================================"

    TARGET_DIR="bin/targets/msm89xx/msm8916"

    echo
    echo "Output directory:"
    echo "$TARGET_DIR"
    echo

    if [ -d "$TARGET_DIR" ]; then

        echo "Generated files:"
        ls -lh "$TARGET_DIR"

    else

        echo "WARNING: target output directory not found:"
        echo "$TARGET_DIR"

    fi

fi

echo
echo "============================================================"
echo " BUILD FINISHED"
echo "============================================================"
echo
echo "OpenWrt : $OPENWRT_VERSION"
echo "Commit  : $OPENWRT_COMMIT"
echo "AWG     : $AWG_VERSION"
echo "AWG SHA : ${AWG_COMMIT:-not-built}"
echo
