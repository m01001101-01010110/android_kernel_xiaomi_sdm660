# Kernel 4.4 to 4.19 Porting Guide for Xiaomi jasmine_sprout (Mi A2)

## Overview

This guide documents the process of porting Xiaomi's kernel 4.4 customizations to Linux Kernel 4.19 while maintaining maximum compatibility with vendor blobs and hardware drivers.

**Target Device:** Xiaomi Mi A2 (jasmine_sprout)
**Base Kernel:** Linux 4.4.302 → Linux 4.19.295
**Android Version:** LineageOS 18.1 → Newer versions

---

## Key Considerations

### 1. Vendor Blob Compatibility
- Xiaomi's proprietary blobs (camera HAL, modem, sensors) were compiled for kernel 4.4 ABI
- **Critical:** Extract and preserve Xiaomi's vendor modifications
- Device tree bindings must remain compatible
- SELinux policies need verification

### 2. Major Kernel Changes (4.4 → 4.19)
- Scheduler improvements (WALT → default)
- Power management enhancements
- Security patches (spectre/meltdown mitigations)
- IO scheduling updates
- Memory management improvements

### 3. Xiaomi Customizations to Preserve

Key areas where Xiaomi made custom modifications:

#### A. Display/DRM Drivers
- Adreno GPU driver modifications
- MDSS (Mobile Display SubSystem) customizations
- Backlight control enhancements

#### B. Power Management
- Custom thermal management
- Battery management driver (bms)
- CPU frequency scaling customizations
- Power states management

#### C. Audio/Camera
- Audio codec configurations
- Camera sensor driver patches
- ISP (Image Signal Processor) optimizations

#### D. Network/Modem
- Qualcomm modem driver patches
- RIL (Radio Interface Layer) interface customizations
- WLAN driver modifications

#### E. System Integration
- SELinux policies
- Kernel command line parameters
- Device tree customizations
- Boot parameters

---

## Porting Strategy

### Phase 1: Extract Xiaomi Customizations from 4.4

```bash
# Clone both kernels side by side
git clone -b lineage-18.1 <repo> kernel-4.4
git clone <upstream-4.19-qcom> kernel-4.19-base

# Generate patch set from Xiaomi's 4.4 changes
cd kernel-4.4
git diff linux-4.4.302..HEAD > xiaomi-4.4-patches.patch
```

### Phase 2: Identify Device-Specific Files

Key files/directories to analyze:

```
arch/arm64/boot/dts/
  └─ qcom/
     ├─ msm8998.dtsi              # SoC definitions
     ├─ jasmine_sprout.dts        # Device tree
     └─ jasmine_sprout-*-*.dts    # Variants

arch/arm64/configs/
  └─ jasmine_sprout_defconfig     # Kernel config

drivers/gpu/drm/msm/
  └─ [Display drivers]

drivers/media/platform/msm/
  └─ [Camera/Video]

sound/soc/msm/
  └─ [Audio drivers]

arch/arm64/kernel/
  └─ [CPU/Scheduler customizations]
```

### Phase 3: Apply Core 4.19 Base

```bash
# Start with clean 4.19 kernel
cd kernel-4.19-base
git checkout v4.19.295

# Add Xiaomi customizations selectively
# (NOT all patches, only device-specific ones)
```

### Phase 4: Cherry-Pick Xiaomi Changes

**Priority 1 (CRITICAL - Must have):**
- Device tree definitions
- Kernel defconfig
- Basic thermal/power management

**Priority 2 (IMPORTANT - Should have):**
- Display drivers
- Audio codec setup
- Camera sensor drivers
- RIL interface

**Priority 3 (NICE - Can have):**
- Optimizations
- Performance tweaks
- Debug features

---

## File-by-File Migration

### 1. Device Tree (CRITICAL)

**Source:** `arch/arm64/boot/dts/qcom/jasmine_sprout*.dts*`

**Action:**
- Copy device tree files as-is to 4.19
- Verify node names match 4.19 bindings
- Update compatible strings if needed
- Check for deprecated properties

```bash
# Validate device tree
dtc -I dts -O dtb arch/arm64/boot/dts/qcom/jasmine_sprout.dts -o /tmp/test.dtb
```

### 2. Kernel Configuration (CRITICAL)

**Source:** `arch/arm64/configs/jasmine_sprout_defconfig`

**Steps:**
```bash
# Extract 4.4 config
cat arch/arm64/configs/jasmine_sprout_defconfig > base.config

# Generate new 4.19 config
cd kernel-4.19
cp base.config .config
make oldconfig  # Answer questions about new options

# Review changes
diff base.config .config | head -50
```

**Key options to verify:**
- `CONFIG_THERMAL` - Thermal framework
- `CONFIG_QCOM_*` - Qualcomm drivers
- `CONFIG_PINCTRL` - Pin control
- `CONFIG_REGULATOR` - Voltage regulation
- `CONFIG_MMC` - Storage
- `CONFIG_USB` - USB support

### 3. Display Drivers

**Source:** `drivers/gpu/drm/msm/`

**4.4 Specific Changes:**
```bash
# Find Xiaomi patches
cd kernel-4.4
git log --oneline --all -- drivers/gpu/drm/msm/ | head -20

# Extract patches
git format-patch -o /tmp/drm-patches kernel-4.4..HEAD -- drivers/gpu/drm/msm/
```

**Porting Process:**
1. Check if changes already in 4.19 upstream
2. If not, manually apply with conflict resolution
3. Test on device: `adb logcat | grep drm`

### 4. Audio Drivers

**Source:** `sound/soc/msm/`

**Critical Elements:**
- WCD9335 codec driver
- Audio routing tables
- DAI configurations

### 5. Camera/Media

**Source:** `drivers/media/platform/msm/`

**Note:** Camera HAL is in proprietary blobs, kernel driver should be minimal customization

### 6. Power Management

**Source:** Multiple locations
- `drivers/thermal/`
- `drivers/cpufreq/`
- `drivers/power/`
- `drivers/regulator/`

**Strategy:**
- Use upstream 4.19 drivers as base
- Cherry-pick Xiaomi's custom thermal profiles
- Preserve battery management customizations

---

## Vendor Blob Compatibility

### Understanding Kernel-Userspace Interface

```
Kernel 4.4.302          Hardware
    ↓
  HALs (Camera, Audio, etc.) ← PROPRIETARY (compiled for 4.4 ABI)
    ↓
Android Framework
```

**Problem:** Vendor blobs expect 4.4 kernel symbols/ABIs

**Solution:**

1. **Identify ABI Dependencies**
```bash
# Check kernel symbols expected by HALs
nm -D proprietary-blobs/*.so | grep GLIBC

# Look for kernel module loading
adb shell lsmod | grep -i qcom
```

2. **Preserve Critical Symbols**
   - Export same symbols as 4.4
   - Maintain struct layouts
   - Keep device file interfaces unchanged

3. **Check Module Compatibility**
```bash
make modules
make modules_install INSTALL_MOD_PATH=/staging
# Verify all modules load in boot
```

---

## Building & Testing

### Build Commands

```bash
# Prepare
make distclean
make mrproper

# Configure
make O=out ARCH=arm64 jasmine_sprout_defconfig

# Build
make -j$(nproc) O=out ARCH=arm64 CROSS_COMPILE=aarch64-linux-android- \
  Image.gz dtbs modules

# Package boot image (requires Android boot tools)
python mkbootimg.py \
  --kernel out/arch/arm64/boot/Image.gz \
  --ramdisk ramdisk.cpio.gz \
  --dtb out/arch/arm64/boot/dtbs/qcom/jasmine_sprout.dtb \
  --base 0x00000000 \
  --pagesize 4096 \
  -o boot.img
```

### Testing Checklist

- [ ] Boot completes without panic
- [ ] All CPUs online
- [ ] Display functional
- [ ] Touch input working
- [ ] USB detection
- [ ] Camera HAL loads
- [ ] Audio functional
- [ ] Modem detection (logcat: `D/QMTI:`)
- [ ] Thermal management stable
- [ ] Battery status reading
- [ ] WiFi functional
- [ ] File I/O stable (internal storage)

### Debug Commands

```bash
# Boot log
adb logcat -b kernel

# Check loaded modules
adb shell lsmod

# Thermal info
adb shell cat /sys/class/thermal/thermal_zone*/temp

# CPU frequency
adb shell cat /sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_cur_freq

# Device tree dump
adb shell cat /proc/device-tree/compatible

# Display info
adb shell getprop ro.hardware.displayname
```

---

## Common Porting Issues & Solutions

### Issue 1: Thermal Shutdown on Boot
**Cause:** Thermal driver misconfiguration or sensor reading error
**Solution:**
```bash
# Check thermal config
grep -r "thermal" arch/arm64/boot/dts/qcom/jasmine_sprout*.dts

# Disable thermal throttling temporarily (DEBUG ONLY)
# Modify drivers/thermal/qcom/tsens.c
```

### Issue 2: No Display Output
**Cause:** DRM/MDSS driver incompatibility
**Solution:**
- Verify device tree display@ nodes
- Check `CONFIG_DRM_MSM` enabled
- Enable DRM debug: `echo 0x1f > /sys/module/drm/parameters/debug`

### Issue 3: Camera HAL Crashes
**Cause:** Kernel symbol mismatch
**Solution:**
```bash
# Extract camera HAL symbols
nm -D libcamera.so | grep qcamera_neon_

# Verify in kernel
nm vmlinux | grep qcamera_neon_
```

### Issue 4: Modem Not Detected
**Cause:** RIL/Modem driver not loading
**Solution:**
```bash
# Check modem firmware
adb shell ls -la /dev/mhi*

# Monitor modem subsystem
adb logcat | grep -i "subsys\|modem\|ril"
```

### Issue 5: Boot Loops
**Cause:** Incompatible kernel config or missing drivers
**Solution:**
```bash
# Enable more verbose logging
echo Y > /sys/module/printk/parameters/console_suspend

# Add boot parameter: "loglevel=8"
# Check dmesg buffer
adb shell dmesg | tail -50
```

---

## Optimization Opportunities

Once basic porting is complete, consider:

1. **Performance Tuning**
   - CPU scheduler tweaks (4.19 has better scheduler)
   - I/O elevator selection
   - Memory page cache tuning

2. **Power Efficiency**
   - Dynamic voltage/frequency scaling improvements
   - Idle power state optimization
   - Thermal profile refinement

3. **Security Enhancements**
   - SELinux enforcement
   - SMACK integration
   - Kernel hardening options

---

## Files to Reference

- `PORTING_CHECKLIST.txt` - Step-by-step checklist
- `build-kernel-4.19.sh` - Automated build script
- `device-tree-validation.sh` - DT verification
- `vendor-blob-check.sh` - HAL compatibility checker

---

## Support Resources

- XDA Developers: https://forum.xda-developers.com/
- Kernel.org Stable: https://www.kernel.org/
- Qualcomm Documentation (if available)
- LineageOS Wiki: https://wiki.lineageos.org/

---

## Version History

- **v1.0** (2026-05-10) - Initial porting guide created
