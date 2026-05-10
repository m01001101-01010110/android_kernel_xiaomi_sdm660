#!/bin/bash

# Device Tree Validation Script
# Validates device tree compatibility for kernel 4.19 on jasmine_sprout

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

DEVICE="jasmine_sprout"
DEVICE_ARCH="arm64"
DTS_PATH="arch/${DEVICE_ARCH}/boot/dts/qcom"

echo -e "${GREEN}=== Device Tree Validation for ${DEVICE} ===${NC}"
echo ""

if ! command -v dtc &> /dev/null; then
    echo -e "${RED}[!] dtc not found. Install: apt-get install device-tree-compiler${NC}"
    exit 1
fi

echo -e "${GREEN}[*] Checking device tree files...${NC}"
echo ""

# Find all DTS files for device
if [ ! -d "${DTS_PATH}" ]; then
    echo -e "${RED}[!] DTS path not found: ${DTS_PATH}${NC}"
    exit 1
fi

dts_files=$(find ${DTS_PATH} -name "${DEVICE}*.dts" -o -name "${DEVICE}*.dtsi")

if [ -z "${dts_files}" ]; then
    echo -e "${YELLOW}[!] Warning: No DTS files found for ${DEVICE}${NC}"
else
    echo -e "${GREEN}Found DTS files:${NC}"
    echo "${dts_files}" | while read -r file; do
        echo "  • $(basename $file)"
    done
fi

echo ""
echo -e "${GREEN}[*] Validating DTS syntax...${NC}"
echo ""

failed=0
for dts in ${dts_files}; do
    dtb_file="/tmp/$(basename $dts .dts).dtb"
    if dtc -I dts -O dtb "${dts}" -o "${dtb_file}" 2>/dev/null; then
        echo -e "${GREEN}✓${NC} $(basename ${dts}) - OK ($(du -h ${dtb_file} | cut -f1))"
    else
        echo -e "${RED}✗${NC} $(basename ${dts}) - FAILED"
        echo "  Error details:"
        dtc -I dts -O dtb "${dts}" 2>&1 | sed 's/^/    /'
        ((failed++))
    fi
done

echo ""
echo -e "${GREEN}[*] Checking device tree properties...${NC}"
echo ""

# Check for critical DT properties
main_dts=$(find ${DTS_PATH} -name "${DEVICE}.dts" | head -1)

if [ -z "${main_dts}" ]; then
    echo -e "${YELLOW}[!] Warning: Main DTS file not found${NC}"
else
    echo "Checking: $(basename ${main_dts})"
    echo ""
    
    # Check for required nodes
    required_nodes=("soc" "cpus" "memory" "chosen")
    for node in "${required_nodes[@]}"; do
        if grep -q "${node}" "${main_dts}"; then
            echo -e "${GREEN}✓${NC} Node '${node}' found"
        else
            echo -e "${YELLOW}!${NC} Node '${node}' not found (may be included)"
        fi
    done
    
    echo ""
    echo -e "${GREEN}[*] Device tree bindings check:${NC}"
    echo ""
    
    # Extract compatible strings
    echo "Compatible strings:"
    grep -h "compatible" "${main_dts}" | head -10 | sed 's/^/  /'
fi

echo ""
echo -e "${GREEN}[*] Checking kernel config compatibility...${NC}"
echo ""

if [ -f "${OUTPUT_DIR:-./.output}/.config" ]; then
    config_file="${OUTPUT_DIR:-./.output}/.config"
    
    # Check critical DT-related configs
    dt_configs=(
        "CONFIG_OF"
        "CONFIG_OF_FLATTREE"
        "CONFIG_OF_EARLY_FLATTREE"
        "CONFIG_PINCTRL"
        "CONFIG_GPIO_SYSFS"
    )
    
    for config in "${dt_configs[@]}"; do
        if grep -q "^${config}=y" "${config_file}"; then
            echo -e "${GREEN}✓${NC} ${config}=y"
        else
            echo -e "${YELLOW}!${NC} ${config} not enabled"
        fi
    done
else
    echo -e "${YELLOW}[!] Kernel config not found. Build kernel first.${NC}"
fi

echo ""
echo -e "${GREEN}[*] Summary${NC}"
echo ""

if [ $failed -eq 0 ]; then
    echo -e "${GREEN}All device tree validations passed!${NC}"
else
    echo -e "${RED}${failed} validation(s) failed. Review errors above.${NC}"
    exit 1
fi
