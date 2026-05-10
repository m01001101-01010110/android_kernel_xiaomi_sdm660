#!/bin/bash

# Build Script for Kernel 4.19 on jasmine_sprout
# This script automates the kernel build process with proper configuration

set -e  # Exit on error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
KERNEL_VERSION="4.19.295"
DEVICE="jasmine_sprout"
DEVICE_ARCH="arm64"
OUTPUT_DIR="./out"
CROSS_COMPILE="aarch64-linux-android-"
MAKE_JOBS=$(nproc)
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOG_FILE="build_${TIMESTAMP}.log"

echo -e "${GREEN}=== Kernel 4.19 Build Script for ${DEVICE} ===${NC}"
echo -e "${YELLOW}Version: ${KERNEL_VERSION}${NC}"
echo -e "${YELLOW}Output: ${OUTPUT_DIR}${NC}"
echo -e "${YELLOW}Log: ${LOG_FILE}${NC}"
echo ""

# Function to print status
print_status() {
    echo -e "${GREEN}[*]${NC} $1"
}

print_error() {
    echo -e "${RED}[!]${NC} $1" >&2
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

# Check prerequisites
print_status "Checking prerequisites..."

if ! command -v "${CROSS_COMPILE}gcc" &> /dev/null; then
    print_error "Cross-compiler not found: ${CROSS_COMPILE}gcc"
    print_error "Install: apt-get install gcc-aarch64-linux-android"
    exit 1
fi

if ! command -v make &> /dev/null; then
    print_error "make not found"
    exit 1
fi

if ! command -v dtc &> /dev/null; then
    print_warning "dtc not found - device tree compilation may fail"
fi

print_status "Prerequisites OK"
echo ""

# Clean build directory
print_status "Preparing build directory..."
rm -rf ${OUTPUT_DIR}
mkdir -p ${OUTPUT_DIR}
echo "" | tee -a ${LOG_FILE}

# Clean kernel source
print_status "Cleaning kernel source..."
make distclean 2>&1 | tee -a ${LOG_FILE}
make mrproper 2>&1 | tee -a ${LOG_FILE}
echo "" | tee -a ${LOG_FILE}

# Configure kernel
print_status "Configuring kernel for ${DEVICE}..."
if [ ! -f "arch/${DEVICE_ARCH}/configs/${DEVICE}_defconfig" ]; then
    print_error "Device config not found: arch/${DEVICE_ARCH}/configs/${DEVICE}_defconfig"
    exit 1
fi

make O=${OUTPUT_DIR} ARCH=${DEVICE_ARCH} ${DEVICE}_defconfig 2>&1 | tee -a ${LOG_FILE}
echo "" | tee -a ${LOG_FILE}

# Show configuration summary
print_status "Configuration Summary:"
echo "CONFIG_THERMAL=$(grep CONFIG_THERMAL ${OUTPUT_DIR}/.config)"
echo "CONFIG_CPUFREQ=$(grep CONFIG_CPUFREQ ${OUTPUT_DIR}/.config | head -1)"
echo "CONFIG_DRM_MSM=$(grep CONFIG_DRM_MSM ${OUTPUT_DIR}/.config)"
echo "CONFIG_USB=$(grep '^CONFIG_USB=' ${OUTPUT_DIR}/.config)"
echo "" | tee -a ${LOG_FILE}

# Build kernel image
print_status "Building kernel image (${MAKE_JOBS} jobs)..."
start_time=$(date +%s)

if make -j${MAKE_JOBS} O=${OUTPUT_DIR} \
    ARCH=${DEVICE_ARCH} \
    CROSS_COMPILE=${CROSS_COMPILE} \
    Image.gz 2>&1 | tee -a ${LOG_FILE}; then
    
    end_time=$(date +%s)
    build_time=$((end_time - start_time))
    print_status "Kernel image built successfully (${build_time}s)"
    ls -lh ${OUTPUT_DIR}/arch/${DEVICE_ARCH}/boot/Image.gz
    echo "" | tee -a ${LOG_FILE}
else
    print_error "Kernel build failed!"
    tail -20 ${LOG_FILE}
    exit 1
fi

# Build device tree
print_status "Building device tree..."
if make -j${MAKE_JOBS} O=${OUTPUT_DIR} \
    ARCH=${DEVICE_ARCH} \
    CROSS_COMPILE=${CROSS_COMPILE} \
    dtbs 2>&1 | tee -a ${LOG_FILE}; then
    
    print_status "Device tree built successfully"
    ls -lh ${OUTPUT_DIR}/arch/${DEVICE_ARCH}/boot/dts/qcom/${DEVICE}*.dtb 2>/dev/null || \
        print_warning "Device tree files not found - check path"
    echo "" | tee -a ${LOG_FILE}
else
    print_error "Device tree build failed!"
    exit 1
fi

# Build kernel modules
print_status "Building kernel modules..."
if make -j${MAKE_JOBS} O=${OUTPUT_DIR} \
    ARCH=${DEVICE_ARCH} \
    CROSS_COMPILE=${CROSS_COMPILE} \
    modules 2>&1 | tee -a ${LOG_FILE}; then
    
    print_status "Kernel modules built successfully"
    module_count=$(find ${OUTPUT_DIR} -name "*.ko" | wc -l)
    echo "Found ${module_count} kernel modules"
    echo "" | tee -a ${LOG_FILE}
else
    print_error "Kernel modules build failed!"
    exit 1
fi

# Optional: Create module staging directory
print_status "Staging kernel modules..."
make O=${OUTPUT_DIR} ARCH=${DEVICE_ARCH} CROSS_COMPILE=${CROSS_COMPILE} \
    INSTALL_MOD_PATH=${OUTPUT_DIR}/modules_staging \
    modules_install 2>&1 | tee -a ${LOG_FILE}
echo "" | tee -a ${LOG_FILE}

# Create output summary
print_status "Creating build summary..."
cat > ${OUTPUT_DIR}/BUILD_INFO.txt << EOF
Kernel Build Information
========================

Device: ${DEVICE}
Kernel Version: ${KERNEL_VERSION}
Build Date: $(date)
Build Duration: ${build_time}s

Output Files:
- Kernel Image: ${OUTPUT_DIR}/arch/${DEVICE_ARCH}/boot/Image.gz
- Device Tree: ${OUTPUT_DIR}/arch/${DEVICE_ARCH}/boot/dts/qcom/${DEVICE}*.dtb
- Kernel Modules: ${OUTPUT_DIR}/modules_staging/

Next Steps:
1. Pack kernel with mkbootimg (requires ramdisk)
2. Verify with: adb logcat
3. Check thermal: adb shell cat /sys/class/thermal/thermal_zone*/temp
4. Monitor modem: adb logcat | grep -i modem

EOF
cat ${OUTPUT_DIR}/BUILD_INFO.txt
echo "" | tee -a ${LOG_FILE}

# Verify critical files exist
print_status "Verifying build artifacts..."

files_to_check=(
    "${OUTPUT_DIR}/arch/${DEVICE_ARCH}/boot/Image.gz"
    "${OUTPUT_DIR}/.config"
)

all_good=true
for file in "${files_to_check[@]}"; do
    if [ -f "${file}" ]; then
        print_status "✓ ${file##*/} found"
    else
        print_error "✗ ${file##*/} NOT FOUND"
        all_good=false
    fi
done

echo "" | tee -a ${LOG_FILE}

if [ "$all_good" = true ]; then
    print_status "${GREEN}Build completed successfully!${NC}"
    echo ""
    echo -e "${GREEN}Build artifacts:${NC}"
    echo "  • Kernel: ${OUTPUT_DIR}/arch/${DEVICE_ARCH}/boot/Image.gz"
    echo "  • DTB: ${OUTPUT_DIR}/arch/${DEVICE_ARCH}/boot/dts/qcom/${DEVICE}*.dtb"
    echo "  • Modules: ${OUTPUT_DIR}/modules_staging/"
    echo "  • Config: ${OUTPUT_DIR}/.config"
    echo ""
    echo -e "${YELLOW}To pack boot image:${NC}"
    echo "  mkbootimg --kernel ${OUTPUT_DIR}/arch/${DEVICE_ARCH}/boot/Image.gz \\"
    echo "    --ramdisk ramdisk.cpio.gz \\"
    echo "    --dtb ${OUTPUT_DIR}/arch/${DEVICE_ARCH}/boot/dts/qcom/${DEVICE}.dtb \\"
    echo "    --base 0x00000000 --pagesize 4096 -o boot.img"
    echo ""
else
    print_error "Some build artifacts are missing. Check log: ${LOG_FILE}"
    exit 1
fi

echo -e "${YELLOW}Build log: ${LOG_FILE}${NC}"
