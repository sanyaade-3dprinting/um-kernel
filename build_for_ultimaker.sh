#!/bin/bash

# This script builds the kernel, kernel modules, device trees and boot scripts for the A20 linux system that we use.

set -e
set -u

# Initialize repositories
git submodule init
git submodule update

if [ -z ${RELEASE_VERSION+x} ]; then
	RELEASE_VERSION=0.0.0
fi

# Which kernel to build
KERNEL=`pwd`/linux

# Which kernel config to build.
BUILDCONFIG="opinicus"

# Build the kernel
KCONFIG=`pwd`/configs/${BUILDCONFIG}_defconfig
pushd ${KERNEL}
# Configure the kernel
ARCH=arm make KCONFIG_CONFIG=${KCONFIG}
# Build the uImage file for a bootable kernel
ARCH=arm LOADADDR=0x40008000 make KCONFIG_CONFIG=${KCONFIG} uImage
# Build modules
ARCH=arm make KCONFIG_CONFIG=${KCONFIG} modules
# Build the device trees that we need
ARCH=arm make KCONFIG_CONFIG=${KCONFIG} sun7i-a20-olinuxino-lime2.dtb
ARCH=arm make KCONFIG_CONFIG=${KCONFIG} sun7i-a20-olinuxino-lime2-nand-4gb.dtb
ARCH=arm make KCONFIG_CONFIG=${KCONFIG} sun7i-a20-olinuxino-lime2-emmc.dtb
ARCH=arm make KCONFIG_CONFIG=${KCONFIG} sun7i-a20-opinicus_nand_v1.dtb
ARCH=arm make KCONFIG_CONFIG=${KCONFIG} sun7i-a20-opinicus_emmc_v1.dtb
popd

# Build the debian package
DEB_DIR=`pwd`/debian
mkdir -p "${DEB_DIR}/boot"
cp ${KERNEL}/arch/arm/boot/uImage "${DEB_DIR}/boot/uImage-sun7i-a20-opinicus_v1"
cp ${KERNEL}/arch/arm/boot/dts/sun7i-a20-olinuxino-lime2.dtb "${DEB_DIR}/boot"
cp ${KERNEL}/arch/arm/boot/dts/sun7i-a20-olinuxino-lime2-nand-4gb.dtb "${DEB_DIR}/boot"
cp ${KERNEL}/arch/arm/boot/dts/sun7i-a20-olinuxino-lime2-emmc.dtb "${DEB_DIR}/boot"
cp ${KERNEL}/arch/arm/boot/dts/sun7i-a20-opinicus_nand_v1.dtb "${DEB_DIR}/boot"
cp ${KERNEL}/arch/arm/boot/dts/sun7i-a20-opinicus_emmc_v1.dtb "${DEB_DIR}/boot"
pushd ${KERNEL}
ARCH=arm make KCONFIG_CONFIG=${KCONFIG} INSTALL_MOD_PATH="${DEB_DIR}" modules_install
popd

# Create the bootscripts for these kernels
cat > "${DEB_DIR}/boot/boot_mtd.cmd" <<-EOT
setenv bootargs console=tty0 ubi.mtd=main ubi.fm_autoconvert=1 root=ubi:rootfs ro rootwait rootfstype=ubifs console=ttyS0,115200 earlyprintk
setenv fdt_high 0xffffffff
ubifsload 0x43200000 "ultimaker_logo.bmp"
bmp d 0x43200000
ubifsload 0x46000000 uImage-sun7i-a20-opinicus_v1
ubifsload 0x49000000 sun7i-a20-opinicus_nand_v1.dtb
bootm 0x46000000 - 0x49000000
EOT
mkimage -A arm -O linux -T script -C none -a 0x43100000 -n "Boot script" -d "${DEB_DIR}/boot/boot_mtd.cmd" "${DEB_DIR}/boot/boot_mtd.scr"

cat > "${DEB_DIR}/boot/boot_mmc.cmd" <<-EOT
setenv bootargs console=tty0 root=/dev/mmcblk0p2 ro rootwait rootfstype=ext4 console=ttyS0,115200 earlyprintk
setenv fdt_high 0xffffffff
ext4load mmc 0 0x43200000 "ultimaker_logo.bmp"
bmp d 0x43200000
ext4load mmc 0 0x46000000 uImage-sun7i-a20-opinicus_v1
ext4load mmc 0 0x49000000 sun7i-a20-opinicus_nand_v1.dtb
bootm 0x46000000 - 0x49000000
EOT
mkimage -A arm -O linux -T script -C none -a 0x43100000 -n "Boot script" -d "${DEB_DIR}/boot/boot_mmc.cmd" "${DEB_DIR}/boot/boot_mmc.scr"

# Create a debian control file to pack up a debian package
mkdir -p "${DEB_DIR}/DEBIAN"
cat > "${DEB_DIR}/DEBIAN/control" <<-EOT
Package: linux
Source: linux-upstream
Version: ${RELEASE_VERSION}
Architecture: armhf
Maintainer: Anonymous <root@monolith.ultimaker.com>
Section: kernel
Priority: optional
Homepage: http://www.kernel.org/
Description: Linux kernel, kernel modules, binary device trees and boot scripts. All in a single package.
EOT

fakeroot dpkg-deb --build "${DEB_DIR}"
mv "${DEB_DIR}.deb" linux-opinicus-${RELEASE_VERSION}.deb