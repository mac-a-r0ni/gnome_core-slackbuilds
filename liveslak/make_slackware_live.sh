#!/bin/bash

# Copyright 2014, 2015, 2016, 2017, 2018, 2019, 2020, 2021, 2022  Eric Hameleers, Eindhoven, NL
# All rights reserved.
#
#   Permission to use, copy, modify, and distribute this software for
#   any purpose with or without fee is hereby granted, provided that
#   the above copyright notice and this permission notice appear in all
#   copies.
#
#   THIS SOFTWARE IS PROVIDED ``AS IS'' AND ANY EXPRESSED OR IMPLIED
#   WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
#   MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
#   IN NO EVENT SHALL THE AUTHORS AND COPYRIGHT HOLDERS AND THEIR
#   CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
#   SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
#   LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF
#   USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
#   ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
#   OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT
#   OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
#   SUCH DAMAGE.
# -----------------------------------------------------------------------------
#
# This script creates a live image for a Slackware OS.
# Features:
# - boots using isolinux/extlinux on BIOS, or grub on UEFI.
# - requires kernel >= 4.0 which supports multiple lower layers in overlay
# - uses squashfs to create compressed modules out of directory trees
# - uses overlayfs to bind multiple squashfs modules together
# - you can add your own modules into ./addons/ or ./optional subdirectories.
# - persistence is enabled when writing the ISO to USB stick using iso2usb.sh.
# - LUKS encrypted homedirectory is optional on USB stick using iso2usb.sh.
#
# -----------------------------------------------------------------------------

# Version of the Live OS generator:
VERSION="1.6.0"

# Timestamp:
THEDATE=$(date +%Y%m%d)

# Directory where our live tools are stored:
LIVE_TOOLDIR=${LIVE_TOOLDIR:-"$(cd $(dirname $0); pwd)"}

# Load the optional configuration file:
CONFFILE=${CONFFILE:-"${LIVE_TOOLDIR}/$(basename $0 .sh).conf"}
if [ -f ${CONFFILE} ]; then
  echo "-- Loading configuration file."
  . ${CONFFILE}
fi

# Set to "YES" to send error output to the console:
DEBUG=${DEBUG:-"NO"}

# Set to "YES" in order to delete everything we have,
# and rebuild any pre-existing .sxz modules from scratch:
FORCE=${FORCE:-"NO"}

# Set to 32 to be more compatible with the specs. Slackware uses 4 by default:
BOOTLOADSIZE=${BOOTLOADSIZE:-4}

# If you want to include an EFI boot image for 32bit Slackware then you
# need a recompiled grub which supports 32bit EFI (Slackware's grub will not).
# A patch for grub.SlackBuild to enable this feature can be found
# in the source directory. Works for both the 32bit and the 64bit grub package.
# Therefore we disable 32bit EFI by default. Enable at your own peril:
EFI32=${EFI32:-"NO"}

# Set to '1' using the "-S" parameter to the script,
# if the liveslak ISO should support SecureBoot-enabled computers:
SECUREBOOT=0

# Which shim to download and install?
# Supported are 'debian' 'fedora' 'opensuse'.
SHIM_3RDP=${SHIM_3RDP:-"fedora"}

# When enabling SecureBoot support, we need a MOK certificate plus private key,
# which we use to sign grub and kernel.
# MOKCERT contains the location of the certificate,
# to be defined through the '-S' parameter:
MOKCERT=""
# MOKPRIVKEY points to the location of the private key,
# to be defined through the '-S' parameter:
MOKPRIVKEY=""

# Set to NO if you want to use the non-SMP kernel on 32bit Slackware.
# note: unsupported option since Slackware enabled preemption in 5.14.15.
SMP32=${SMP32:-"YES"}

# Include support for NFS root (PXE boot), will increase size of the initrd:
NFSROOTSUP=${NFSROOTSUP:-"YES"}

# This variable can be set to a comma-separated list of package series.
# The squashfs module(s) for these package series will then be re-generated.
# Example commandline parameter: "-r l,kde,kdei"
REFRESH=""

# Use xorriso instead of mkisofs/isohybrid to create the ISO:
USEXORR=${USEXORR:-"NO"}

#
# ---------------------------------------------------------------------------
#

# Distribution name:
DISTRO=${DISTRO:-"slackware"}

# What type of Live image?
# Choices are: SLACKWARE, XFCE, LEAN, DAW, KTOWN, MATE, CINNAMON, DLACK, STUDIOWARE
LIVEDE=${LIVEDE:-"SLACKWARE"}

# The live username of the image:
LIVEUID=${LIVEUID:-"live"}

# The number of the live account in the image:
LIVEUIDNR=${LIVEUIDNR:-"1000"}

# The full name of the live account in the image can be set per Live variant,
# and will always be overridden by a LIVEUIDFN definition in the .conf file.
# The LIVEUIDFN defaults to '${DISTRO^} Live User' if not set explicitly:
LIVEUIDFN_DAW="${DISTRO^} Live Musician"

# The root and live user passwords of the image:
ROOTPW=${ROOTPW:-"root"}
LIVEPW=${LIVEPW:-"live"}

# The nvidia persistence account:
NVUID=${NVUID:-"nvidia"}
NVUIDNR=${NVUIDNR:-"365"}
NVGRP=${NVFRP:-"nvidia"}
NVGRPNR=${NVUIDNR:-"365"}

# The colord account:
CLRUID=${CLRUID:-"colord"}
CLRUIDNR=${CLRUIDNR:-"303"}
CLRGRP=${CLRGRP:-"colord"}
CLRGRPNR=${CLRUIDNR:-"303"}

# The avahi account:
AVUID=${AVUID:-"avahi"}
AVUIDNR=${AVUIDNR:-"214"}
AVGRP=${AVGRP:-"avahi"}
AVGRPNR=${AVUIDNR:-"214"}

# The flatpak account:
FPUID=${FPUID:-"flatpak"}
FPUIDNR=${FPUIDNR:-"372"}
FPGRP=${FPGRP:-"flatpak"}
FPGRPNR=${FPUIDNR:-"372"}

# The tss account:
TSUID=${TSUID:-"tss"}
TSUIDNR=${TSUIDNR:-"374"}
TSGRP=${TSGRP:-"tss"}
TSGRPNR=${TSUIDNR:-"374"}

# Custom name for the host:
LIVE_HOSTNAME=${LIVE_HOSTNAME:-"liveslack"}

# What runlevel to use if adding a DE like: XFCE, DAW, KTOWN etc...
RUNLEVEL=${RUNLEVEL:-4}

# Use the graphical syslinux menu (YES or NO)?
SYSMENU=${SYSMENU:-"YES"}

# The amount of seconds we want the init script to wait to give the kernel's
# USB subsystem time to settle. The default value of mkinitrd is "1" which
# is too short for use with USB sticks but "1" is fine for CDROM/DVD.
WAIT=${WAIT:-"5"}

#
# ---------------------------------------------------------------------------
#

# Who built the live image:
BUILDER=${BUILDER:-"jloc0/mac-a-r0ni"}

# Console font to use with syslinux for better language support:
CONSFONT=${CONSFONT:-"ter-i16v.psf"}

# The ISO main directory:
LIVEMAIN=${LIVEMAIN:-"liveslak"}

# Marker used for finding the Slackware Live files:
MARKER=${MARKER:-"SLACKWARELIVE"}

# The filesystem label we will be giving our ISO:
MEDIALABEL=${MEDIALABEL:-"LIVESLAK"}

# The name of the custom package list containing the generic kernel.
# This package list is special because the script will also take care of
# the ISO boot setup when processing the MINLIST package list:
MINLIST=${MINLIST:-"min"}

# For x86_64 you can add multilib:
MULTILIB=${MULTILIB:-"NO"}

# Use the '-G' parameter to generate the ISO from a pre-populated directory
# containing the live OS files:
ONLY_ISO="NO"

# The name of the directory used for storing persistence data:
PERSISTENCE=${PERSISTENCE:-"persistence"}

# Add a Core OS to load into RAM (currently supported for XFCE, LEAN, DAW):
CORE2RAM=${CORE2RAM:-"NO"}
CORE2RAMMODS="${MINLIST} noxbase"

# Slackware version to use (note: this won't work for Slackware <= 14.1):
SL_VERSION=${SL_VERSION:-"current"}

# Slackware architecture to install:
SL_ARCH=${SL_ARCH:-"x86_64"}

# Root directory of a Slackware local mirror tree;
# You can define custom repository location (must be in local filesystem)
# for any module in the file ./pkglists/<module>.conf:
SL_REPO=${SL_REPO:-"/home/liveslak"}
DEF_SL_REPO=${SL_REPO}

# The rsync URI of our default Slackware mirror server:
SL_REPO_URL=${SL_REPO_URL:-"rsync.osuosl.org::slackware"}
DEF_SL_REPO_URL=${SL_REPO_URL}

# List of Slackware package series - each will become a squashfs module:
SEQ_SLACKWARE="tagfile:a,ap,d,e,gcs,l,n,t,tcl,x,xap,y pkglist:slackextra,slackpkgplus"

# Stripped-down Slackware with XFCE as the Desktop Environment:
# - each series will become a squashfs module:
SEQ_XFCEBASE="${MINLIST},noxbase,x_base,xapbase,xfcebase local:mcpp"

# Stripped-down Base Slackware:
SEQ_LEAN="pkglist:${MINLIST},noxbase,x_base,xapbase,xfcebase,slackpkgplus,z00_plasma5supp,z01_plasma5base,z01_swdev"

# Stripped-down Slackware DAW with Plasma5 as the Desktop Environment:
# - each series will become a squashfs module.
# Note that loading the modules needs a specific order, which we force:
SEQ_DAW="pkglist:${MINLIST},noxbase,x_base,xapbase,slackpkgplus,z00_plasma5supp,z01_plasma5base,z01_plasma5extra,z01_swdev,z02_alien4daw,z02_alienrest4daw,z03_daw"

# Slackware with 'ktown' Plasma5 instead of its own KDE (full install):
# - each will become a squashfs module:
SEQ_KTOWN="tagfile:a,ap,d,e,f,k,l,n,t,tcl,x,xap,xfce,y pkglist:ktown,ktownalien,slackextra,slackpkgplus"

# List of Slackware package series with MSB instead of KDE (full install):
# - each will become a squashfs module:
SEQ_MSB="tagfile:a,ap,d,e,f,k,l,n,t,tcl,x,xap,xfce,y pkglist:mate,slackextra,slackpkgplus"

# List of Slackware package series with Cinnamon instead of KDE (full install):
# - each will become a squashfs module:
SEQ_CIN="tagfile:a,ap,d,e,f,k,l,n,t,tcl,x,xap,xfce,y pkglist:cinnamon,slackextra,slackpkgplus"

# Slackware package series with Gnome3/systemd instead of KDE (full install):
# - each will become a squashfs module:
SEQ_DLACK="tagfile:a,ap,d,e,f,k,l,n,t,tcl,x,xap pkglist:dlackware,slackextra,systemd"

# List of Slackware package series with StudioWare (full install):
# - each will become a squashfs module:
SEQ_STUDW="tagfile:a,ap,d,e,f,k,kde,l,n,t,tcl,x,xap,xfce,y pkglist:slackextra,slackpkgplus,studioware"

# Package blacklists for variants:
#BLACKLIST_DAW="seamonkey"
#BLACKLIST_LEAN="seamonkey"
#BLACKLIST_XFCE="gst-plugins-bad-free lynx mc motif mozilla-firefox pidgin xlockmore"

# Potentially we will use package(s) from 'testing' instead of regular repo:
#TESTINGLIST_DAW="kernel-generic kernel-modules kernel-headers kernel-source"
TESTINGLIST_DAW=""

# -- START: Used verbatim in upslak.sh -- #
# List of kernel modules required for a live medium to boot properly;
# Lots of HID modules added to support keyboard input for LUKS password entry;
# Virtio modules added to experiment with liveslak in a VM.
KMODS=${KMODS:-"squashfs:overlay:loop:xhci-pci:ohci-pci:ehci-pci:xhci-hcd:uhci-hcd:ehci-hcd:mmc-core:mmc-block:sdhci:sdhci-pci:sdhci-acpi:rtsx_pci:rtsx_pci_sdmmc:usb-storage:uas:hid:usbhid:i2c-hid:hid-generic:hid-apple:hid-cherry:hid-logitech:hid-logitech-dj:hid-logitech-hidpp:hid-lenovo:hid-microsoft:hid_multitouch:jbd:mbcache:ext3:ext4:isofs:fat:nls_cp437:nls_iso8859-1:msdos:vfat:exfat:ntfs:virtio_ring:virtio:virtio_blk:virtio_balloon:virtio_pci:virtio_pci_modern_dev:virtio_net"}

# Network kernel modules to include for NFS root support:
NETMODS="kernel/drivers/net kernel/drivers/virtio"

# Network kernel modules to exclude from above list:
NETEXCL="appletalk arcnet bonding can dummy.ko hamradio hippi ifb.ko irda macvlan.ko macvtap.ko pcmcia sb1000.ko team tokenring tun.ko usb veth.ko wan wimax wireless xen-netback.ko"
# -- END: Used verbatim in upslak.sh -- #

# Firmware for wired network cards required for NFS root support:
NETFIRMWARE="3com acenic adaptec bnx tigon e100 sun kaweth tr_smctr cxgb3 rtl_nic"

# If any Live variant needs additional 'append' parameters, define them here,
# either using a variable name 'KAPPEND_<LIVEDE>', or by defining 'KAPPEND' in the .conf file:
KAPPEND_SLACKWARE=""
KAPPEND_KTOWN="threadirqs"
KAPPEND_DAW="threadirqs preempt=full loglevel=3 audit=0"
KAPPEND_LEAN="threadirqs preempt=full loglevel=3 audit=0"
KAPPEND_STUDIOWARE="threadirqs preempt=full loglevel=3 audit=0"

# Add CACert root certificates yes/no?
ADD_CACERT=${ADD_CACERT:-"NO"}

# Default language selection for the Live OS; 'en' means generic English.
# This can be changed with the commandline switch "-l":
DEF_LANG="en"

#
# ---------------------------------------------------------------------------
#

# What compression to use for the initrd?
# Default is xz with CRC32 (the kernel's XZ decoder does not support CRC64),
# the alternative is gzip (which adds  ~30% to the initrd size).
COMPR=${COMPR:-"xz --check=crc32"}

# What compressors are available?
SQ_COMP_AVAIL="gzip lzma lzo xz zstd"

# What module exttensions do we accept:
SQ_EXT_AVAIL="sxz sfz szs xzm"

# Compressor optimizations:
declare -A SQ_COMP_PARAMS_DEF
SQ_COMP_PARAMS_DEF[gzip]=""
SQ_COMP_PARAMS_DEF[lzma]=""
SQ_COMP_PARAMS_DEF[lzo]=""
SQ_COMP_PARAMS_DEF[xz]="-b 512k -Xdict-size 100%"
SQ_COMP_PARAMS_DEF[zstd]="-b 512k -Xcompression-level 16"
declare -A SQ_COMP_PARAMS_OPT
SQ_COMP_PARAMS_OPT[gzip]=""
SQ_COMP_PARAMS_OPT[lzma]=""
SQ_COMP_PARAMS_OPT[lzo]=""
SQ_COMP_PARAMS_OPT[xz]="-b 1M"
SQ_COMP_PARAMS_OPT[zstd]="-b 1M -Xcompression-level 22"

# What compression to use for the squashfs modules?
# Default is xz, alternatives are gzip, lzma, lzo, zstd:
SQ_COMP=${SQ_COMP:-"xz"}

# Mount point where Live filesystem is assembled (no storage requirements):
LIVE_ROOTDIR=${LIVE_ROOTDIR:-"/mnt/slackwarelive"}

# Directory where the live ISO image will be written:
OUTPUT=${OUTPUT:-"/home/liveslak"}

# Directory where we create the staging directory:
TMP=${TMP:-"/tmp"}

# Toplevel directory of our staging area (this needs sufficient storage):
LIVE_STAGING=${LIVE_STAGING:-"${TMP}/slackwarelive_staging"}

# Work directory where we will create all the temporary stuff:
LIVE_WORK=${LIVE_WORK:-"${LIVE_STAGING}/temp"}

# Directory to be used by overlayfs for data manipulation,
# needs to be a directory in the same filesystem as ${LIVE_WORK}:
LIVE_OVLDIR=${LIVE_OVLDIR:-"${LIVE_WORK}/.ovlwork"}

# Directory where we will move the kernel and create the initrd;
# note that a ./boot directory will be created in here by installpkg:
LIVE_BOOT=${LIVE_BOOT:-"${LIVE_STAGING}/${LIVEMAIN}/bootinst"}

# Directories where the squashfs modules will be created:
LIVE_MOD_SYS=${LIVE_MOD_SYS:-"${LIVE_STAGING}/${LIVEMAIN}/system"}
LIVE_MOD_ADD=${LIVE_MOD_ADD:-"${LIVE_STAGING}/${LIVEMAIN}/addons"}
LIVE_MOD_OPT=${LIVE_MOD_OPT:-"${LIVE_STAGING}/${LIVEMAIN}/optional"}
LIVE_MOD_COS=${LIVE_MOD_COS:-"${LIVE_STAGING}/${LIVEMAIN}/core2ram"}

# ---------------------------------------------------------------------------
# Define some functions.
# ---------------------------------------------------------------------------

# Clean up in case of failure:
function cleanup() {
  # Clean up by unmounting our loopmounts, deleting tempfiles:
  echo "--- Cleaning up the staging area..."
  sync
  umount ${LIVE_ROOTDIR}/sys 2>${DBGOUT} || true
  umount ${LIVE_ROOTDIR}/proc 2>${DBGOUT} || true
  umount ${LIVE_ROOTDIR}/dev 2>${DBGOUT} || true
  umount ${LIVE_ROOTDIR} 2>${DBGOUT} || true
  # Need to umount the squashfs modules too:
  umount ${LIVE_WORK}/*_$$ 2>${DBGOUT} || true

  rmdir ${LIVE_ROOTDIR} 2>${DBGOUT}
  rmdir ${LIVE_WORK}/*_$$ 2>${DBGOUT}
  rm ${LIVE_MOD_COS}/* 2>${DBGOUT} || true
  rm ${LIVE_MOD_OPT}/* 2>${DBGOUT} || true
  rm ${LIVE_MOD_ADD}/* 2>${DBGOUT} || true
} # End of cleanup()

trap 'echo "*** $0 FAILED at line $LINENO ***"; cleanup; exit 1' ERR INT TERM

# Uncompress the initrd based on the compression algorithm used:
function uncompressfs() {
  if $(file "${1}" | grep -qi ": gzip"); then
    gzip -cd "${1}"
  elif $(file "${1}" | grep -qi ": XZ"); then
    xz -cd "${1}"
  fi
} # End of uncompressfs()

#
# Return the full pathname of first package found below $2 matching exactly $1:
#
function full_pkgname() {
  PACK=$1
  if [ -e $2 ]; then
    TOPDIR=$2
    # Perhaps I will use this more readable code in future:
    #for FL in $(find ${TOPDIR} -name "${PACK}-*.t?z" 2>/dev/null) ; do
    #  # Weed out package names starting with "$PACK"; we want exactly "$PACK":
    #  if [ "$(echo $FL |rev|cut -d- -f4-|cut -d/ -f1|rev)" != "$PACK" ]; then
    #    continue
    #  else
    #    break
    #  fi
    #done
    #echo "$FL"
    echo "$(find ${TOPDIR}/ -name "${PACK}-*.t?z" 2>/dev/null |grep -E "\<${PACK//+/\\+}-[^-]+-[^-]+-[^-]+.t?z" |head -1)"
  else
    echo ""
  fi
} # End of full_pkgname()

#
# Find packages and install them into the temporary root:
#
function install_pkgs() {
  if [ -z "$1" ]; then
    echo "-- function install_pkgs: Missing module name."
    cleanup
    exit 1
  fi
  if [ ! -d "$2" ]; then
    echo "-- function install_pkgs: Target directory '$2' does not exist!"
    cleanup
    exit 1
  elif [ ! -f "$2/${MARKER}" ]; then
    echo "-- function install_pkgs: Target '$2' does not contain '${MARKER}' file."
    echo "-- Did you choose the right installation directory?"
    cleanup
    exit 1
  fi

  # Define the default Slackware repository, can be overridden here:
  SL_REPO_URL="${DEF_SL_REPO_URL}"
  SL_REPO="${DEF_SL_REPO}"
  SL_PKGROOT="${DEF_SL_PKGROOT}"
  SL_PATCHROOT="${DEF_SL_PATCHROOT}"

  if [ "$3" = "local" -a -d ${LIVE_TOOLDIR}/local${DIRSUFFIX}/$1 ]; then
    echo "-- Installing local packages from subdir 'local${DIRSUFFIX}/$1'."
    #installpkg --terse --root "$2" "${LIVE_TOOLDIR}/local${DIRSUFFIX}/$1/*.t?z"
    ROOT="$2" upgradepkg --install-new --reinstall "${LIVE_TOOLDIR}"/local${DIRSUFFIX}/"$1"/*.t?z
  else
    # Load package list and (optional) custom repo info:
    if [ "$3" = "tagfile" ]; then
      PKGCONF="__tagfile__"
      PKGFILE=${SL_PKGROOT}/${1}/tagfile
    else
      PKGCONF=${LIVE_TOOLDIR}/pkglists/$(echo $1 |tr [A-Z] [a-z]).conf
      PKGFILE=${LIVE_TOOLDIR}/pkglists/$(echo $1 |tr [A-Z] [a-z]).lst
      if [ -f ${PKGCONF} ]; then
        echo "-- Loading repo info for '$1'."
        . ${PKGCONF}
      fi
    fi

    if [ "${SL_REPO}" = "${DEF_SL_REPO}" ]; then
      # SL_REPO was not re-defined in ${PKGCONF},
      # so we are dealing with an actual Slackware repository rootdir.
      # We select only the requested release in the Slackware package mirror;
      # This must *not* end with a '/' :
      SELECTION="${DISTRO}${DIRSUFFIX}-${SL_VERSION}"
    else
      SELECTION=""
    fi
    if [ ! -d ${SL_REPO} -o -z "$(find ${SL_PKGROOT}/ -type f 2>/dev/null)" ]; then
      # Oops... empty local repository. Let's see if we can rsync from remote:
      echo "** Slackware package repository root '${SL_REPO}' does not exist or is empty!"
      RRES=1
      if [ -n "${SL_REPO_URL}" ]; then
        mkdir -p ${SL_REPO}
        # Must be a rsync URL!
        echo "-- Rsync-ing repository content from '${SL_REPO_URL}' to local directory '${SL_REPO}'..."
        echo "-- This can be time-consuming.  Please wait."
        rsync -rlptD --no-motd --exclude=source ${RSYNCREP} ${SL_REPO_URL}/${SELECTION} ${SL_REPO}/
        RRES=$?
        echo "-- Done rsync-ing from '${SL_REPO_URL}'."
      fi
      if [ $RRES -ne 0 ]; then
        echo "** Exiting."
        cleanup
        exit 1
      fi
    fi

    if [ -f ${PKGFILE} ]; then
      echo "-- Loading package list '$PKGFILE'."
    else
      echo "-- Mandatory package list file '$PKGFILE' is missing! Exiting."
      cleanup
      exit 1
    fi

    for PKGPAT in $(cat ${PKGFILE} |grep -v -E '^ *#|^$' |cut -d: -f1); do
      # Extract the name of the package to install:
      PKG=$(echo $PKGPAT |cut -d% -f2)
      # Extract the name of the potential package to replace/remove:
      # - If there is no package to replace then the 'cut' will make
      #   REP equal to PKG.
      # - If PKG is empty then this is a request to remove the package.
      REP=$(echo $PKGPAT |cut -d% -f1)
      # Skip installation on detecting a blacklisted package:
      for BLST in ${BLACKLIST} BLNONE; do
        if [ "$PKG" == "$BLST" ]; then
          # Found a blacklisted package.
          break
        fi
      done
      # Sometimes we want to use a package in 'testing' instead:
      for PTST in ${TESTINGLIST} TSTNONE; do
        if [ "$PKG" == "$PTST" ]; then
          # Found a package to install from 'testing'.
          break
        fi
      done
      # Install a SMP kernel/modules if requested:
      if [ "${PKG}" = "kernel-generic" ] && [ "$SL_ARCH" != "x86_64" -a "$SMP32" = "YES" ]; then
        PKG="kernel-generic-smp"
      elif [ "${PKG}" = "kernel-modules" ] && [ "$SL_ARCH" != "x86_64" -a "$SMP32" = "YES" ]; then
        PKG="kernel-modules-smp"
      fi
      # Now decide what to do:
      if [ -z "${PKG}" ]; then
        # Package removal:
        ROOT="$2" removepkg "${REP}"
      elif [ "${PKG}" == "${BLST}" ]; then
        echo "-- Not installing blacklisted package '$PKG'."
      else
        if [ "${PKG}" == "${PTST}" ]; then
          echo "-- Installing package '$PKG' from 'testing'."
          FULLPKG=$(full_pkgname ${PKG} $(dirname ${SL_PKGROOT})/testing)
        else
          FULLPKG=""
        fi
        # Package install/upgrade:
        # Look in ./patches ; then ./${DISTRO}$DIRSUFFIX ; then ./extra
        # Need to escape any '+' in package names such a 'gtk+2'.
        if [ "x${FULLPKG}" = "x" ]; then
          if [ ! -z "${SL_PATCHROOT}" ]; then
            FULLPKG=$(full_pkgname ${PKG} ${SL_PATCHROOT})
          else
            FULLPKG=""
          fi
        fi
        if [ "x${FULLPKG}" = "x" ]; then
          FULLPKG=$(full_pkgname ${PKG} ${SL_PKGROOT})
        elif [ "${PKG}" != "${PTST}" ]; then
          echo "-- $PKG found in patches"
        fi
        if [ "x${FULLPKG}" = "x" ]; then
          # One last attempt: look in ./extra
          FULLPKG=$(full_pkgname ${PKG} $(dirname ${SL_PKGROOT})/extra)
        fi

        if [ "x${FULLPKG}" = "x" ]; then
          echo "-- Package $PKG was not found in $(dirname ${SL_REPO}) !"
        else
          # Determine if we need to install or upgrade a package:
          for INSTPKG in $(ls -1 "$2"/var/log/packages/${REP}-* 2>/dev/null |rev |cut -d/ -f1 |cut -d- -f4- |rev) ; do
            if [ "$INSTPKG" = "$REP" ]; then
              break
            fi
          done
          if [ "$INSTPKG" = "$REP" ]; then
            if [ "$PKG" = "$REP" ]; then
              ROOT="$2" upgradepkg --reinstall "${FULLPKG}"
            else
              # We need to replace one package (REP) with another (FULLPKG):
              ROOT="$2" upgradepkg "${REP}%${FULLPKG}"
            fi
          else
            installpkg --terse --root "$2" "${FULLPKG}"
          fi
        fi
      fi
    done
  fi

  if [ "$TRIM" = "doc" -o "$TRIM" = "mandoc"  -o "$TRIM" = "waste" -o "$TRIM" = "bloat" ]; then
    # Remove undesired (too big for a live OS) document subdirectories,
    # but leave cups alone because it contains the CUPS service's web page:
    (cd "${2}/usr/doc" && find . -type d -mindepth 2 -maxdepth 2 |grep -v /cups- |xargs rm -rf)
    rm -rf "$2"/usr/share/gtk-doc
    rm -rf "$2"/usr/share/help
    find "$2"/usr/share/ -type d -name doc |xargs rm -rf
    # Remove residual bloat:
    rm -rf "${2}"/usr/doc/*/html
    rm -f "${2}"/usr/doc/*/*.{pdf,db,gz,bz2,xz,txt,TXT}
    # This will remove more bloat but won't touch the license texts:
    find "${2}"/usr/doc/ -type f -size +50k |grep -v /cups- |xargs rm -f
    # Remove info pages:
    rm -rf "$2"/usr/info
  fi
  if [ "$TRIM" = "mandoc" -o "$TRIM" = "waste" -o "$TRIM" = "bloat" ]; then
    # Also remove man pages:
    rm -rf "$2"/usr/man
  fi
  if [ "$TRIM" = "bloat" ]; then
    # By pruning stuff that no one likely needs anyway,
    # we make room for packages we would otherwise not be able to add.
    # We do this only if your ISO needs to be the smallest possible:
    # MySQL embedded is only used by Amarok:
    rm -f "$2"/usr/bin/mysql*embedded*
    # Also remove the big unused/esoteric static libraries:
    rm -f "$2"/usr/lib${DIRSUFFIX}/*.a
    # This was inadvertantly left in the gcc package:
    rm -f "$2"/usr/libexec/gcc/*/*/cc1objplus
    # From samba we mostly want the shared runtime libraries:
    rm -rf "$2"/usr/share/samba
    rm -rf "$2"/usr/lib${DIRSUFFIX}/python*/site-packages/samba
    # Guile library is all we need to satisfy make:
    rm -f "$2"/usr/bin/guil*
    rm -rf "$2"/usr/include/guile
    rm -rf "$2"/usr/lib64/guile
    rm -rf "$2"/usr/share/guile
    # I am against torture:
    rm -f "$2"/usr/bin/smbtorture
    # From llvm we only want the shared runtime libraries so wipe the rest:
    rm -f "$2"/usr/lib${DIRSUFFIX}/lib{LLVM,lldb}*.a
    rm -rf "$2"/usr/lib${DIRSUFFIX}/libclang*
    rm -rf "$2"/usr/include/{c++/v1,clang,clang-c,lldb,llvm,llvm-c}
    rm -rf "$2"/usr/share/{clang,opt-viewer,scan-build,scan-view}
    rm -rf "$2"/usr/lib${DIRSUFFIX}/cmake/{clang,llvm}
    rm -rf "$2"/usr/lib${DIRSUFFIX}/clang
    rm -rf "$2"/usr/lib${DIRSUFFIX}/python*/site-packages/{clang,lldb}
    if [ -e "$2"/var/log/packages/llvm-[0-9]* ]; then
      for BINFILE in $(grep /bin/. "$2"/var/log/packages/llvm-[0-9]*) ; do
         rm -f "$2"/$BINFILE ; 
      done
    fi
    # Bye llvm; on with the rest:
    rm -rf "$2"/usr/lib${DIRSUFFIX}/d3d
    rm -rf "$2"/usr/lib${DIRSUFFIX}/guile
    rm -rf "$2"/usr/share/icons/HighContrast
  fi
  if [ "$TRIM" = "waste" -o "$TRIM" = "bloat" ]; then
    # Get rid of these datacenter NIC firmwares and drivers:
    rm -rf "$2"/lib/firmware/{bnx*,cxgb4,libertas,liquidio,mellanox,netronome,qed}
    rm -rf "$2"/lib/modules/*/kernel/drivers/infiniband
    rm -rf "$2"/lib/modules/*/kernel/drivers/net/ethernet/{broadcom/bnx*,chelsio,mellanox,netronome,qlogic}
    # Old wireless cards that eat space:
    rm -rf "$2"/lib/firmware/mrvl
    rm -rf "$2"/lib/modules/*/kernel/drivers/net/wireless/marvell
    # Qualcomm GPU firmware (Android phone/tablet)
    rm -rf "$2"/lib/firmware/qcom
    # Texas Instruments ARM firmware:
    rm -rf "$2"/lib/firmware/ti-connectivity
    # Mediatek ARM firmware:
    rm -rf "$2"/lib/firmware/mediatek
    rm -rf "$2"/lib/firmware/vpu*.bin
    # Firmware for Data Path Acceleration Architecture NICs:
    rm -rf "$2"/lib/firmware/dpaa2
    # Not needed:
    rm -rf "$2"/boot/System.map*
    # Depends on Qt:
    rm -f "$2"/usr/bin/wpa_gui "$2"/usr/share/applications/wpa_gui.desktop
    # Replace 3.2 MB splash with a symlink to a 33 kB file:
    if [ -e "$2"/usr/share/gimp/2.0/images/gimp-splash.png -a ! -L "$2"/usr/share/gimp/2.0/images/gimp-splash.png ]; then
      rm -rf "$2"/usr/share/gimp/2.0/images/gimp-splash.png
      ln -sf wilber.png "$2"/usr/share/gimp/2.0/images/gimp-splash.png
    fi
    # Replace big watch cursors with simpler ones:
    if [ -e "$2"/usr/share/icons/Adwaita/cursors/watch -a ! -L "$2"/usr/share/icons/Adwaita/cursors/watch ]; then
      rm -rf "$2"/usr/share/icons/Adwaita/cursors/{watch,left_ptr_watch}
      ln -sf left_ptr "$2"/usr/share/icons/Adwaita/cursors/watch
      ln -sf left_ptr "$2"/usr/share/icons/Adwaita/cursors/left_ptr_watch
    fi
    # Remove 9+ MB of brushes:
    rm -rf "$2"/usr/share/gimp/2.0/brushes/Fun
    # Get rid of useless documentation:
    rm -rf "$2"/usr/share/ghostscript/*/doc/
    # We don't need tests or examples:
    find "$2"/usr/ -type d -iname test |xargs rm -rf
    find "$2"/usr/ -type d -iname "example*" |xargs rm -rf
    # Get rid of most of the screensavers:
    KEEPXSCR="julia|xflame|xjack"
    if [ -d "${2}"/usr/libexec/xscreensaver ]; then
      cd "${2}"/usr/libexec/xscreensaver
        find . -type f | grep -Ev "($KEEPXSCR)" |xargs rm -f
      cd - 1>/dev/null
    fi
    if [ "$3" != "local" ] && echo "$(cat ${PKGFILE} |grep -v -E '^ *#|^$' |cut -d: -f1)" |grep -wq glibc ; then
      # Remove unneeded languages from glibc:
      KEEPLANG="$(cat ${LIVE_TOOLDIR}/languages|grep -Ev "(^ *#|^$)"|cut -d: -f5)"
      for LOCALEDIR in /usr/lib${DIRSUFFIX}/locale /usr/share/i18n/locales /usr/share/locale ; do
        if [ -d "${2}"/${LOCALEDIR} ]; then
          cd "${2}"/${LOCALEDIR}
          mkdir ${LIVE_WORK}/.keep
          for KL in C ${KEEPLANG} ; do
            # en_US.utf8 -> en_US*
            mv ${KL%%.utf8}* ${LIVE_WORK}/.keep/ 2>/dev/null
            # en_US.utf8 -> en
            mv ${KL%%_*} ${LIVE_WORK}/.keep/ 2>/dev/null
          done
          rm -rf [A-Za-z]*
          mv ${LIVE_WORK}/.keep/* . 2>/dev/null
          rm -rf ${LIVE_WORK}/.keep
          cd - 1>/dev/null
        fi
      done
    fi
    # Remove big old ICU libraries that are not needed for the XFCE image:
    if [ -e "$2"/var/log/packages/aaa_elflibs-[0-9]* ]; then
      for ICUFILE in $(grep /libicu "$2"/var/log/packages/aaa_elflibs-[0-9]*) ; do
         rm -f "$2"/$ICUFILE ;
      done
    fi
  fi

} # End install_pkgs()


#
# Create the graphical multi-language syslinux boot menu:
#
function gen_bootmenu() {

  MENUROOTDIR="$1/menu"

  # Generate vesamenu structure - many files because of the selection tree.
  mkdir -p ${MENUROOTDIR}

  # Initialize an empty keyboard selection and language menu:
  rm -f ${MENUROOTDIR}/kbd.cfg
  rm -f ${MENUROOTDIR}/lang*.cfg

  # Generate main (EN) vesamenu.cfg:
  cat ${LIVE_TOOLDIR}/menu.tpl | sed \
    -e "s/@KBD@/${DEF_KBD}/g" \
    -e "s/@LANG@/${DEF_LANG}/g" \
    -e "s/@ULANG@/${DEF_LANG^^}/g" \
    -e "s,@LOCALE@,${DEF_LOCALE},g" \
    -e "s,@TZ@,${DEF_TZ},g" \
    -e "s/@CONSFONT@/$CONSFONT/g" \
    -e "s/@DIRSUFFIX@/$DIRSUFFIX/g" \
    -e "s/@DISTRO@/$DISTRO/g" \
    -e "s/@CDISTRO@/${DISTRO^}/g" \
    -e "s/@UDISTRO@/${DISTRO^^}/g" \
    -e "s/@KVER@/$KVER/g" \
    -e "s/@LIVEMAIN@/$LIVEMAIN/g" \
    -e "s/@MEDIALABEL@/$MEDIALABEL/g" \
    -e "s/@LIVEDE@/$(echo $LIVEDE |sed 's/BASE//')/g" \
    -e "s/@SL_VERSION@/$SL_VERSION/g" \
    -e "s/@VERSION@/$VERSION/g" \
    -e "s/@KAPPEND@/$KAPPEND/g" \
    -e "s/@C2RMH@/$C2RMH/g" \
    > ${MENUROOTDIR}/vesamenu.cfg

  for LANCOD in $(cat ${LIVE_TOOLDIR}/languages |grep -Ev "(^ *#|^$)" |cut -d: -f1)
  do
    LANDSC=$(cat ${LIVE_TOOLDIR}/languages |grep "^$LANCOD:" |cut -d: -f2)
    KBD=$(cat ${LIVE_TOOLDIR}/languages |grep "^$LANCOD:" |cut -d: -f3)
    # First, create keytab files if they are missing:
    if [ ! -f ${MENUROOTDIR}/${KBD}.ktl ]; then
      keytab-lilo $(find /usr/share/kbd/keymaps/i386 -name "us.map.gz") $(find /usr/share/kbd/keymaps/i386 -name "${KBD}.map.gz") > ${MENUROOTDIR}/${KBD}.ktl
    fi
    # Add this keyboard to the keyboard selection menu:
    cat <<EOL >> ${MENUROOTDIR}/kbd.cfg
label ${LANCOD}
  menu label ${LANDSC}
EOL
    if [ "${KBD}" == "${DEF_KBD}" ]; then
      echo "  menu default" >> ${MENUROOTDIR}/kbd.cfg
    fi
    cat <<EOL >> ${MENUROOTDIR}/kbd.cfg
  kbdmap menu/${KBD}.ktl
  kernel vesamenu.c32
  append menu/menu_${LANCOD}.cfg

EOL

    # Generate custom vesamenu.cfg for selected keyboard:
    cat ${LIVE_TOOLDIR}/menu.tpl | sed \
      -e "s/@KBD@/$KBD/g" \
      -e "s/@LANG@/$LANCOD/g" \
      -e "s/@ULANG@/${DEF_LANG^^}/g" \
      -e "s,@LOCALE@,${DEF_LOCALE},g" \
      -e "s,@TZ@,${DEF_TZ},g" \
      -e "s/@CONSFONT@/$CONSFONT/g" \
      -e "s/@DIRSUFFIX@/$DIRSUFFIX/g" \
      -e "s/@DISTRO@/$DISTRO/g" \
      -e "s/@CDISTRO@/${DISTRO^}/g" \
      -e "s/@UDISTRO@/${DISTRO^^}/g" \
      -e "s/@KVER@/$KVER/g" \
      -e "s/@LIVEMAIN@/$LIVEMAIN/g" \
      -e "s/@MEDIALABEL@/$MEDIALABEL/g" \
      -e "s/@LIVEDE@/$(echo $LIVEDE |sed 's/BASE//')/g" \
      -e "s/@SL_VERSION@/$SL_VERSION/g" \
      -e "s/@VERSION@/$VERSION/g" \
      -e "s/@KAPPEND@/$KAPPEND/g" \
      -e "s/@C2RMH@/$C2RMH/g" \
      > ${MENUROOTDIR}/menu_${LANCOD}.cfg

    # Generate custom language selection submenu for selected keyboard:
    for SUBCOD in $(cat ${LIVE_TOOLDIR}/languages |grep -Ev "(^ *#|^$)" |cut -d: -f1) ; do
      SUBKBD=$(cat ${LIVE_TOOLDIR}/languages |grep "^$SUBCOD:" |cut -d: -f3)
      cat <<EOL >> ${MENUROOTDIR}/lang_${LANCOD}.cfg
label $(cat ${LIVE_TOOLDIR}/languages |grep "^$SUBCOD:" |cut -d: -f1)
  menu label $(cat ${LIVE_TOOLDIR}/languages |grep "^$SUBCOD:" |cut -d: -f2)
EOL
      if [ "$SUBKBD" = "$KBD" ]; then
        echo "  menu default" >> ${MENUROOTDIR}/lang_${LANCOD}.cfg
      fi
      cat <<EOL >> ${MENUROOTDIR}/lang_${LANCOD}.cfg
  kernel /boot/generic
  append initrd=/boot/initrd.img $KAPPEND load_ramdisk=1 prompt_ramdisk=0 rw printk.time=0 kbd=$KBD tz=$(cat ${LIVE_TOOLDIR}/languages |grep "^$SUBCOD:" |cut -d: -f4) locale=$(cat ${LIVE_TOOLDIR}/languages |grep "^$SUBCOD:" |cut -d: -f5) xkb=$(cat ${LIVE_TOOLDIR}/languages |grep "^$SUBCOD:" |cut -d: -f6)

EOL
    done

  done

} # End of gen_bootmenu()

#
# Create the grub menu file for UEFI boot:
#
function gen_uefimenu() {

  GRUBDIR="$1"

  # Generate the grub menu structure - many files because of the selection tree.
  # I expect the directory to exist... but you never know.
  mkdir -p ${GRUBDIR}

  # Initialize an empty keyboard, language and timezone selection menu:
  rm -f ${GRUBDIR}/kbd.cfg
  rm -f ${GRUBDIR}/lang.cfg
  rm -f ${GRUBDIR}/tz.cfg

  # Generate main grub.cfg:
  cat ${LIVE_TOOLDIR}/grub.tpl | sed \
    -e "s/@KBD@/${DEF_KBD}/g" \
    -e "s,@TZ@,${DEF_TZ},g" \
    -e "s/@LANG@/${DEF_LANG}/g" \
    -e "s/@ULANG@/${DEF_LANG^^}/g" \
    -e "s/@LANDSC@/${DEF_LANDSC}/g" \
    -e "s/@LOCALE@/${DEF_LOCALE}/g" \
    -e "s/@CONSFONT@/$CONSFONT/g" \
    -e "s/@DIRSUFFIX@/$DIRSUFFIX/g" \
    -e "s/@DISTRO@/$DISTRO/g" \
    -e "s/@CDISTRO@/${DISTRO^}/g" \
    -e "s/@UDISTRO@/${DISTRO^^}/g" \
    -e "s/@KVER@/$KVER/g" \
    -e "s/@LIVEMAIN@/$LIVEMAIN/g" \
    -e "s/@MEDIALABEL@/$MEDIALABEL/g" \
    -e "s/@LIVEDE@/$(echo $LIVEDE |sed 's/BASE//')/g" \
    -e "s/@SL_VERSION@/$SL_VERSION/g" \
    -e "s/@VERSION@/$VERSION/g" \
    -e "s/@KAPPEND@/$KAPPEND/g" \
    -e "s/@C2RMH@/$C2RMH/g" \
    > ${GRUBDIR}/grub.cfg

  # Set a default keyboard selection:
  cat <<EOL > ${GRUBDIR}/kbd.cfg
# Keyboard selection:
set default = $sl_lang

EOL

  # Set a default language selection:
  cat <<EOL > ${GRUBDIR}/lang.cfg
# Language selection:
set default = $sl_lang

EOL

  # Create the remainder of the selection menus:
  for LANCOD in $(cat languages |grep -Ev "(^ *#|^$)" |cut -d: -f1) ; do
    LANDSC=$(cat languages |grep "^$LANCOD:" |cut -d: -f2)
    KBD=$(cat languages |grep "^$LANCOD:" |cut -d: -f3)
    XKB=$(cat languages |grep "^$LANCOD:" |cut -d: -f6)
    LANLOC=$(cat languages |grep "^$LANCOD:" |cut -d: -f5)
    # Add this entry to the keyboard selection menu:
    cat <<EOL >> ${GRUBDIR}/kbd.cfg
menuentry "${LANDSC}" {
  set sl_kbd="$KBD"
  set sl_xkb="$XKB"
  set sl_lang="$LANDSC"
  export sl_kbd
  export sl_xkb
  export sl_lang
  configfile \$prefix/grub.cfg
}

EOL

    # Add this entry to the language selection menu:
    cat <<EOL >> ${GRUBDIR}/lang.cfg
menuentry "${LANDSC}" {
  set sl_locale="$LANLOC"
  set sl_lang="$LANDSC"
  export sl_locale
  export sl_lang
  configfile \$prefix/grub.cfg
}

EOL

  done

  # Create the timezone selection menu:
  TZDIR="/usr/share/zoneinfo"
  TZLIST=$(mktemp -t alientz.XXXXXX)
  if [ ! -f $TZLIST ]; then
    echo "*** Failed to create a temporary file!"
    cleanup
    exit 1
  fi
  # First, create a list of timezones:
  # This code taken from Slackware script:
  # source/a/glibc-zoneinfo/timezone-scripts/output-updated-timeconfig.sh
  # Author: Patrick Volkerding <volkerdi@slackware.com>
  # US/ first:
  ( cd $TZDIR
    find . -type f | xargs file | grep "timezone data" | cut -f 1 -d : | cut -f 2- -d / | sort | grep "^US/" | while read zone ; do
      echo "${zone}" >> $TZLIST
    done
  )
  # Don't list right/ and posix/ zones:
  ( cd $TZDIR
    find . -type f | xargs file | grep "timezone data" | cut -f 1 -d : | cut -f 2- -d / | sort | grep -v "^US/" | grep -v "^posix/" | grep -v "^right/" | while read zone ; do
      echo "${zone}" >> $TZLIST
    done
  )
  for TZ in $(cat $TZLIST); do
    # Add this entry to the keyboard selection menu:
    cat <<EOL >> ${GRUBDIR}/tz.cfg
menuentry "${TZ}" {
  set sl_tz="$TZ"
  export sl_tz
  configfile \$prefix/grub.cfg
}

EOL
  rm -f $TZLIST

  done

} # End of gen_uefimenu()


#
# Add UEFI SecureBoot support:
#
function secureboot() {
  # Liveslak uses Fedora's shim (for now), which is signed by
  # 'Microsoft UEFI CA' and contains Fedora's CA certificate.
  # We sign liveslak's grub and kernel with our own key/certificate pair.
  # This means that the user of liveslak will have to enroll liveslak's
  # public certificate via MokManager. This needs to be done only once.

  # Note that we use the generic fallback directory /EFI/BOOT/ for the Live ISO
  # instead of a custom distro entry for UEFI such as /EFI/BOOT/Slackware/
  # When shim is booted with  path /EFI/BOOT/bootx64.efi, and there is a
  # Fallback binary (fbx64.efi) , shim will load that one instead of grub,
  # so Fallback can create a NVRAM boot entry for a custom distro directory
  # (which we do not have) causing a reset boot loop.
  # This is why liveslak does not install fbx64.efi. A regular distro should
  # install that file in its distro subdirectory!

  SHIM_VENDOR="$1"
  [ -z "${SHIM_VENDOR}" ] && SHIM_VENDOR="fedora"

  case $SHIM_VENDOR in
    opensuse)      GRUB_SIGNED="grub.efi"
                   ;;
    *)             GRUB_SIGNED="grubx64.efi"
                   ;;
  esac
  mkdir -p ${LIVE_WORK}/shim
  cd ${LIVE_WORK}/shim

  echo "-- Signing grub+kernel with '${LIVE_STAGING}/EFI/BOOT/liveslak.pem'."
  # Sign grub:
  # The Grub EFI image must be renamed appropriately for shim to find it,
  # since some distros change the default 'grubx64.efi' filename:
  mv -i ${LIVE_STAGING}/EFI/BOOT/bootx64.efi \
    ${LIVE_WORK}/shim/grubx64.efi.unsigned
  sbsign --key ${MOKPRIVKEY} --cert ${MOKCERT} \
    --output ${LIVE_STAGING}/EFI/BOOT/${GRUB_SIGNED} \
    ${LIVE_WORK}/shim/grubx64.efi.unsigned 
  # Sign the kernel:
  mv ${LIVE_STAGING}/boot/generic ${LIVE_WORK}/shim/generic.unsigned 
  sbsign --key ${MOKPRIVKEY} --cert ${MOKCERT} \
    --output ${LIVE_STAGING}/boot/generic \
    ${LIVE_WORK}/shim/generic.unsigned 

  if [ "${SHIM_VENDOR}" = "fedora" ]; then
    # The version of Fedora's shim package - always use the latest!
    SHIM_MAJVER=15.4
    SHIM_MINVER=5
    SHIMSRC="https://kojipkgs.fedoraproject.org/packages/shim/${SHIM_MAJVER}/${SHIM_MINVER}/x86_64/shim-x64-${SHIM_MAJVER}-${SHIM_MINVER}.x86_64.rpm"
    echo "-- Downloading/installing the SecureBoot signed shim from Fedora."
    wget -q --progress=dot:mega --show-progress ${SHIMSRC} -O - \
      | rpm2cpio - | cpio -dim
    echo ""
    # Install signed efi files into UEFI BOOT directory of the esp partition:
    # The name of the shim in the ISO, *must* be 'bootx64.efi':
    install -D -m0644 boot/efi/EFI/fedora/shimx64.efi \
      ${LIVE_STAGING}/EFI/BOOT/bootx64.efi
    install -D -m0644 boot/efi/EFI/fedora/mmx64.efi \
      ${LIVE_STAGING}/EFI/BOOT/mmx64.efi
    #install -D -m0644 boot/efi/EFI/BOOT/fbx64.efi \
    #  ${LIVE_STAGING}/EFI/BOOT/fbx64.efi
  elif [ "${SHIM_VENDOR}" = "opensuse" ]; then
    SHIM_MAJVER=15.4
    SHIM_MINVER=4.2
    SHIMSRC="https://download.opensuse.org/repositories/openSUSE:/Factory/standard/x86_64/shim-${SHIM_MAJVER}-${SHIM_MINVER}.x86_64.rpm"
    echo "-- Downloading/installing the SecureBoot signed shim from openSUSE."
    wget -q --progress=dot:mega --show-progress ${SHIMSRC} -O - \
      | rpm2cpio - | cpio -dim
    echo ""
    # Install signed efi files into UEFI BOOT directory of the esp partition:
    # The name of the shim in the ISO, *must* be 'bootx64.efi':
    install -D -m0644 usr/share/efi/x86_64/shim-opensuse.efi \
      ${LIVE_STAGING}/EFI/BOOT/bootx64.efi
    install -D -m0644 usr/share/efi/x86_64/MokManager.efi \
      ${LIVE_STAGING}/EFI/BOOT/MokManager.efi
    #install -D -m0644 usr/share/efi/x86_64/fallback.efi \
    #  ${LIVE_STAGING}/EFI/BOOT/fallback.efi
  elif [ "${SHIM_VENDOR}" = "debian" ]; then
    DEBSHIM_VER=1.38
    DEBMOKM_VER=1
    SHIM_MAJVER=15.4
    SHIM_MINVER=7
    SHIMSRC="http://ftp.de.debian.org/debian/pool/main/s/shim-signed/shim-signed_${DEBSHIM_VER}+${SHIM_MAJVER}-${SHIM_MINVER}_amd64.deb"
    MOKMSRC="http://ftp.de.debian.org/debian/pool/main/s/shim-helpers-amd64-signed/shim-helpers-amd64-signed_${DEBMOKM_VER}+${SHIM_MAJVER}+${SHIM_MINVER}_amd64.deb"
    echo "-- Downloading the SecureBoot signed shim from Debian."
    wget -q --progress=dot:mega --show-progress ${SHIMSRC}
    echo ""
    echo "-- Installing the SecureBoot signed shim to the ESP."
    # Extract discarding any directory structure:
    ar p $(basename ${SHIMSRC}) data.tar.xz | tar --xform='s#^.+/##x' -Jxf - \
      ./usr/lib/shim/shimx64.efi.signed
    echo "-- Downloading the SecureBoot signed mokmanager from Debian."
    wget -q  --progress=dot:mega --show-progress ${MOKMSRC}
    echo ""
    echo "-- Installing the SecureBoot signed mokmanager to the ESP."
    # Extract discarding any directory structure:
    ar p $(basename ${MOKMSRC}) data.tar.xz | tar --xform='s#^.+/##x' -Jxf - \
      ./usr/lib/shim/fbx64.efi.signed ./usr/lib/shim/mmx64.efi.signed
    # Install signed efi files into UEFI BOOT directory of the esp partition:
    # The name of the shim in the ISO, *must* be 'bootx64.efi':
    install -D -m0644 ./shimx64.efi.signed \
      ${LIVE_STAGING}/EFI/BOOT/bootx64.efi
    install -D -m0644 ./mmx64.efi.signed \
      ${LIVE_STAGING}/EFI/BOOT/mmx64.efi
    #install -D -m0644 ./fbx64.efi.signed \
    #  ${LIVE_STAGING}/EFI/BOOT/fbx64.efi
  else
    echo ">> A '${SHIM_VENDOR}' shim was requested, but only 'opensuse' 'fedora' or 'debian' shim/mokmanager are supported."
    echo ">> Expect trouble ahead."
  fi
  cd - 1>/dev/null

  ## Write CSV file for the Fallback EFI program so that it knows what to boot:
  #echo -n "bootx64.efi,SHIM,,SecureBoot UEFI entry for liveslak" \
  #  | iconv -t UCS-2 > ${LIVE_STAGING}/EFI/BOOT/BOOT.CSV

  # Cleanup:
  rm -rf ${LIVE_WORK}/shim

} # End of secureboot()

#
# Create an ISO file from a directory's content:
#
function create_iso() {
  TOPDIR=${1:-"${LIVE_STAGING}"}

  cd "$TOPDIR"

  # Tag the type of live environment to the ISO filename:
  if [ "$LIVEDE" = "SLACKWARE" ]; then
    ISOTAG=""
  else
    ISOTAG="-$(echo $LIVEDE |tr A-Z a-z)"
  fi

  # Determine whether we add UEFI boot capabilities to the ISO:
  if [ -f boot/syslinux/efiboot.img -a "$USEXORR" = "NO" ]; then
    UEFI_OPTS="-eltorito-alt-boot -no-emul-boot -eltorito-platform 0xEF -eltorito-boot boot/syslinux/efiboot.img"
  elif [ -f boot/syslinux/efiboot.img -a "$USEXORR" = "YES" ]; then
    UEFI_OPTS="-eltorito-alt-boot -e boot/syslinux/efiboot.img -no-emul-boot"
  else
    UEFI_OPTS=""
  fi

  # Time to determine the output filename, now that we know all the variables
  # and ensured that the OUTPUT directory exists:
  OUTFILE=${OUTFILE:-"${OUTPUT}/${DISTRO}${DIRSUFFIX}-live${ISOTAG}-${SL_VERSION}.iso"}
  if [ "$USEXORR" = "NO" ]; then
    mkisofs -o "${OUTFILE}" \
      -V "${MEDIALABEL}" \
      -R -J \
      -hide-rr-moved \
      -v -d -N \
      -no-emul-boot -boot-load-size ${BOOTLOADSIZE} -boot-info-table \
      -sort boot/syslinux/iso.sort \
      -b boot/syslinux/isolinux.bin \
      -c boot/syslinux/isolinux.boot \
      ${UEFI_OPTS} \
      -preparer "$(echo $LIVEDE |sed 's/BASE//') Live built by ${BUILDER}" \
      -publisher "The Slackware Linux Project - http://www.slackware.com/" \
      -A "${DISTRO^}-${SL_VERSION} for ${SL_ARCH} ($(echo $LIVEDE |sed 's/BASE//') Live $VERSION)" \
      -x ./$(basename ${LIVE_WORK}) \
      -x ./${LIVEMAIN}/bootinst \
      -x boot/syslinux/testing \
      .

    if [ "$SL_ARCH" = "x86_64" -o "$EFI32" = "YES" ]; then
      # Make this a hybrid ISO with UEFI boot support on x86_64.
      # On 32bit, the variable EFI32 must be explicitly enabled.
      isohybrid -u "${OUTFILE}"
    else
      isohybrid "${OUTFILE}"
    fi # End UEFI hybrid ISO.
  else
    echo "-- Using xorriso to generate the ISO and make it hybrid."
    xorriso -as mkisofs -o "${OUTFILE}" \
      -V "${MEDIALABEL}" \
      -J -joliet-long -r \
      -hide-rr-moved \
      -v -d -N \
      -b boot/syslinux/isolinux.bin \
      -c boot/syslinux/isolinux.boot \
      -boot-load-size ${BOOTLOADSIZE} -boot-info-table -no-emul-boot \
      ${UEFI_OPTS} \
      -isohybrid-mbr /usr/share/syslinux/isohdpfx.bin \
      -isohybrid-gpt-basdat \
      -preparer "$(echo $LIVEDE |sed 's/BASE//') Live built by ${BUILDER}" \
      -publisher "The Slackware Linux Project - http://www.slackware.com/" \
      -A "${DISTRO^}-${SL_VERSION} for ${SL_ARCH} ($(echo $LIVEDE |sed 's/BASE//') Live $VERSION)" \
      -x ./$(basename ${LIVE_WORK}) \
      -x ./${LIVEMAIN}/bootinst \
      -x boot/syslinux/testing \
      .
  fi

  # Return to original directory:
  cd - 1>/dev/null

  cd "${OUTPUT}"
    md5sum "$(basename "${OUTFILE}")" \
      > "$(basename "${OUTFILE}")".md5
  cd - 1>/dev/null
  echo "-- Live ISO image created:"
  echo "   - CDROM max size is 737.280.000 bytes (703 MB)"
  echo "   - DVD max size is 4.706.074.624 bytes (4.38 GB aka 4.7 GiB)"
  ls -l "${OUTFILE}"*

} # End of create_iso()

#
# Configure a custom background image in Plasma5:
#
function plasma5_custom_bg() {
  # The function expects a background image file of JPG or PNG format.
  # The bitmap must be present in the liveslak source tree as:
  # media/<variant>/bg/background.png or media/<variant>/bg/background.jpg ,
  # where <variant> is the lowercase name of the liveslak variant (such as
  # cinnamon, daw, slackware, etc).
  # The file background.{jpg,png} can be a symlink to an actual JPG or PNG.
  # Aspect ratio of the image *must* be 16:9 (1920x1080 px or higher res).

  # Exit immediately if the image file is not found:
  if ! readlink -f ${LIVE_TOOLDIR}/media/${LIVEDE,,}/bg/background.* 1>/dev/null 2>&1 ; then
    echo "-- No ${LIVEDE} custom wallpaper image."
    return
  fi

  echo "-- Configuring ${LIVEDE} custom background image."
  # First convert our image into a JPG in the liveslak directory:
  mkdir -p ${LIVE_ROOTDIR}/usr/share/${LIVEMAIN}/${LIVEDE,,}
  convert ${LIVE_TOOLDIR}/media/${LIVEDE,,}/bg/background.* ${LIVE_ROOTDIR}/usr/share/${LIVEMAIN}/${LIVEDE,,}/background.jpg

  # Create a Plasma5 desktop wallpaper set with a lowercase LIVEDE name:
  mkdir -p ${LIVE_ROOTDIR}/usr/share/wallpapers/${LIVEDE,,}/contents/images

  # Create set of images for common aspect ratios like 16:9, 16:10 and 4:3:
  # Aspect Ratio 16:9 :
  convert ${LIVE_ROOTDIR}/usr/share/${LIVEMAIN}/${LIVEDE,,}/background.jpg \
    -resize 1920x1080 \
    ${LIVE_ROOTDIR}/usr/share/wallpapers/${LIVEDE,,}/contents/images/1920x1080.jpg
  convert ${LIVE_ROOTDIR}/usr/share/${LIVEMAIN}/${LIVEDE,,}/background.jpg \
    -resize 5120x2880 \
    ${LIVE_ROOTDIR}/usr/share/wallpapers/${LIVEDE,,}/contents/images/5120x2880.jpg
  # Aspect Ratio 16:10 :
  convert  ${LIVE_ROOTDIR}/usr/share/${LIVEMAIN}/${LIVEDE,,}/background.jpg \
    -resize 5120x - | \
    convert - -geometry 1920x1200^ -gravity center -crop 1920x1200+0+0 \
    ${LIVE_ROOTDIR}/usr/share/wallpapers/${LIVEDE,,}/contents/images/1920x1200.jpg
  convert  ${LIVE_ROOTDIR}/usr/share/${LIVEMAIN}/${LIVEDE,,}/background.jpg \
    -resize 5120x - | \
    convert - -geometry 1280x800^ -gravity center -crop 1280x800+0+0 \
    ${LIVE_ROOTDIR}/usr/share/wallpapers/${LIVEDE,,}/contents/images/1280x800.jpg
  # Aspect Ratio 4:3 :
  convert  ${LIVE_ROOTDIR}/usr/share/${LIVEMAIN}/${LIVEDE,,}/background.jpg \
    -resize 5120x - | \
    convert - -geometry 1024x768^ -gravity center -crop 1024x768+0+0 \
    ${LIVE_ROOTDIR}/usr/share/wallpapers/${LIVEDE,,}/contents/images/1024x768.jpg

  # Create the required wallpaper screenshot of 400x225 px (16:9 aspect ratio):
  convert ${LIVE_ROOTDIR}/usr/share/${LIVEMAIN}/${LIVEDE,,}/background.jpg \
    -resize 400x225 \
    ${LIVE_ROOTDIR}/usr/share/wallpapers/${LIVEDE,,}/contents/screenshot.png

  # Add wallpaper description:
  cat <<EOT >${LIVE_ROOTDIR}/usr/share/wallpapers/${LIVEDE,,}/metadata.desktop
[Desktop Entry]
Name=${DISTRO^} Live

X-KDE-PluginInfo-Name=${LIVEDE,,}
X-KDE-PluginInfo-Author=Eric Hameleers
X-KDE-PluginInfo-Email=alien@slackware.com
X-KDE-PluginInfo-License=CC-BY-SA-4.0
EOT

  # Now set our wallpaper to be the default. For this to work, we need to link
  # the name of the default theme to ours, so find out what the default is:
  if [ -f "${LIVE_ROOTDIR}/usr/share/plasma/desktoptheme/default/metadata.desktop" ]; then
    # Frameworks before 5.94.0:
    THEMEFIL=/usr/share/plasma/desktoptheme/default/metadata.deskop
  else
    # Frameworks 5.94.0 and newer:
    THEMEFIL=/usr/share/plasma/desktoptheme/default/plasmarc
  fi
  DEF_THEME="$(grep ^defaultWallpaperTheme ${LIVE_ROOTDIR}/${THEMEFIL} |cut -d= -f2-)"
  mv ${LIVE_ROOTDIR}/usr/share/wallpapers/${DEF_THEME}{,.orig}
  ln -s ${LIVEDE,,} ${LIVE_ROOTDIR}/usr/share/wallpapers/${DEF_THEME}

  # Custom background for the SDDM login greeter:
  mkdir -p ${LIVE_ROOTDIR}/usr/share/sddm/themes/breeze
  cp ${LIVE_ROOTDIR}/usr/share/${LIVEMAIN}/${LIVEDE,,}/background.jpg ${LIVE_ROOTDIR}/usr/share/sddm/themes/breeze/${LIVEDE,,}_background.jpg
  cat <<EOT > ${LIVE_ROOTDIR}/usr/share/sddm/themes/breeze/theme.conf.user
[General]
background=${LIVEDE,,}_background.jpg
EOT

  # Screenlocker:
  mkdir -p ${LIVE_ROOTDIR}/home/${LIVEUID}/.config
cat <<EOT > ${LIVE_ROOTDIR}/home/${LIVEUID}/.config/kscreenlockerrc 
[$Version]
update_info=kscreenlocker.upd:0.1-autolock

[Greeter]
WallpaperPlugin=org.kde.image
[Greeter][Wallpaper][org.kde.image][General]
FillMode=2
Image=file:///usr/share/${LIVEMAIN}/${LIVEDE,,}/background.jpg
EOT

} # End of plasma5_custom_bg()

# ---------------------------------------------------------------------------
# Action!
# ---------------------------------------------------------------------------

while getopts "a:c:d:efhl:m:r:s:t:vz:CGH:MO:R:S:X" Option
do
  case $Option in
    h )
        echo "----------------------------------------------------------------"
        echo "make_slackware_live.sh $VERSION"
        echo "----------------------------------------------------------------"
        echo "Usage:"
        echo "  $0 [OPTION] ..."
        echo "or:"
        echo "  SL_REPO=/your/repository/dir $0 [OPTION] ..."
        echo ""
        echo "The SL_REPO is the directory that contains the directory"
        echo "  ${DISTRO}-<RELEASE> or ${DISTRO}64-<RELEASE>"
        echo "Current value of SL_REPO : $SL_REPO"
        echo ""
        echo "The script's parameters are:"
        echo " -h                 This help."
        echo " -a arch            Machine architecture (default: ${SL_ARCH})."
        echo "                    Use i586 for a 32bit ISO, x86_64 for 64bit."
        echo " -c comp            Squashfs compression (default: ${SQ_COMP})."
        echo "                    Can be any of '${SQ_COMP_AVAIL}'."
        echo " -d desktoptype     SLACKWARE (full Slack),XFCE basic, LEAN, DAW,"
        echo "                    KTOWN, MATE, CINNAMON, DLACK, STUDIOWARE."
        echo " -e                 Use ISO boot-load-size of 32 for computers."
        echo "                    where the ISO won't boot otherwise."
        echo " -f                 Forced re-generation of all squashfs modules,"
        echo "                    custom configurations and new initrd.img."
        echo " -l <localization>  Enable a different default localization"
        echo "                    (script-default is '${DEF_LANG}')."
        echo " -m pkglst[,pkglst] Add modules defined by pkglists/<pkglst>,..."
        echo " -r series[,series] Refresh only one or a few package series."
        echo " -s slackrepo_dir   Directory containing ${DISTRO^} repository."
        echo " -t <none|doc|mandoc|waste|bloat>"
        echo "                    Trim the ISO (remove man and/or doc and/or bloat)."
        echo " -v                 Show debug/error output."
        echo " -z version         Define your ${DISTRO^} version (default: $SL_VERSION)."
        echo " -C                 Add RAM-based Console OS to boot menu."
        echo " -G                 Generate ISO file from existing directory tree"
        echo " -H hostname        Hostname of the Live OS (default: $LIVE_HOSTNAME)."
        echo " -M                 Add multilib (x86_64 only)."
        echo " -O outfile         Custom filename for the ISO."
        echo " -R runlevel        Runlevel to boot into (default: $RUNLEVEL)."
        echo " -S privkey:cert    Enable SecureBoot support and sign binaries"
        echo "                    using the full path to colon-separated"
        echo "                    private key and certificate files"
        echo " -X                 Use xorriso instead of mkisofs/isohybrid."
        exit
        ;;
    a ) SL_ARCH="${OPTARG}"
        ;;
    c ) SQ_COMP="${OPTARG}"
        ;;
    d ) LIVEDE="$(echo ${OPTARG} |tr a-z A-Z)"
        ;;
    e ) BOOTLOADSIZE=32
        ;;
    f ) FORCE="YES"
        ;;
    l ) DEF_LANG="${OPTARG}"
        ;;
    m ) SEQ_ADDMOD="${OPTARG}"
        ;;
    r ) REFRESH="${OPTARG}"
        ;;
    s ) SL_REPO="${OPTARG}"
        DEF_SL_REPO="${SL_REPO}"
        ;;
    t ) TRIM="${OPTARG}"
        ;;
    v ) DEBUG="YES"
        ;;
    z ) SL_VERSION="${OPTARG}"
        ;;
    C ) CORE2RAM="YES"
        ;;
    G ) ONLY_ISO="YES"
        ;;
    H ) LIVE_HOSTNAME="${OPTARG}"
        ;;
    M ) MULTILIB="YES"
        ;;
    O ) OUTFILE="${OPTARG}"
        OUTPUT="$(cd $(dirname "${OUTFILE}"); pwd)"
        ;;
    R ) RUNLEVEL=${OPTARG}
        ;;
    S ) MOKPRIVKEY=$(readlink -f $(echo ${OPTARG} |cut -d: -f1))
        MOKCERT=$(readlink -f $(echo ${OPTARG} |cut -d: -f2))
        TEMP_3RDP=$(echo ${OPTARG} |cut -d: -f3)
        [ -n "${TEMP_3RDP}" ] && SHIM_3RDP=${TEMP_3RDP}
        unset TEMP_3RDP
        ;;
    X ) USEXORR="YES"
        ;;
    * ) echo "You passed an illegal switch to the program!"
        echo "Run '$0 -h' for more help."
        exit
        ;;   # DEFAULT
  esac
done

# End of option parsing.
shift $(($OPTIND - 1))

#  $1 now references the first non option item supplied on the command line
#  if one exists.
# ---------------------------------------------------------------------------

[ "$DEBUG" = "NO" ] && DBGOUT="/dev/null" || DBGOUT="/dev/stderr"

# -----------------------------------------------------------------------------
# Some sanity checks first.
# -----------------------------------------------------------------------------

if [ -n "$REFRESH" -a "$FORCE" = "YES" ]; then
  echo ">> Please use only _one_ of the switches '-f' or '-r'!"
  echo ">> Run '$0 -h' for more help."
  exit 1
fi

if [ "$ONLY_ISO" = "YES" -a "$FORCE" = "YES" ]; then
  echo ">> Please use only _one_ of the switches '-f' or '-G'!"
  echo ">> Run '$0 -h' for more help."
  exit 1
fi

if [ $RUNLEVEL -ne 3 -a $RUNLEVEL -ne 4 ]; then
  echo ">> Default runlevel other than 3 or 4 is not supported."
  exit 1
fi

if [ "$SL_ARCH" != "x86_64" -a "$MULTILIB" = "YES" ]; then
  echo ">> Multilib is only supported on x86_64 architecture."
  exit 1
fi

if [ -n "${MOKPRIVKEY}" ] && [ -n "${MOKCERT}" ]; then
  if [ -f ${MOKPRIVKEY} ] && [ -f ${MOKCERT} ]; then
    echo "-- Enabling SecureBoot support (${SHIM_3RDP} shim)."
    SECUREBOOT=1
  else
    echo ">> SecureBoot can not be enabled; MOK key and/or cert not found."
    exit 1
  fi
fi

# Determine which module sequence we have to build:
case "$LIVEDE" in
  SLACKWARE) MSEQ="${SEQ_SLACKWARE}" ;;
       XFCE) MSEQ="${SEQ_XFCEBASE}" ;;
       LEAN) MSEQ="${SEQ_LEAN}" ;;
        DAW) MSEQ="${SEQ_DAW}" ;;
      KTOWN) MSEQ="${SEQ_KTOWN}" ;;
       MATE) MSEQ="${SEQ_MSB}" ;;
   CINNAMON) MSEQ="${SEQ_CIN}" ;;
      DLACK) MSEQ="${SEQ_DLACK}" ;;
 STUDIOWARE) MSEQ="${SEQ_STUDW}" ;;
          *) if [ -n "${SEQ_CUSTOM}" ]; then
               # Custom distribution with a predefined package list:
               MSEQ="${SEQ_CUSTOM}"              
             else
               echo "** Unsupported configuration '$LIVEDE'"; exit 1
             fi
             ;;
esac

if [ "${CORE2RAM}" == "YES" ] || [ "${LIVEDE}" == "XFCE" ] || [ "${LIVEDE}" == "LEAN" ] || [ "${LIVEDE}" == "DAW" ] ; then
  # For now, allow CORE2RAM only for the variants that actually
  # have the required modules in their system list.
  # TODO: create these modules separately in the 'core2ram' subdirectory. 
  for MY_MOD in ${CORE2RAMMODS} ; do
    if ! echo ${MSEQ} | grep -wq ${MY_MOD} ; then
      echo ">> Modules required for Core RAM-based OS (${CORE2RAMMODS}) not available."
      exit 1
    fi
  done
  # Whether to hide the Core OS menu on boot yes or no:
  C2RMH="#"
else
  C2RMH=""
fi

if ! cat ${LIVE_TOOLDIR}/languages |grep -Ev '(^ *#|^$)' |grep -q ^${DEF_LANG}:
then
  echo ">> Unsupported language '${DEF_LANG}', select a supported language:"
  echo ">> $(cat ${LIVE_TOOLDIR}/languages |grep -Ev '(^ *#|^$)' |cut -d: -f1)."
  exit 1
else
  # Default locale, timezone and keyboard layout based on language choice:
  DEF_LANDSC="$(cat ${LIVE_TOOLDIR}/languages |grep ^${DEF_LANG}: |cut -d: -f2)"
  DEF_KBD="$(cat ${LIVE_TOOLDIR}/languages |grep ^${DEF_LANG}: |cut -d: -f3)"
  DEF_TZ="$(cat ${LIVE_TOOLDIR}/languages |grep ^${DEF_LANG}: |cut -d: -f4)"
  DEF_LOCALE="$(cat ${LIVE_TOOLDIR}/languages |grep ^${DEF_LANG}: |cut -d: -f5)"
  # Select sane defaults in case the language file lacks info:
  DEF_LANDSC="${DEF_LANDSC:-'us american'}"
  DEF_KBD="${DEF_KBD:-'us'}"
  DEF_TZ="${DEF_TZ:-'UTC'}"
  DEF_LOCALE="${DEF_LOCALE:-'en_US.utf8'}"
fi

# Directory suffix, arch dependent:
if [ "$SL_ARCH" = "x86_64" ]; then
  DIRSUFFIX="64"
  EFIFORM="x86_64"
  EFISUFF="x64"
else
  DIRSUFFIX=""
  EFIFORM="i386"
  EFISUFF="ia32"
fi

# Package root directory, arch dependent:
SL_PKGROOT=${SL_REPO}/${DISTRO}${DIRSUFFIX}-${SL_VERSION}/${DISTRO}${DIRSUFFIX}
DEF_SL_PKGROOT=${SL_PKGROOT}

# Patches root directory, arch dependent:
SL_PATCHROOT=${SL_REPO}/${DISTRO}${DIRSUFFIX}-${SL_VERSION}/patches/packages
DEF_SL_PATCHROOT=${SL_PATCHROOT}

# Are all the required add-on tools present?
[ "$USEXORR" = "NO" ] && ISOGEN="mkisofs isohybrid" || ISOGEN="xorriso"
PROG_MISSING=""
REQTOOLS="mksquashfs unsquashfs grub-mkfont grub-mkimage syslinux $ISOGEN installpkg upgradepkg keytab-lilo rsync wget mkdosfs"
if [ $SECUREBOOT -eq 1 ]; then
   REQTOOLS="${REQTOOLS} openssl sbsign"
fi
for PROGN in ${REQTOOLS} ; do
  if ! which $PROGN 1>/dev/null 2>/dev/null ; then
    PROG_MISSING="${PROG_MISSING}--   $PROGN\n"
  fi
done
if [ ! -z "$PROG_MISSING" ] ; then
  echo "-- Required program(s) not found in PATH!"
  echo -e ${PROG_MISSING}
  echo "-- Exiting."
  exit 1
fi

# Test whether the compressor of choice is supported by the script:
if ! echo ${SQ_COMP_AVAIL} | grep -wq ${SQ_COMP} ; then
  echo "-- Compressor '${SQ_COMP}' not supported by liveslak!"
  echo "-- Select one of '${SQ_COMP_AVAIL}'"
  exit 1
else
  # Test whether the local squashfs-tools support the compressor:
  if ! mksquashfs 2>&1 | grep -Ewq "^[[:space:]]*${SQ_COMP}" ; then
    echo "-- Compressor '${SQ_COMP}' not supported by your 'mksquashfs'!"
    echo "-- Select another one from '${SQ_COMP_AVAIL}'"
    exit 1
  fi
fi
 
# What compression parameters to use?
# For our lean XFCE image we try to achieve max compression,
# at the expense of runtime latency:
if [ "$LIVEDE" = "XFCE" ] ; then
  SQ_COMP_PARAMS=${SQ_COMP_PARAMS:-"${SQ_COMP_PARAMS_OPT[${SQ_COMP}]}"}
else
  SQ_COMP_PARAMS=${SQ_COMP_PARAMS:-"${SQ_COMP_PARAMS_DEF[${SQ_COMP}]}"}
fi

# Check rsync progress report capability:
if [ -z "$(rsync  --info=progress2 2>&1 |grep "unknown option")" ]; then
  # Use recent rsync to display some progress:
  RSYNCREP="--no-inc-recursive --info=progress2"
else
  # Remain silent if we have an older rsync:
  RSYNCREP=" "
fi

# What to trim from the ISO file (none, doc, mandoc, waste, bloat):
if [ "${LIVEDE}" == "XFCE" ] ; then
  TRIM=${TRIM:-"waste"}
elif [ "${LIVEDE}" == "LEAN" ] ; then
  TRIM=${TRIM:-"doc"}
else
  TRIM=${TRIM:-"none"}
fi

# Determine possible blacklist to use:
if [ -z "${BLACKLIST}" ]; then
  eval BLACKLIST=\$BLACKLIST_${LIVEDE}
fi

# Determine possible package list from 'testing' to use:
if [ -z "${TESTINGLIST}" ]; then
  eval TESTINGLIST=\$TESTINGLIST_${LIVEDE}
fi

# Create output directory for image file:
mkdir -p "${OUTPUT}"
if [ $? -ne 0 ]; then
  echo "-- Creation of output directory '${OUTPUT}' failed! Exiting."
  exit 1
fi

# If so requested, we generate the ISO image and immediately exit.
if [ "$ONLY_ISO" = "YES" -a -n "${LIVE_STAGING}" ]; then
  create_iso ${LIVE_STAGING}
  cleanup
  exit 0
else
  # Remove ./boot - it will be created from scratch later:
  rm -rf ${LIVE_STAGING}/boot
fi

# Cleanup if we are FORCEd to rebuild from scratch:
if [ "$FORCE" = "YES" ]; then
  echo "-- Removing old files and directories!"
  umount ${LIVE_ROOTDIR}/{proc,sys,dev} 2>${DBGOUT} || true
  umount ${LIVE_ROOTDIR} 2>${DBGOUT} || true
  rm -rf ${LIVE_STAGING}/${LIVEMAIN} ${LIVE_WORK} ${LIVE_ROOTDIR}
fi

# Create temporary directories for building the live filesystem:
for LTEMP in $LIVE_OVLDIR $LIVE_BOOT $LIVE_MOD_SYS $LIVE_MOD_ADD $LIVE_MOD_OPT $LIVE_MOD_COS ; do
  umount ${LTEMP} 2>${DBGOUT} || true
  mkdir -p ${LTEMP}
  if [ $? -ne 0 ]; then
    echo "-- Creation of temporary directory '${LTEMP}' failed! Exiting."
    exit 1
  fi
done

# Create the mount point for our Slackware filesystem:
if [ ! -d ${LIVE_ROOTDIR} ]; then
  mkdir -p ${LIVE_ROOTDIR}
  if [ $? -ne 0 ]; then
    echo "-- Creation of moint point '${LIVE_ROOTDIR}' failed! Exiting."
    exit 1
  fi
  chmod 775 ${LIVE_ROOTDIR}
else
  echo "-- Found an existing live root directory at '${LIVE_ROOTDIR}'".
  echo "-- Check the content and deal with it, then remove that directory."
  echo "-- Exiting now."
  exit 1
fi

# ----------------------------------------------------------------------------
# Install package series:
# ----------------------------------------------------------------------------

unset INSTDIR
RODIRS="${LIVE_BOOT}"
# Create the verification file for the install_pkgs function:
echo "${THEDATE} (${BUILDER})" > ${LIVE_BOOT}/${MARKER}

# Do we need to include secureboot module?
if [ $SECUREBOOT -eq 1 ]; then
  echo "-- Adding secureboot module."
  MSEQ="${MSEQ} pkglist:secureboot"
fi

# Do we need to create/include additional module(s) defined by a pkglist:
if [ -n "$SEQ_ADDMOD" ]; then
  echo "-- Adding ${SEQ_ADDMOD}."
  MSEQ="${MSEQ} ${SEQ_ADDMOD}"
fi

# Do we need to include multilib?
# Add these last so we can easily distribute the module separately.
if [ "$MULTILIB" = "YES" ]; then
  if ! echo ${MSEQ} |grep -qw multilib ; then
    echo "-- Adding multilib."
    MSEQ="${MSEQ} pkglist:multilib"
  fi
fi

echo "-- Creating liveslak ${VERSION} '${LIVEDE}' image (based on ${DISTRO^}-${SL_VERSION} ${SL_ARCH})."

# Module sequence can be composed of multiple sub-sequences:
for MSUBSEQ in ${MSEQ} ; do

  SL_SERIES="$(echo ${MSUBSEQ} |cut -d: -f2 |tr , ' ')"
  # MTYPE can be "tagfile", "local" or "pkglist"
  # If MTYPE was not specified, by default it is "pkglist":
  MTYPE="$(echo ${MSUBSEQ} |cut -d: -f1 |tr , ' ')"
  if [ "${MTYPE}" = "${SL_SERIES}" ]; then MTYPE="pkglist" ; fi

  # We prefix our own modules based on the source of the package list:
  case "$MTYPE" in
    tagfile) MNUM="0010" ;;
    pkglist) MNUM="0020" ;;
      local) MNUM="0030" ;;
          *) echo "** Unknown package source '$MTYPE'"; exit 1 ;;
  esac

for SPS in ${SL_SERIES} ; do

  INSTDIR=${LIVE_WORK}/${SPS}_$$
  mkdir -p ${INSTDIR}

  if [ "$FORCE" = "YES" -o $(echo ${REFRESH} |grep -wq ${SPS} ; echo $?) -eq 0 -o ! -f ${LIVE_MOD_SYS}/${MNUM}-${DISTRO}_${SPS}-${SL_VERSION}-${SL_ARCH}.sxz ]; then

    # Following conditions trigger creation of the squashed module:
    # - commandline switch '-f' was used, or;
    # - the module was mentioned in the '-r' commandline switch, or;
    # - the module does not yet exist.

    # Create the verification file for the install_pkgs function:
    echo "${THEDATE} (${BUILDER})" > ${INSTDIR}/${MARKER}

    echo "-- Installing the '${SPS}' series."
    umount ${LIVE_ROOTDIR} 2>${DBGOUT} || true
    mount -t overlay -o lowerdir=${RODIRS},upperdir=${INSTDIR},workdir=${LIVE_OVLDIR} overlay ${LIVE_ROOTDIR}

    # Install the package series:
    install_pkgs ${SPS} ${LIVE_ROOTDIR} ${MTYPE}
    umount ${LIVE_ROOTDIR} || true

    if [ "$SPS" = "a" -o "$SPS" = "${MINLIST}" ]; then

      # We need to take care of a few things first:
      if [ "$SL_ARCH" = "x86_64" -o "$SMP32" = "NO" ]; then
        KGEN=$(ls --indicator-style=none ${INSTDIR}/var/log/packages/kernel*modules* |grep -v smp |head -1 |rev | cut -d- -f3 |tr _ - |rev)
        KVER=$(ls --indicator-style=none ${INSTDIR}/lib/modules/ |grep -v smp |head -1)
      else
        KGEN=$(ls --indicator-style=none ${INSTDIR}/var/log/packages/kernel*modules* |grep smp |head -1 |rev | cut -d- -f3 |tr _ - |rev)
        KVER=$(ls --indicator-style=none ${INSTDIR}/lib/modules/ |grep smp |head -1)
      fi
      if [ -z "$KVER" ]; then
        echo "-- Could not find installed kernel in '${INSTDIR}'! Exiting."
        cleanup
        exit 1
      else
        # Move the content of the /boot directory out of the minimal system,
        # this will be joined again using overlay:
        rm -rf ${LIVE_BOOT}/boot
        mv ${INSTDIR}/boot ${LIVE_BOOT}/
        # Squash the boot files into a module as a safeguard:
        mksquashfs ${LIVE_BOOT} ${LIVE_MOD_SYS}/0000-${DISTRO}_boot-${SL_VERSION}-${SL_ARCH}.sxz -noappend -comp ${SQ_COMP} ${SQ_COMP_PARAMS}
      fi

    fi

    # Squash the installed package series into a module:
    mksquashfs ${INSTDIR} ${LIVE_MOD_SYS}/${MNUM}-${DISTRO}_${SPS}-${SL_VERSION}-${SL_ARCH}.sxz -noappend -comp ${SQ_COMP} ${SQ_COMP_PARAMS}
    rm -rf ${INSTDIR}/*

    # End result: we have our .sxz file and the INSTDIR is empty again,
    # Next step is to loop-mount the squashfs file onto INSTDIR.

  elif [ "$SPS" = "a" -o "$SPS" = "${MINLIST}" ]; then

    # We need to do a bit more if we skipped creation of 'a' or 'min' module:
    # Extract the content of the /boot directory out of the boot module,
    # else we don't have a /boot ready when we create the ISO.
    # We can not just loop-mount it because we need to write into /boot later:
    rm -rf ${LIVE_BOOT}/boot
    unsquashfs -dest ${LIVE_BOOT}/boottemp ${LIVE_MOD_SYS}/0000-${DISTRO}_boot-${SL_VERSION}-${SL_ARCH}.sxz
    mv ${LIVE_BOOT}/boottemp/* ${LIVE_BOOT}/
    rmdir ${LIVE_BOOT}/boottemp

  fi

  # Add the package series tree to the readonly lowerdirs for the overlay:
  RODIRS="${INSTDIR}:${RODIRS}"

  # Mount the modules for use in the final assembly of the ISO:
  mount -t squashfs -o loop ${LIVE_MOD_SYS}/${MNUM}-${DISTRO}_${SPS}-${SL_VERSION}-${SL_ARCH}.sxz ${INSTDIR}

done
done

# ----------------------------------------------------------------------------
# Modules for all package series are created and loop-mounted.
# Next: system configuration.
# ----------------------------------------------------------------------------

# Configuration mudule will always be created from scratch:
INSTDIR=${LIVE_WORK}/zzzconf_$$
mkdir -p ${INSTDIR}

# -------------------------------------------------------------------------- #
echo "-- Configuring the base system."
# -------------------------------------------------------------------------- #

umount ${LIVE_ROOTDIR} 2>${DBGOUT} || true
mount -t overlay -o lowerdir=${RODIRS},upperdir=${INSTDIR},workdir=${LIVE_OVLDIR} overlay ${LIVE_ROOTDIR}

# Determine the kernel version in the Live OS:
if [ "$SL_ARCH" = "x86_64" -o "$SMP32" = "NO" ]; then
  KGEN=$(ls --indicator-style=none ${LIVE_ROOTDIR}/var/log/packages/kernel*modules* |grep -v smp |head -1 |rev | cut -d- -f3 |tr _ - |rev)
  KVER=$(ls --indicator-style=none ${LIVE_ROOTDIR}/lib/modules/ |grep -v smp |head -1)
else
  KGEN=$(ls --indicator-style=none ${LIVE_ROOTDIR}/var/log/packages/kernel*modules* |grep smp |head -1 |rev | cut -d- -f3 |tr _ - |rev)
  KVER=$(ls --indicator-style=none ${LIVE_ROOTDIR}/lib/modules/ |grep smp |head -1)
fi

# Configure hostname and network:
echo "${LIVE_HOSTNAME}.home.arpa" > ${LIVE_ROOTDIR}/etc/HOSTNAME
if [ -f ${LIVE_ROOTDIR}/etc/NetworkManager/NetworkManager.conf ]; then
  sed -i -e "s/^hostname=.*/hostname=${LIVE_HOSTNAME}/" \
    ${LIVE_ROOTDIR}/etc/NetworkManager/NetworkManager.conf
fi
sed -e "s/^\(127.0.0.1\t*\)darkstar.*/\1${LIVE_HOSTNAME}.home.arpa ${LIVE_HOSTNAME}/" \
  -i ${LIVE_ROOTDIR}/etc/hosts

# Make sure we can access DNS straight away:
cat <<EOT >> ${LIVE_ROOTDIR}/etc/resolv.conf
nameserver 8.8.4.4
nameserver 8.8.8.8

EOT

# Configure default locale (script-default is 'en_US.utf8). Note that there
# is 'UTF-8' versus 'utf8' and while the former has a preference, there is
# no functional difference between the two when using Linux glibc.
# This setting can be overridden on boot:
if grep -q "^ *export LANG=" ${LIVE_ROOTDIR}/etc/profile.d/lang.sh ; then
  sed -e "s/^ *export LANG=.*/export LANG=${DEF_LOCALE}/" -i ${LIVE_ROOTDIR}/etc/profile.d/lang.sh
else
  echo "export LANG=${DEF_LOCALE}" >> ${LIVE_ROOTDIR}/etc/profile.d/lang.sh
fi
# Does not hurt to also add systemd compatible configuration:
echo "LANG=${DEF_LOCALE}" > ${LIVE_ROOTDIR}/etc/locale.conf
echo "KEYMAP=${DEF_KBD}" > ${LIVE_ROOTDIR}/etc/vconsole.conf

# Set timezone to UTC, mimicking the 'timeconfig' script in Slackware:
ln -s /usr/share/zoneinfo/UTC ${LIVE_ROOTDIR}/etc/localtime
# Could be absent so 'rm -f' to avoid script aborts:
rm -f ${LIVE_ROOTDIR}/etc/localtime-copied-from

# Qt5 expects '/etc/localtime' to be a symlink. If this is a real file,
# it causes Qt5 timezone detection to fail so that "UTC" will be returned
# always.  However if a file '/etc/timezone' exists, Qt5 will use that.
# We add the file and update the 'timeconfig' script accordingly:
echo "UTC" > ${LIVE_ROOTDIR}/etc/timezone
sed -i -n "p;s/^\( *\)rm -f localtime$/\1echo \$TZ > timezone/p" \
  ${LIVE_ROOTDIR}/usr/sbin/timeconfig

# Configure the hardware clock to be interpreted as UTC as well:
cat <<EOT > ${LIVE_ROOTDIR}/etc/hardwareclock 
# /etc/hardwareclock
#
# Tells how the hardware clock time is stored.
# You should run timeconfig to edit this file.

UTC
EOT

# Configure a nice default console font that can handle Unicode:
cat <<EOT >${LIVE_ROOTDIR}/etc/rc.d/rc.font
#!/bin/sh
#
# This selects your default screen font from among the ones in
# /usr/share/kbd/consolefonts.
#
#setfont -v

# Use Terminus font to work better with the Unicode-enabled console
# (configured in /etc/lilo.conf)
setfont -v ter-120b
EOT
chmod +x ${LIVE_ROOTDIR}/etc/rc.d/rc.font

# Enable mouse support in runlevel 3:
cat <<"EOM" > ${LIVE_ROOTDIR}/etc/rc.d/rc.gpm
#!/bin/sh
# Start/stop/restart the GPM mouse server:
if [ -x /usr/sbin/gpm ]; then
  MTYPE="imps2"
  if [ "$1" = "stop" ]; then
    echo "Stopping gpm..."
    /usr/sbin/gpm -k
  elif [ "$1" = "restart" ]; then
    echo "Restarting gpm..."
    /usr/sbin/gpm -k
    sleep 1
    /usr/sbin/gpm -m /dev/mouse -t ${MTYPE}
  else # assume $1 = start:
    echo "Starting gpm:  /usr/sbin/gpm -m /dev/mouse -t ${MTYPE}"
    /usr/sbin/gpm -m /dev/mouse -t ${MTYPE}
  fi
fi
EOM
chmod +x ${LIVE_ROOTDIR}/etc/rc.d/rc.gpm

# Remove ssh server keys - new unique keys will be generated
# at first boot of the live system: 
rm -f ${LIVE_ROOTDIR}/etc/ssh/*key*

# Sanitize /etc/fstab :
cat <<EOT > ${LIVE_ROOTDIR}/etc/fstab
proc      /proc       proc        defaults   0   0
sysfs     /sys        sysfs       defaults   0   0
tmpfs     /tmp        tmpfs       defaults,nodev,nosuid,mode=1777  0   0
tmpfs     /var/tmp    tmpfs       defaults,nodev,nosuid,mode=1777  0   0
tmpfs     /dev/shm    tmpfs       defaults,nodev,nosuid,mode=1777  0   0
devpts    /dev/pts    devpts      gid=5,mode=620   0   0
none      /           tmpfs       defaults   1   1

EOT

# Prevent loop devices (sxz modules) from appearing in filemanagers:
mkdir -p ${LIVE_ROOTDIR}/etc/udev/rules.d
cat <<EOL > ${LIVE_ROOTDIR}/etc/udev/rules.d/11-local.rules
# Prevent loop devices (mounted sxz modules) from appearing in
# filemanager panels - http://www.seguridadwireless.net

# Hidden loops for udisks:
KERNEL=="loop*", ENV{UDISKS_PRESENTATION_HIDE}="1"

# Hidden loops for udisks2:
KERNEL=="loop*", ENV{UDISKS_IGNORE}="1"
EOL

# Set a root password. Note 'chpasswd' sometimes segfaults in the first form.
if ! echo "root:${ROOTPW}" | /usr/sbin/chpasswd -R ${LIVE_ROOTDIR} 2>/dev/null; then
  echo "root:${ROOTPW}" | chroot ${LIVE_ROOTDIR} /usr/sbin/chpasswd
fi

# Create group and user for the avahi/colord/nvidia persistence daemon:
if ! chroot ${LIVE_ROOTDIR} /usr/bin/getent passwd ${NVUID} > /dev/null 2>&1 ;
then
  chroot ${LIVE_ROOTDIR} /usr/sbin/groupadd -g ${AVGRPNR} ${AVGRP}
  chroot ${LIVE_ROOTDIR} /usr/sbin/useradd -c "Avahi User" -u ${AVUIDNR} -g ${AVGRPNR} -d /dev/null -s /bin/false ${AVUID}
  chroot ${LIVE_ROOTDIR} /usr/sbin/groupadd -g ${CLRGRPNR} ${CLRGRP}
  chroot ${LIVE_ROOTDIR} /usr/sbin/useradd -u ${CLRUIDNR} -g ${CLRGRPNR} -d /var/lib/${CLRGRP} -s /bin/false ${CLRUID}
  chroot ${LIVE_ROOTDIR} /usr/sbin/groupadd -g ${NVGRPNR} ${NVGRP}
  chroot ${LIVE_ROOTDIR} /usr/sbin/useradd -c "Nvidia persistence" -u ${NVUIDNR} -g ${NVGRPNR} -d /dev/null -s /bin/false ${NVUID}
  chroot ${LIVE_ROOTDIR} /usr/sbin/groupadd -g ${FPGRPNR} ${FPGRP}
  chroot ${LIVE_ROOTDIR} /usr/sbin/useradd -u ${FPUIDNR} -g ${FPGRPNR} -d /var/lib/${FPGRP} -s /bin/false ${FPUID}
  chroot ${LIVE_ROOTDIR} /usr/sbin/groupadd -g ${TSGRPNR} ${TSGRP}
  chroot ${LIVE_ROOTDIR} /usr/sbin/useradd -c "TSS/TPM Agent" -u ${TSUIDNR} -g ${TSGRPNR} -d /dev/null -s /bin/false ${TSUID}

#  chroot ${LIVE_ROOTDIR} /usr/sbin/useradd -u ${TSUIDNR} -g ${TSGRPNR} -d /home/${TSGRP} -s /bin/bash ${TSUID}

  if ! echo "${NVUID}:$(openssl rand -base64 12)" | /usr/sbin/chpasswd -R ${LIVE_ROOTDIR} 2>/dev/null ; then
    echo "${NVUID}:$(openssl rand -base64 12)" | chroot ${LIVE_ROOTDIR} /usr/sbin/chpasswd
  fi
fi

# Determine the full name of the live account in the image:
if [ -z "${LIVEUIDFN}" ]; then
  eval LIVEUIDFN=\$LIVEUIDFN_${LIVEDE}
  if [ -z "${LIVEUIDFN}" ]; then
    LIVEUIDFN="${DISTRO^} Live User"
  fi
fi

# Create a nonprivileged user account (called "live" by default):
chroot ${LIVE_ROOTDIR} /usr/sbin/useradd -c "${LIVEUIDFN}" -g users -G wheel,audio,cdrom,floppy,plugdev,video,power,netdev,lp,scanner,kmem,dialout,games,disk,input -u ${LIVEUIDNR} -d /home/${LIVEUID} -m -s /bin/bash ${LIVEUID}
if ! echo "${LIVEUID}:${LIVEPW}" | /usr/sbin/chpasswd -R ${LIVE_ROOTDIR} 2>/dev/null ; then
  echo "${LIVEUID}:${LIVEPW}" | chroot ${LIVE_ROOTDIR} /usr/sbin/chpasswd
fi

# Configure suauth if we are not on a PAM system (where this does not work):
if [ ! -L ${LIVE_ROOTDIR}/lib${DIRSUFFIX}/libpam.so.? ]; then
  cat <<EOT >${LIVE_ROOTDIR}/etc/suauth
root:${LIVEUID}:OWNPASS
root:ALL EXCEPT GROUP wheel:DENY
EOT
  chmod 600 ${LIVE_ROOTDIR}/etc/suauth
fi

# Configure sudoers:
chmod 640 ${LIVE_ROOTDIR}/etc/sudoers
# Slackware 14.2:
sed -i ${LIVE_ROOTDIR}/etc/sudoers -e 's/# *\(%wheel\sALL=(ALL)\sALL\)/\1/'
# Slackware 15.0:
sed -i ${LIVE_ROOTDIR}/etc/sudoers -e 's/# *\(%wheel\sALL=(ALL:ALL)\sALL\)/\1/'
chmod 440 ${LIVE_ROOTDIR}/etc/sudoers

# Also treat members of the 'wheel' group as admins next to root:
mkdir -p ${LIVE_ROOTDIR}/etc/polkit-1/rules.d
cat <<EOT > ${LIVE_ROOTDIR}/etc/polkit-1/rules.d/10-wheel-admin.rules
polkit.addAdminRule(function(action, subject) {
    return ["unix-group:wheel"];
});
EOT

# Add some convenience to the bash shell:
mkdir -p  ${LIVE_ROOTDIR}/etc/skel/
cat << "EOT" > ${LIVE_ROOTDIR}/etc/skel/.bashrc
# If not running interactively, don't do anything
[ -z "$PS1" ] && return
# Check the window size after each command and, if necessary,
# update the values of LINES and COLUMNS.
shopt -s checkwinsize
EOT
cat << "EOT" > ${LIVE_ROOTDIR}/etc/skel/.profile
# Source a .bashrc if it exists:
[[ -r ~/.bashrc ]] && . ~/.bashrc

# Define some useful aliases:
alias ll="ls -la $LS_OPTIONS"
lsp() { basename $(ls -1 "/var/log/packages/$@"*) ; }
alias md="mkdir"
alias tarview="tar -tvf"
# GREP_OPTIONS="--color=auto" is deprecated, use alias to enable colored output:
alias grep="grep --color=auto"
alias fgrep="fgrep --color=auto"
alias egrep="egrep --color=auto"

# Ctrl-D should not log us off immediately; now it needs 10 times:
set -o ignoreeof
EOT

# Do the root account the same favor:
cat ${LIVE_ROOTDIR}/etc/skel/.profile > ${LIVE_ROOTDIR}/root/.profile
chown root:root ${LIVE_ROOTDIR}/root/.profile

# If the 'vi' symlink doees not exist, add it:
if [ ! -e ${LIVE_ROOTDIR}/usr/bin/vi ]; then
  if [ -x ${LIVE_ROOTDIR}/usr/bin/elvis ]; then
    ln -s elvis ${LIVE_ROOTDIR}/usr/bin/vi
  else
    ln -s vim ${LIVE_ROOTDIR}/usr/bin/vi
  fi
fi

# Add a screen configuration:
cat <<"EOT" > ${LIVE_ROOTDIR}/etc/skel/.screenrc
vbell on
autodetach on
startup_message off
pow_detach_msg "Screen session of \$LOGNAME \$:cr:\$:nl:ended."
defscrollback 3000
attrcolor b ".I"
defbce "on"
term xterm-256color
shell -$SHELL

# xterm:
termcap  xterm hs@:cs=\E[%i%d;%dr:im=\E[4h:ei=\E[4l
terminfo xterm hs@:cs=\E[%i%p1%d;%p2%dr:im=\E[4h:ei=\E[4l
termcapinfo xterm Z0=\E[?3h:Z1=\E[?3l:is=\E[r\E[m\E[2J\E[H\E[?7h\E[?1;4;6l
termcapinfo xterm* OL=10000
termcapinfo xterm 'VR=\E[?5h:VN=\E[?5l'
termcapinfo xterm 'k1=\E[11~:k2=\E[12~:k3=\E[13~:k4=\E[14~'
termcapinfo xterm 'kh=\EOH:kI=\E[2~:kD=\E[3~:kH=\EOF:kP=\E[5~:kN=\E[6~'
termcapinfo xterm 'hs:ts=\E]2;:fs=\007:ds=\E]2;screen\007'
termcapinfo xterm 'vi=\E[?25l:ve=\E[34h\E[?25h:vs=\E[34l'
termcapinfo xterm 'XC=K%,%\E(B,[\304,\\\\\326,]\334,{\344,|\366,}\374,~\337'
termcapinfo xterm* be
termcapinfo xterm* ti@:te@
termcapinfo xterm 'Co#256:AB=\E[48;5;%dm:AF=\E[38;5;%dm'

# vt100:
termcap  vt100* ms:AL=\E[%dL:DL=\E[%dM:UP=\E[%dA:DO=\E[%dB:LE=\E[%dD:RI=\E[%dC
terminfo vt100* ms:AL=\E[%p1%dL:DL=\E[%p1%dM:UP=\E[%p1%dA:DO=\E[%p1%dB:LE=\E[%p1%dD:RI=\E[%p1%dC
termcapinfo linux C8

# Tabbed colored hardstatus line
hardstatus alwayslastline
hardstatus string '%{= Kd} %{= Kd}%-w%{= Kr}[%{= KW}%n %t%{= Kr}]%{= Kd}%+w %-= %{KG} %H%{KW}|%{KY}%101`%{KW}|%D %M %d %Y%{= Kc} %C%A%{-}'
# Hide hardstatus: ctrl-a f
bind f eval "hardstatus ignore"
# Show hardstatus: ctrl-a F
bind F eval "hardstatus alwayslastline"
EOT
# Give root a copy:
cat ${LIVE_ROOTDIR}/etc/skel/.screenrc > ${LIVE_ROOTDIR}/root/.screenrc

if [ -f ${LIVE_ROOTDIR}/etc/rc.d/rc.networkmanager ]; then
  # Enable NetworkManager if present:
  chmod +x ${LIVE_ROOTDIR}/etc/rc.d/rc.networkmanager
  # And disable Slackware's own way of configuring eth0:
  cat <<EOT > ${LIVE_ROOTDIR}/etc/rc.d/rc.inet1.conf
IFNAME[0]="eth0"
IPADDR[0]=""
NETMASK[0]=""
USE_DHCP[0]=""
DHCP_HOSTNAME[0]=""

GATEWAY=""
DEBUG_ETH_UP="no"
EOT

  # Ensure that NetworkManager uses its internal DHCP client - seems to give
  # better compliancy:
  sed -e "s/^dhcp=dhcpcd/#&/" -e "s/^#\(dhcp=internal\)/\1/" \
      -i ${LIVE_ROOTDIR}/etc/NetworkManager/conf.d/00-dhcp-client.conf

else
  # Use Slackware's own network configuration routing for eth0 in base image:
  cat <<EOT > ${LIVE_ROOTDIR}/etc/rc.d/rc.inet1.conf
IFNAME[0]="eth0"
IPADDR[0]=""
NETMASK[0]=""
USE_DHCP[0]="yes"
DHCP_HOSTNAME[0]="${LIVE_HOSTNAME}"

GATEWAY=""
DEBUG_ETH_UP="no"
EOT
fi

# First disable any potentially incorrect mirror for slackpkg:
sed -e "s/^ *\([^#]\)/#\1/" -i ${LIVE_ROOTDIR}/etc/slackpkg/mirrors
# Enable a Slackware mirror for slackpkg:
cat <<EOT >> ${LIVE_ROOTDIR}/etc/slackpkg/mirrors
https://mirrors.slackware.com/slackware/slackware${DIRSUFFIX}-${SL_VERSION}/
EOT

## Blacklist the l10n packages;
#cat << EOT >> ${LIVE_ROOTDIR}/etc/slackpkg/blacklist
#
## Blacklist the l10n packages;
#calligra-l10n-
#kde-l10n-
#
#EOT

# If we added slackpkg+ for easier system management, let's configure it too.
# Update the cache for slackpkg:
echo "-- Creating slackpkg cache, takes a few seconds..."
chroot "${LIVE_ROOTDIR}" /bin/bash <<EOSL 2>${DBGOUT}

# Rebuild SSL certificate database to prevent GPG verification errors
# which are in fact triggered by SSL certificate errors:
/usr/sbin/update-ca-certificates --fresh 1>/dev/null

if [ -f var/log/packages/slackpkg+-* ] ; then
  cat <<EOPL > etc/slackpkg/slackpkgplus.conf
SLACKPKGPLUS=on
VERBOSE=1
ALLOW32BIT=off
USEBL=1
WGETOPTS="--timeout=20 --tries=2"
GREYLIST=off
STRICTGPG=on
PKGS_PRIORITY=( gcs43 )
REPOPLUS=( slackpkgplus gcs43 )
MIRRORPLUS['slackpkgplus']=http://slakfinder.org/slackpkg+/
MIRRORPLUS['gcs43']=https://slackware.lngn.net/pub/x86_64/slackware64-current/gcs/gcs43/
EOPL
fi

# add slackpkg+ greylist for gcs43 pkgs overriding "current" slackware packages
if [ -f var/log/packages/slackpkg+-* ] ; then
  cat <<EOPL > etc/slackpkg/greylist
atkmm
gcr
glibmm
pangomm
polkit
EOPL
fi

# add slackpkg+ blacklist for gnome_core ensuring we don't end up install-new-ing kde & xfce package sets
# and/or the kernel packages
if [ -f var/log/packages/slackpkg+-* ] ; then
  cat <<EOPL > etc/slackpkg/blacklist
kernel-generic.*
# we're not supposed to blacklist the headers, but we're going to anyway.
kernel-headers.*
kernel-huge.*
kernel-modules.*
kernel-source.*
kde/
xfce/
EOPL
fi

# Slackpkg wants you to opt-in on slackware-current:
if [ "${SL_VERSION}" = "current" ]; then
  mkdir -p /var/lib/slackpkg
  touch /var/lib/slackpkg/current
fi

ARCH=${SL_ARCH} /usr/sbin/slackpkg -batch=on -default_answer=y update gpg
ARCH=${SL_ARCH} /usr/sbin/slackpkg -batch=on -default_answer=y update
# Let any lingering .new files replace their originals:
yes o | ARCH=${SL_ARCH} /usr/sbin/slackpkg new-config

EOSL

# Add our scripts to the Live OS:
mkdir -p  ${LIVE_ROOTDIR}/usr/local/sbin
install -m0755 ${LIVE_TOOLDIR}/makemod ${LIVE_TOOLDIR}/iso2usb.sh ${LIVE_TOOLDIR}/isocomp.sh ${LIVE_TOOLDIR}/upslak.sh ${LIVE_ROOTDIR}/usr/local/sbin/

# Add PXE Server infrastructure:
mkdir -p ${LIVE_ROOTDIR}/var/lib/tftpboot/pxelinux.cfg
cp -ia /usr/share/syslinux/pxelinux.0 ${LIVE_ROOTDIR}/var/lib/tftpboot/
ln -s /mnt/livemedia/boot/generic ${LIVE_ROOTDIR}/var/lib/tftpboot/
ln -s /mnt/livemedia/boot/initrd.img ${LIVE_ROOTDIR}/var/lib/tftpboot/
mkdir -p ${LIVE_ROOTDIR}/var/lib/tftpboot/EFI/BOOT
ln -s /mnt/livemedia/EFI/BOOT ${LIVE_ROOTDIR}/var/lib/tftpboot/uefi
ln -s /mnt/livemedia/EFI/BOOT/bootx64.efi ${LIVE_ROOTDIR}/var/lib/tftpboot/EFI/BOOT/
cat ${LIVE_TOOLDIR}/pxeserver.tpl | sed \
  -e "s/@DIRSUFFIX@/$DIRSUFFIX/g" \
  -e "s/@DISTRO@/$DISTRO/g" \
  -e "s/@CDISTRO@/${DISTRO^}/g" \
  -e "s/@UDISTRO@/${DISTRO^^}/g" \
  -e "s/@KVER@/$KVER/g" \
  -e "s/@LIVEDE@/$LIVEDE/g" \
  -e "s/@LIVEMAIN@/$LIVEMAIN/g" \
  -e "s/@MARKER@/$MARKER/g" \
  -e "s/@SL_VERSION@/$SL_VERSION/g" \
  -e "s/@VERSION@/$VERSION/g" \
  > ${LIVE_ROOTDIR}/usr/local/sbin/pxeserver
chmod 755 ${LIVE_ROOTDIR}/usr/local/sbin/pxeserver

# Add a harddisk installer to the ISO.
# The huge kernel does not require an initrd and installation to the
# hard drive will not be complicated, so a liveslak install is recommended
# for newbies only if the ISO contains huge kernel...
if [ -f ${DEF_SL_PKGROOT}/../isolinux/initrd.img ]; then
  echo "-- Adding 'setup2hd' hard disk installer to /usr/share/${LIVEMAIN}/."
  # Extract the 'setup' files we need from the Slackware installer
  # and move them to a single directory in the ISO:
  mkdir -p ${LIVE_ROOTDIR}/usr/share/${LIVEMAIN}
  cd  ${LIVE_ROOTDIR}/usr/share/${LIVEMAIN}
    uncompressfs ${DEF_SL_PKGROOT}/../isolinux/initrd.img | cpio -i -d -m -H newc usr/lib/setup/* sbin/probe sbin/fixdate
    mv -i usr/lib/setup/* sbin/probe sbin/fixdate .
    rm -r usr sbin
    rm -f setup
  cd - 1>/dev/null
  # Fix some occurrences of '/mnt' that should not be used in the Live ISO
  # (this was applied in Slackware > 14.2 but does not harm to do this anyway):
  sed -i ${LIVE_ROOTDIR}/usr/share/${LIVEMAIN}/* \
    -e 's,T_PX=/mnt,T_PX="`cat $TMP/SeTT_PX`",g' \
    -e 's, /mnt, ${T_PX},g' \
    -e 's,=/mnt$,=${T_PX},g' \
    -e 's,=/mnt/,=${T_PX}/,g'
  # Allow a choice of dialog:
  sed -i ${LIVE_ROOTDIR}/usr/share/${LIVEMAIN}/* \
    -e '1a \\nDIALOG=${DIALOG:-dialog}\n' \
    -e 's/dialog -/${DIALOG} -/'
  # If T_PX is used in a script, it should be defined first:
  for FILE in ${LIVE_ROOTDIR}/usr/share/${LIVEMAIN}/* ; do
    if grep -q T_PX $FILE ; then
      if ! grep -q "^T_PX=" $FILE ; then
        if ! grep -q "^TMP=" $FILE ; then
          sed -e '/#!/a T_PX="`cat $TMP/SeTT_PX`"' -i $FILE
          sed -e '/#!/a TMP=/var/log/setup/tmp' -i $FILE
        else
          sed -e '/^TMP=/a T_PX="`cat $TMP/SeTT_PX`"' -i $FILE
        fi
      fi
    fi
  done
  if [ -f ${LIVE_ROOTDIR}/sbin/liloconfig ]; then
    if [ -f ${LIVE_TOOLDIR}/patches/liloconfig_${SL_VERSION}.patch ]; then
      LILOPATCH=liloconfig_${SL_VERSION}.patch
    elif [ -f ${LIVE_TOOLDIR}/patches/liloconfig.patch ]; then
      LILOPATCH=liloconfig.patch
    else
      LILOPATCH=""
    fi
    if [ -n "${LILOPATCH}" ]; then
      patch ${LIVE_ROOTDIR}/sbin/liloconfig ${LIVE_TOOLDIR}/patches/${LILOPATCH}
    fi
  fi
  if [ -f ${LIVE_ROOTDIR}/usr/sbin/eliloconfig ]; then
    if [ -f ${LIVE_TOOLDIR}/patches/eliloconfig_${SL_VERSION}.patch ]; then
      ELILOPATCH=eliloconfig_${SL_VERSION}.patch
    elif  [ -f ${LIVE_TOOLDIR}/patches/eliloconfig.patch ]; then
      ELILOPATCH=eliloconfig.patch
    else
      ELILOPATCH=""
    fi
    if [ -n "${ELILOPATCH}" ]; then
      patch ${LIVE_ROOTDIR}/usr/sbin/eliloconfig ${LIVE_TOOLDIR}/patches/${ELILOPATCH}
    fi
  fi
  # Fix some occurrences of '/usr/lib/setup/' that are covered by $PATH:
  sed -i -e 's,/usr/lib/setup/,,g' -e 's,:/usr/lib/setup,:/usr/share/${LIVEMAIN},g' ${LIVE_ROOTDIR}/usr/share/${LIVEMAIN}/*
  # Prevent SeTconfig from asking redundant questions after a Live OS install:
  sed -i ${LIVE_ROOTDIR}/usr/share/${LIVEMAIN}/SeTconfig \
    -e '/.\/var\/log\/setup\/$SCRIPT $T_PX $ROOT_DEVICE/i # Skip stuff that was taken care of by liveslak\nif [ -f $TMP/SeTlive ] && echo $SCRIPT |grep -qE "(make-bootdisk|mouse|setconsolefont|xwmconfig)"; then true; else' \
    -e '/.\/var\/log\/setup\/$SCRIPT $T_PX $ROOT_DEVICE/a fi'
  # Add the Slackware Live HD installer scripts:
  for USCRIPT in SeTuacct SeTudiskpart SeTumedia SeTupass SeTpasswd SeTfirewall rc.firewall setup.liveslak setup.slackware ; do
    cat ${LIVE_TOOLDIR}/setup2hd/${USCRIPT}.tpl | sed \
      -e "s/@DIRSUFFIX@/$DIRSUFFIX/g" \
      -e "s/@DISTRO@/$DISTRO/g" \
      -e "s/@CDISTRO@/${DISTRO^}/g" \
      -e "s/@UDISTRO@/${DISTRO^^}/g" \
      -e "s/@KVER@/$KVER/g" \
      -e "s/@LIVEDE@/$LIVEDE/g" \
      -e "s/@LIVEMAIN@/$LIVEMAIN/g" \
      -e "s/@LIVEUID@/$LIVEUID/g" \
      -e "s/@LIVEUIDNR@/$LIVEUIDNR/g" \
      -e "s/@MARKER@/$MARKER/g" \
      -e "s/@SL_VERSION@/$SL_VERSION/g" \
      -e "s/@VERSION@/$VERSION/g" \
      > ${LIVE_ROOTDIR}/usr/share/${LIVEMAIN}/${USCRIPT}
    chmod 755 ${LIVE_ROOTDIR}/usr/share/${LIVEMAIN}/${USCRIPT}
  done
  mkdir -p ${LIVE_ROOTDIR}/usr/local/sbin
  cat ${LIVE_TOOLDIR}/setup2hd.tpl | sed \
    -e "s/@DIRSUFFIX@/$DIRSUFFIX/g" \
    -e "s/@DISTRO@/$DISTRO/g" \
    -e "s/@CDISTRO@/${DISTRO^}/g" \
    -e "s/@UDISTRO@/${DISTRO^^}/g" \
    -e "s/@KVER@/$KVER/g" \
    -e "s/@LIVEDE@/$LIVEDE/g" \
    -e "s/@LIVEMAIN@/$LIVEMAIN/g" \
    -e "s/@LIVEUID@/$LIVEUID/g" \
    -e "s/@LIVEUIDNR@/$LIVEUIDNR/g" \
    -e "s/@MARKER@/$MARKER/g" \
    -e "s/@SL_VERSION@/$SL_VERSION/g" \
    -e "s/@VERSION@/$VERSION/g" \
    > ${LIVE_ROOTDIR}/usr/local/sbin/setup2hd
  chmod 755 ${LIVE_ROOTDIR}/usr/local/sbin/setup2hd
  # Slackware Live HD post-install customization hook:
  if [ -f ${LIVE_TOOLDIR}/setup2hd.local.tpl ]; then
    # The '.local' suffix means: install it as a sample file only:
    HOOK_SRC="${LIVE_TOOLDIR}/setup2hd.local.tpl"
    HOOK_DST="${LIVE_ROOTDIR}/usr/share/${LIVEMAIN}/setup2hd.$DISTRO.sample"
  elif [ -f ${LIVE_TOOLDIR}/setup2hd.$DISTRO ]; then
    # Install the hook; the file will be sourced by "setup2hd".
    HOOK_SRC="${LIVE_TOOLDIR}/setup2hd.$DISTRO"
    HOOK_DST="${LIVE_ROOTDIR}/usr/share/${LIVEMAIN}/setup2hd.$DISTRO"
  fi
  cat ${HOOK_SRC} | sed \
    -e "s/@DIRSUFFIX@/$DIRSUFFIX/g" \
    -e "s/@DISTRO@/$DISTRO/g" \
    -e "s/@CDISTRO@/${DISTRO^}/g" \
    -e "s/@UDISTRO@/${DISTRO^^}/g" \
    -e "s/@KVER@/$KVER/g" \
    -e "s/@LIVEDE@/$LIVEDE/g" \
    -e "s/@LIVEMAIN@/$LIVEMAIN/g" \
    -e "s/@MARKER@/$MARKER/g" \
    -e "s/@SL_VERSION@/$SL_VERSION/g" \
    -e "s/@VERSION@/$VERSION/g" \
    > ${HOOK_DST}
  chmod 644 ${HOOK_DST}
 else
  echo "-- Could not find ${DEF_SL_PKGROOT}/../isolinux/initrd.img - not adding 'setup2hd'!"
fi

# Add the documentation:
mkdir -p  ${LIVE_ROOTDIR}/usr/doc/liveslak-${VERSION}
install -m0644 ${LIVE_TOOLDIR}/README* ${LIVE_ROOTDIR}/usr/doc/liveslak-${VERSION}/
mkdir -p  ${LIVE_ROOTDIR}/usr/doc/${DISTRO}${DIRSUFFIX}-${SL_VERSION}
install -m0644 \
  ${DEF_SL_PKGROOT}/../{ANNOUNCE,CHANGES_AND_HINTS,COPY,CRYPTO,README,RELEASE_NOTES,SPEAK,*HOWTO,UPGRADE}* \
  ${DEF_SL_PKGROOT}/../usb-and-pxe-installers/README* \
  ${LIVE_ROOTDIR}/usr/doc/${DISTRO}${DIRSUFFIX}-${SL_VERSION}/

# -------------------------------------------------------------------------- #
echo "-- Configuring the X base system."
# -------------------------------------------------------------------------- #

# Reduce the number of local consoles, two should be enough:
sed -i -e '/^c3\|^c4\|^c5\|^c6/s/^/# /' ${LIVE_ROOTDIR}/etc/inittab

# Give the 'live' user a face:
if [ -f "${LIVE_TOOLDIR}/media/${LIVEDE,,}/icons/default.png" ]; then
  # Use custom face icon if available for the Live variant:
  FACE_ICON="${LIVE_TOOLDIR}/media/${LIVEDE,,}/icons/default.png"
else
  # Use the default Slackware blue 'S':
  FACE_ICON="${LIVE_TOOLDIR}/blueSW-64px.png"
fi
convert ${FACE_ICON} -resize 64x64 - >${LIVE_ROOTDIR}/home/${LIVEUID}/.face.icon
chown --reference=${LIVE_ROOTDIR}/home/${LIVEUID} ${LIVE_ROOTDIR}/home/${LIVEUID}/.face.icon
( cd ${LIVE_ROOTDIR}/home/${LIVEUID}/ ; ln .face.icon .face )
mkdir -p ${LIVE_ROOTDIR}/usr/share/apps/kdm/pics/users
convert ${FACE_ICON} -resize 64x64 - >${LIVE_ROOTDIR}/usr/share/apps/kdm/pics/users/blues.icon

# Give XDM a nicer look:
mkdir -p ${LIVE_ROOTDIR}/etc/X11/xdm/liveslak-xdm
cp -a ${LIVE_TOOLDIR}/xdm/* ${LIVE_ROOTDIR}/etc/X11/xdm/liveslak-xdm/
# Point xdm to the custom /etc/X11/xdm/liveslak-xdm/xdm-config:
#sed -i ${LIVE_ROOTDIR}/etc/rc.d/rc.4 -e 's,bin/xdm -nodaemon,& -config /etc/X11/xdm/liveslak-xdm/xdm-config,'
sed -i 's/gdm -nodaemon/gdm/g' ${LIVE_ROOTDIR}/etc/rc.d/rc.4
# Adapt xdm configuration to target architecture:
sed -i "s/@LIBDIR@/lib${DIRSUFFIX}/g" ${LIVE_ROOTDIR}/etc/X11/xdm/liveslak-xdm/xdm-config

# XDM needs a C preprocessor to calculate the login box position, and if
# the ISO contains mcpp instead of the cpp contained in full gcc, we will
# create a symlink (don't forget to install mcpp of course!):
if [ ! -e ${LIVE_ROOTDIR}/usr/bin/cpp ] && [ -x ${LIVE_ROOTDIR}/usr/bin/mcpp ];
then
  ln -s mcpp ${LIVE_ROOTDIR}/usr/bin/cpp
fi
 
# The Xscreensaver should show a blank screen only, to prevent errors about
# missing modules:
echo "mode:           blank" > ${LIVE_ROOTDIR}/home/${LIVEUID}/.xscreensaver

if [ -x ${LIVE_ROOTDIR}/usr/bin/fc-cache ]; then
  # Make the EmojiOne TTF font universally available:
  mkdir -p ${LIVE_ROOTDIR}/etc/fonts
  cat << EOT > ${LIVE_ROOTDIR}/etc/fonts/local.conf
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<!-- /etc/fonts/local.conf file to customize system font access -->
<fontconfig>
<!-- Contains the EmojiOne TTF font: -->
<dir>/usr/lib${DIRSUFFIX}/firefox/fonts</dir>
</fontconfig>
EOT
  chroot ${LIVE_ROOTDIR} fc-cache -f
fi

# Allow direct scanning via xsane (no temporary intermediate files) in Gimp:
if [ ! -L ${LIVE_ROOTDIR}/usr/lib${DIRSUFFIX}/gimp/2.0/plug-ins/xsane  ]; then
  mkdir -p ${LIVE_ROOTDIR}/usr/lib${DIRSUFFIX}/gimp/2.0/plug-ins
  ln -s /usr/bin/xsane \
    ${LIVE_ROOTDIR}/usr/lib${DIRSUFFIX}/gimp/2.0/plug-ins/xsane
fi

## Enable this only after we checked all dialog calls for compatibility ##
## If Xdialog is installed, set DIALOG environment variable:            ##
mkdir -p ${LIVE_ROOTDIR}/etc/profile.d
cat <<EOT > ${LIVE_ROOTDIR}/etc/profile.d/dialog.sh
#!/bin/sh
if [ -x /usr/bin/Xdialog ]; then
  DIALOG=Xdialog
  XDIALOG_HIGH_DIALOG_COMPAT=1
  XDIALOG_FORCE_AUTOSIZE=1
  export DIALOG XDIALOG_HIGH_DIALOG_COMPAT XDIALOG_FORCE_AUTOSIZE
fi
EOT
cat <<EOT > ${LIVE_ROOTDIR}/etc/profile.d/dialog.csh
#!/bin/csh
if (-x /usr/bin/Xdialog) then
  setenv DIALOG Xdialog
  setenv XDIALOG_HIGH_DIALOG_COMPAT 1
  setenv XDIALOG_FORCE_AUTOSIZE 1
endif
EOT
# Once we are certain this works, make the scripts executable:
chmod 0644 ${LIVE_ROOTDIR}/etc/profile.d/dialog.{c,}sh

# Add a shortcut to 'setup2hd' on the user's desktop:
mkdir -p ${LIVE_ROOTDIR}/usr/share/pixmaps
install -m 0644 ${LIVE_TOOLDIR}/media/slackware/icons/graySW_512px.png \
  ${LIVE_ROOTDIR}/usr/share/pixmaps/liveslak.png
#mkdir -p ${LIVE_ROOTDIR}/home/${LIVEUID}/Desktop
#cat <<EOT > ${LIVE_ROOTDIR}/home/${LIVEUID}/Desktop/.directory
#[Desktop Entry]
#Encoding=UTF-8
#Icon=user-desktop
#Type=Directory
#EOT
cat <<EOT > ${LIVE_ROOTDIR}/usr/share/applications/setup2hd.desktop
#!/usr/bin/env xdg-open
[Desktop Entry]
Type=Application
Terminal=true
Name=Install ${DISTRO^}
Comment=Install ${DISTRO^} (live or regular) to Harddisk
Icon=/usr/share/pixmaps/liveslak.png
Exec=sudo -i /usr/local/sbin/setup2hd
EOT
# Let Plasma5 trust the desktop shortcut:
chmod 0544 ${LIVE_ROOTDIR}/usr/share/applications/setup2hd.desktop


# -------------------------------------------------------------------------- #
echo "-- Configuring GNOME."
# -------------------------------------------------------------------------- #

# Prepare some GNOME defaults for the 'live' user and any new users.
# (don't show icons on the desktop for irrelevant stuff).
# Also, allow other people to add their own custom skel*.txz archives:
mkdir -p ${LIVE_ROOTDIR}/etc/skel/
for SKEL in ${LIVE_TOOLDIR}/skel/skel*.txz ; do
  tar -xf ${SKEL} -C ${LIVE_ROOTDIR}/etc/skel/
done

# Only configure for KDE4 if it is actually installed:
if [ -d ${LIVE_ROOTDIR}/usr/lib${DIRSUFFIX}/kde4/libexec ]; then

  # -------------------------------------------------------------------------- #
  echo "-- Configuring KDE4."
  # -------------------------------------------------------------------------- #

  # Adjust some usability issues with the default desktop layout:
  if [ -f ${LIVE_ROOTDIR}/usr/share/apps/plasma/layout-templates/org.kde.plasma-desktop.defaultPanel/contents/layout.js ]; then
    # Only apply to an unmodified file (Slackware 14.2 already implements it):
    if grep -q 'tasks.writeConfig' ${LIVE_ROOTDIR}/usr/share/apps/plasma/layout-templates/org.kde.plasma-desktop.defaultPanel/contents/layout.js ; then
      sed -i \
        -e '/showActivityManager/a konsole = panel.addWidget("quicklaunch")' \
        -e '/showActivityManager/a dolphin = panel.addWidget("quicklaunch")' \
        -e '/showActivityManager/a firefox = panel.addWidget("quicklaunch")' \
        -e '$a firefox.writeConfig("iconUrls","file:///usr/share/applications/mozilla-firefox.desktop")' \
        -e '$a dolphin.writeConfig("iconUrls","file:////usr/share/applications/kde4/dolphin.desktop")' \
        -e '$a konsole.writeConfig("iconUrls","file:///usr/share/applications/kde4/konsole.desktop")' \
        -e '/tasks.writeConfig/d' \
        ${LIVE_ROOTDIR}/usr/share/apps/plasma/layout-templates/org.kde.plasma-desktop.defaultPanel/contents/layout.js
    fi
  fi

  # Prepare some KDE4 defaults for the 'live' user and any new users.

  # Preselect the user 'live' in KDM:
  mkdir -p ${LIVE_ROOTDIR}/var/lib/kdm
  cat <<EOT > ${LIVE_ROOTDIR}/var/lib/kdm/kdmsts
[PrevUser]
:0=${LIVEUID}
EOT
  chmod 600 ${LIVE_ROOTDIR}/var/lib/kdm/kdmsts

  # Set default GTK+ theme for Qt applications:
  mkdir -p  ${LIVE_ROOTDIR}/etc/skel/
  cat << EOF > ${LIVE_ROOTDIR}/etc/skel/.gtkrc-2.0
include "/usr/share/themes/Adwaita/gtk-2.0/gtkrc"
include "/usr/share/gtk-2.0/gtkrc"
include "/etc/gtk-2.0/gtkrc"
gtk-theme-name="Adwaita"
EOF
  mkdir -p ${LIVE_ROOTDIR}/etc/skel/.config/gtk-3.0
  cat << EOF > ${LIVE_ROOTDIR}/etc/skel/.config/gtk-3.0/settings.ini
[Settings]
gtk-theme-name = Adwaita
EOF

  # Be gentle to low-performance USB media and limit disk I/O:
  mkdir -p  ${LIVE_ROOTDIR}/etc/skel/.kde/share/config
  cat <<EOT > ${LIVE_ROOTDIR}/etc/skel/.kde/share/config/nepomukserverrc
[Basic Settings]
Configured repositories=main
Start Nepomuk=false

[Service-nepomukstrigiservice]
autostart=false

[main Settings]
Storage Dir[\$e]=\$HOME/.kde/share/apps/nepomuk/repository/main/
Used Soprano Backend=redlandbackend
rebuilt index for type indexing=true
EOT

  # Disable baloo:
  mkdir -p ${LIVE_ROOTDIR}/etc/skel/.kde4/share/apps/config
  cat <<EOT >${LIVE_ROOTDIR}/etc/skel/.kde4/share/apps/config/baloofilerc
[Basic Settings]
Indexing-Enabled=false
EOT

  mkdir -p ${LIVE_ROOTDIR}/etc/skel/.config
  cat <<EOT > ${LIVE_ROOTDIR}/etc/skel/.config/kwalletrc
[Auto Allow]
kdewallet=Network Management,KDE Daemon,KDE Control Module

[Wallet]
Close When Idle=false
Enabled=true
First Use=true
Use One Wallet=true
EOT

  # Start Konsole with a login shell:
  mkdir -p ${LIVE_ROOTDIR}/etc/skel/.kde/share/apps/konsole
  cat <<EOT > ${LIVE_ROOTDIR}/etc/skel/.kde/share/apps/konsole/Shell.profile
[General]
Command=/bin/bash -l
Name=Shell
Parent=FALLBACK/
EOT
  mkdir -p ${LIVE_ROOTDIR}/etc/skel/.config
  cat <<EOT >> ${LIVE_ROOTDIR}/etc/skel/.config/konsolerc
[Desktop Entry]
DefaultProfile=Shell.profile

EOT

  # Configure (default) UTC timezone so we can change it during boot:
  mkdir -p ${LIVE_ROOTDIR}/etc/skel/.kde/share/config
  cat <<EOT > ${LIVE_ROOTDIR}/etc/skel/.kde/share/config/ktimezonedrc
[TimeZones]
LocalZone=UTC
ZoneinfoDir=/usr/share/zoneinfo
Zonetab=/usr/share/zoneinfo/zone.tab
ZonetabCache=
EOT

fi # End KDE4


# Only configure for Plasma5 if it is actually installed:
if [ -d ${LIVE_ROOTDIR}/usr/lib${DIRSUFFIX}/kf5 ]; then

  # -------------------------------------------------------------------------- #
  echo "-- Configuring Plasma5."
  # -------------------------------------------------------------------------- #

  # This section is for any Plasma5 based variant.

  # Install a custom login/desktop/lock background if an image is present:
  plasma5_custom_bg

  # Remove the confusing openbox session if present:
  rm -f ${LIVE_ROOTDIR}/usr/share/xsessions/openbox-session.desktop || true
  # Remove the buggy mediacenter session:
  rm -f ${LIVE_ROOTDIR}/usr/share/xsessions/plasma-mediacenter.desktop || true
  # Remove non-functional wayland session:
  if [ ! -f ${LIVE_ROOTDIR}/usr/lib${DIRSUFFIX}/qt5/bin/qtwaylandscanner ];
  then
    rm -f ${LIVE_ROOTDIR}/usr/share/wayland-sessions/plasmawayland.desktop || true
  fi

  # Remove broken/unwanted shortcuts (discover and konqueror) from taskbar:
  sed -i ${LIVE_ROOTDIR}/usr/share/plasma/plasmoids/org.kde.plasma.taskmanager/contents/config/main.xml \
    -e 's#,applications:org.kde.discover.desktop##' \
    -e s'#,preferred://browser##'

  # Set the OS name to "Slackware Live" in "System Information":
  echo "Name=${DISTRO^} Live" >> ${LIVE_ROOTDIR}/etc/kde/xdg/kcm-about-distrorc

  # Set sane SDDM defaults on first boot (root-owned file):
  mkdir -p ${LIVE_ROOTDIR}/var/lib/sddm
  cat <<EOT > ${LIVE_ROOTDIR}/var/lib/sddm/state.conf 
[Last]
# Name of the last logged-in user.
# This user will be preselected when the login screen appears
User=${LIVEUID}

# Name of the session for the last logged-in user.
# This session will be preselected when the login screen appears.
Session=/usr/share/xsessions/plasma.desktop
EOT
  chroot ${LIVE_ROOTDIR} chown -R sddm:sddm var/lib/sddm

  # Thanks to Fedora Live: https://git.fedorahosted.org/cgit/spin-kickstarts.git
  mkdir -p ${LIVE_ROOTDIR}/etc/skel/.config/akonadi
  mkdir -p ${LIVE_ROOTDIR}/etc/skel/.local/share/akonadi
  mkdir -p ${LIVE_ROOTDIR}/etc/skel/.kde/share/config

  # Configure kdesu to use 'sudo' instead of 'su', so that it will ask
  # for the 'live'password instead of the 'root'password:
  cat <<KDESU_EOF >${LIVE_ROOTDIR}/etc/skel/.config/kdesurc
[super-user-command]
super-user-command=sudo
KDESU_EOF

  # Set akonadi backend:
  cat <<AKONADI_EOF >${LIVE_ROOTDIR}/etc/skel/.config/akonadi/akonadiserverrc
[%General]
Driver=QSQLITE

[QSQLITE]
Name=/home/${LIVEUID}/.local/share/akonadi/akonadi.db
AKONADI_EOF

  # Disable baloo:
  cat <<BALOO_EOF >${LIVE_ROOTDIR}/etc/skel/.config/baloofilerc
[Basic Settings]
Indexing-Enabled=false
BALOO_EOF

  # Disable kres-migrator:
  cat <<KRES_EOF >${LIVE_ROOTDIR}/etc/skel/.kde/share/config/kres-migratorrc
[Migration]
Enabled=false
KRES_EOF

  # Disable kwallet migrator:
  cat <<KWALLET_EOL >${LIVE_ROOTDIR}/etc/skel/.config/kwalletrc
[Migration]
alreadyMigrated=true

KWALLET_EOL

  # Start Konsole with a login shell:
  mkdir -p ${LIVE_ROOTDIR}/etc/skel/.local/share/konsole
  cat <<EOT > ${LIVE_ROOTDIR}/etc/skel/.local/share/konsole/Shell.profile
[Appearance]
ColorScheme=BlackOnWhite

[General]
Command=/bin/bash -l
Name=Shell
Parent=FALLBACK/
TerminalColumns=80
TerminalRows=25

[Interaction Options]
AutoCopySelectedText=true
TrimTrailingSpacesInSelectedText=true
EOT
  mkdir -p ${LIVE_ROOTDIR}/etc/skel/.config
  cat <<EOT >> ${LIVE_ROOTDIR}/etc/skel/.config/konsolerc
[Desktop Entry]
DefaultProfile=Shell.profile

EOT

  # Configure (default) UTC timezone so we can change it during boot:
  mkdir -p ${LIVE_ROOTDIR}/etc/skel/.config
  cat <<EOTZ > ${LIVE_ROOTDIR}/etc/skel/.config/ktimezonedrc
[TimeZones]
LocalZone=UTC
ZoneinfoDir=/usr/share/zoneinfo
Zonetab=/usr/share/zoneinfo/zone.tab
EOTZ

  # Make sure that Plasma and SDDM work on older GPUs,
  # by forcing Qt5 to use software GL rendering:
  cat <<"EOGL" >> ${LIVE_ROOTDIR}/usr/share/sddm/scripts/Xsetup

OPENGL_VERSION=$(LANG=C glxinfo |grep '^OpenGL version string: ' |head -n 1 |sed -e 's/^OpenGL version string: \([0-9]\).*$/\1/g')
if [ "$OPENGL_VERSION" -lt 2 ]; then
  QT_XCB_FORCE_SOFTWARE_OPENGL=1
  export QT_XCB_FORCE_SOFTWARE_OPENGL
fi

EOGL

  # Workaround a bug where SDDM does not always use the configured keymap:
  echo "setxkbmap" >> ${LIVE_ROOTDIR}/usr/share/sddm/scripts/Xsetup

  # Do not show the blueman applet, Plasma5 has its own BlueTooth widget:
  echo "NotShowIn=KDE;" >> ${LIVE_ROOTDIR}/etc/xdg/autostart/blueman.desktop

  # Set QtWebkit as the Konqueror rendering engine if available:
  if [ -f ${LIVE_ROOTDIR}/usr/share/kservices5/kwebkitpart.desktop  ]; then
    mkdir ${LIVE_ROOTDIR}/home/${LIVEUID}/.config
    cat <<EOT >> ${LIVE_ROOTDIR}/home/${LIVEUID}/.config/mimeapps.list
[Added KDE Service Associations]
application/xhtml+xml=kwebkitpart.desktop;
application/xml=kwebkitpart.desktop;
text/html=kwebkitpart.desktop;
EOT
  fi

  # Requirement for Plasma Wayland sessions:
  mkdir -p ${LIVE_ROOTDIR}/etc/profile.d
  cat <<EOT > ${LIVE_ROOTDIR}/etc/profile.d/kwayland.sh
#!/bin/sh
# Force the usage of XCB platform on Qt5 applications:
export QT_QPA_PLATFORM=xcb
# Force the usage of X11 platform for GDK applications:
export GDK_BACKEND=x11
EOT
  cat <<EOT > ${LIVE_ROOTDIR}/etc/profile.d/kwayland.csh
#!/bin/csh
# Force the usage of XCB platform on Qt5 applications:
setenv QT_QPA_PLATFORM xcb
# Force the usage of X11 platform for GDK applications:
setenv GDK_BACKEND x11
EOT
  chmod 755 ${LIVE_ROOTDIR}/etc/profile.d/kwayland.*

fi # End Plasma5

if [ "$LIVEDE" = "DLACK" ]; then

  # -------------------------------------------------------------------------- #
  echo "-- Configuring DLACK."
  # -------------------------------------------------------------------------- #

  # Make sure we start in graphical mode with gdm enabled.
  ln -sf /lib/systemd/system/graphical.target ${LIVE_ROOTDIR}/etc/systemd/system/default.target
  ln -sf /lib/systemd/system/gdm.service ${LIVE_ROOTDIR}/etc/systemd/system/display-manager.service

  # Do not show the blueman applet, Gnome3 has its own BlueTooth widget:
  echo "NotShowIn=GNOME;" >> ${LIVE_ROOTDIR}/etc/xdg/autostart/blueman.desktop

  # Do not start gnome-initial-setup:
  mkdir -p ${LIVE_ROOTDIR}/home/${LIVEUID}/.config
  touch ${LIVE_ROOTDIR}/home/${LIVEUID}/.config/gnome-initial-setup-done

  # Do not let systemd re-generate dynamic linker cache on boot:
  echo "File created by ${MARKER}.  See systemd-update-done.service(8)." \
    |tee ${LIVE_ROOTDIR}/etc/.updated >${LIVE_ROOTDIR}/var/.updated

fi # End LIVEDE = DLACK  

if [ "$LIVEDE" = "DAW" ]; then

  # -------------------------------------------------------------------------- #
  echo "-- Configuring DAW."
  # -------------------------------------------------------------------------- #

  # Stream ALSA through Pulse and all through Jack. This is achieved by
  # having pulseaudio-jack module installed and starting jack-dbus:

  # We default to using a 48000 Hz sample rate throughout, assuming that
  # modern sound hardware will support this, and it lowers the latency:
  if [ -f ${LIVE_ROOTDIR}/etc/pulse/daemon.conf ]; then
    cat <<EOT >> ${LIVE_ROOTDIR}/etc/pulse/daemon.conf
; Run 'pulseaudio --dump-resample-methods' for all possible options.
; We want higher-quality resampling than the default:
resample-method = speex-float-9
; Jack is configured for 48KHz so let's make pulseaudio use it too:
default-sample-rate = 48000
alternate-sample-rate = 44100
EOT
  fi

  mkdir -p ${LIVE_ROOTDIR}/home/${LIVEUID}/.config/rncbc.org
  cat <<EOT > ${LIVE_ROOTDIR}/home/${LIVEUID}/.config/rncbc.org/QjackCtl.conf
[Options]
DBusEnabled=true
GraphButton=true
JackDBusEnabled=true
KeepOnTop=false
PostShutdownScript=true
PostShutdownScriptShell=killall a2jmidid &
PostStartupScript=true
PostStartupScriptShell=/usr/bin/a2jmidid -e &
ServerConfig=true
ServerConfigName=.jackdrc
ShutdownScript=false
ShutdownScriptShell=
Singleton=true
StartJack=true
StartMinimized=true
StartupScript=false
StartupScriptShell=
StopJack=true
SystemTray=true
SystemTrayQueryClose=false
XrunRegex=xrun of at least ([0-9|\\.]+) msecs

[Presets]
DefPreset=(default)

[Settings]
Driver=alsa
Frames=256
MidiDriver=seq
Periods=2
PortMax=256
Priority=5
Realtime=true
SampleRate=48000
Server=jackd
StartDelay=2
Sync=true
EOT

  # Add a default jackd configuration:
  cat <<EOT > ${LIVE_ROOTDIR}/home/${LIVEUID}/.jackdrc
/usr/bin/jackd -dalsa -dhw:0 -r48000 -p1024 -n2
EOT

  # Autostart qjackctl:
  mkdir -p ${LIVE_ROOTDIR}/home/${LIVEUID}/.config/autostart
  if [ -f ${LIVE_ROOTDIR}/usr/share/applications/org.rncbc.qjackctl.desktop ]; then
    QJCDF=/usr/share/applications/org.rncbc.qjackctl.desktop
  else
    QJCDF=/usr/share/applications/qjackctl.desktop
  fi
  cp -a ${LIVE_ROOTDIR}/${QJCDF} \
    ${LIVE_ROOTDIR}/home/${LIVEUID}/.config/autostart/

  # Add all our programs into their own submenu Applications>Multimedia>DAW
  # to avoid clutter in the Multimedia menu. We will use a custom category
  # "X-DAW" to decide what goes into the new submenu.
  # Also move the X42 and LSP Plugin submenus below the new DAW submenu.
  # see https://specifications.freedesktop.org/menu-spec/menu-spec-1.0.html
  # We overwrite the menu entries from the 'daw_base' package,
  # since we want the slightly different liveslak contents instead:
  install -Dm 644 ${LIVE_TOOLDIR}/media/${LIVEDE,,}/menu/liveslak-daw.menu \
    $LIVE_ROOTDIR/etc/xdg/menus/applications-merged/${DISTRO}-daw.menu
  install -Dm 644 \
    ${LIVE_TOOLDIR}/media/${LIVEDE,,}/menu/liveslak-daw.directory \
    $LIVE_ROOTDIR/usr/share/desktop-directories/liveslak-daw.directory
  install -Dm 644 ${LIVE_TOOLDIR}/media/${LIVEDE,,}/menu/liveslak-daw.png \
    -t $LIVE_ROOTDIR/usr/share/icons/hicolor/512x512/apps/

  # Any menu entry that does not yet have a Category "X-DAW" will now have to
  # get that added so that our mew submenu will be populated:
  for DAWPKG in $(cat ${LIVE_TOOLDIR}/pkglists/z03_daw.lst |grep -v x42 |grep -Ev '(^ *#)' ) ; do
    # Find the installed full package name belonging to the DAW package:
    PKGINST=$( ls -1 ${LIVE_ROOTDIR}/var/log/packages/${DAWPKG}* 2>/dev/null |grep -E "/var/log/packages/${DAWPKG}-[^-]+-[^-]+-[^-]+$" || true)
    if [ -n "${PKGINST}" ]; then
      for DESKTOPF in $(grep 'usr/share/applications/.*.desktop' ${PKGINST})
      do
        if ! grep -q X-DAW ${LIVE_ROOTDIR}/${DESKTOPF} ; then
          sed -i ${LIVE_ROOTDIR}/${DESKTOPF} \
            -e "s/^Categories=\(.*\)/Categories=X-DAW;\1/"
        fi
        ## Hide the application in Multimedia (which is based on the AudioVideo
        ## category) to prevent them from getting listed twice:
        #sed -i ${LIVE_ROOTDIR}/${DESKTOPF} -e "/^Categories=/s/AudioVideo;//"
      done
    fi
  done

  # VCV Rack plugins need to be linked into the user-directory to be seen:
  mkdir -p ${LIVE_ROOTDIR}/home/${LIVEUID}/.Rack/plugins-v1
  for PLUGIN in $(find ${LIVE_ROOTDIR}/usr/share/vcvrack/ -type f -name "*.zip" -mindepth 1 -maxdepth 1); do
    ln -s /usr/share/vcvrack/$(basename ${PLUGIN}) ${LIVE_ROOTDIR}/home/${LIVEUID}/.Rack/plugins-v1/
  done

  # The new Kickoff application launcher that replaced the old Kickoff,
  # does not adhere to the XDG Desktop standards.
  # Therefore we will switch the DAW desktop to Kicker instead, to preserve
  # our 'Slackware DAW' menu structure in the 'Multimedia' menu:
  sed -e 's/kickoff/kicker/g' -i ${LIVE_ROOTDIR}/usr/share/plasma/layout-templates/org.kde.plasma.desktop.defaultPanel/contents/layout.js

fi # End LIVEDE = DAW

if [ "$LIVEDE" = "STUDIOWARE" ]; then

  # -------------------------------------------------------------------------- #
  echo "-- Configuring STUDIOWARE."
  # -------------------------------------------------------------------------- #

  # Create group and user for the Avahi service:
  chroot ${LIVE_ROOTDIR} /usr/sbin/groupadd -g 214 avahi
  chroot ${LIVE_ROOTDIR} /usr/sbin/useradd -c "Avahi Service Account" -u 214 -g 214 -d /dev/null -s /bin/false avahi
  if ! echo "avahi:$(openssl rand -base64 12)" | /usr/sbin/chpasswd -R ${LIVE_ROOTDIR} 2>/dev/null ; then
    echo "avahi:$(openssl rand -base64 12)" | chroot ${LIVE_ROOTDIR} /usr/sbin/chpasswd
  fi

fi # End LIVEDE = STUDIOWARE

if [ "$LIVEDE" = "DAW" -o "$LIVEDE" = "STUDIOWARE" ];
then

  # -------------------------------------------------------------------------- #
  echo "-- Configuring $LIVEDE (RT behaviour)."
  # -------------------------------------------------------------------------- #

  # Install real-time configuration in case the OS-installed packages
  # have not yet done this for us ('daw_base' for instance).
  # The script looks for specific filenames as used in 'daw_base':
  #   /etc/security/limits.d/rt_audio.conf
  #   /etc/sysctl.d/daw.conf
  #   /etc/udev/rules.d/40-timer-permissions.rules

  # RT Scheduling and Locked Memory:
  # Implementation depends on whether PAM is installed:
  if [ -L ${LIVE_ROOTDIR}/lib${DIRSUFFIX}/libpam.so.? ]; then
    if [ ! -f ${LIVE_ROOTDIR}/etc/security/limits.d/rt_audio.conf ]; then
      # On PAM based OS, allow user in 'audio' group to invoke rt capability:
      mkdir -p ${LIVE_ROOTDIR}/etc/security/limits.d
      cat <<EOT > ${LIVE_ROOTDIR}/etc/security/limits.d/rt_audio.conf
# Realtime capability allowed for user in the 'audio' group:
# Use 'unlimited' with care, you can lock up your system when app misbehaves:
#@audio   -  memlock    2097152
@audio   -  memlock    unlimited
@audio   -  rtprio     95
EOT
    fi
  else
    cat << "EOT" > ${LIVE_ROOTDIR}/etc/initscript
# Set umask to safe level:
umask 022
# Disable core dumps:
ulimit -c 0
# Allow unlimited size to be locked into memory:
ulimit -l unlimited
# Address issue of jackd failing to start with realtime scheduling:
ulimit -r 95

# Execute the program.
eval exec "$4"
EOT
    chmod +x ${LIVE_ROOTDIR}/etc/initscript
  fi

  if [ ! -f ${LIVE_ROOTDIR}/etc/udev/rules.d/40-timer-permissions.rules ]; then
    # Allow access for 'audio' group to the high precision event timer,
    # which may benefit a DAW which relies on ALSA MIDI;
    # Also grant write access to /dev/cpu_dma_latency to prevent CPU's
    # from going into idle state:
    mkdir -p ${LIVE_ROOTDIR}/etc/udev/rules.d
    cat <<EOT > ${LIVE_ROOTDIR}/etc/udev/rules.d/40-timer-permissions.rules
KERNEL=="rtc0", GROUP="audio"
KERNEL=="hpet", GROUP="audio"
KERNEL=="cpu_dma_latency", GROUP="audio"
EOT
  fi

  if [ ! -f ${LIVE_ROOTDIR}/etc/sysctl.d/daw.conf ]; then
    # Audio related sysctl settings for better realtime performance:
    mkdir -p ${LIVE_ROOTDIR}/etc/sysctl.d
    cat <<EOT > ${LIVE_ROOTDIR}/etc/sysctl.d/daw.conf
# https://wiki.linuxaudio.org/wiki/system_configuration
dev.hpet.max-user-freq = 3072
fs.inotify.max_user_watches = 524288
vm.swappiness = 10
EOT
  fi

  #  # This would benefit a DAW, but if the user runs the Live OS on a laptop,
  #  # she might want to decide about this herself:
  #  mkdir -p ${LIVE_ROOTDIR}/etc/default
  #cat <<EOT > ${LIVE_ROOTDIR}/etc/default/cpufreq
  #SCALING_GOVERNOR=performance
  #EOT

fi # End LIVEDE = DAW/STUDIOWARE

# You can define the function 'custom_config()' by uncommenting it in
# the configuration file 'make_slackware_live.conf'.
if type custom_config 1>/dev/null 2>/dev/null ; then

  # -------------------------------------------------------------------------- #
  echo "-- Configuring ${LIVEDE} by calling 'custom_config()'."
  # -------------------------------------------------------------------------- #

  # This is particularly useful if you defined a non-standard "LIVEDE"
  # in 'make_slackware_live.conf', in which case you must specify your custom
  # package sequence in the variable "SEQ_CUSTOM" in that same .conf file.
  custom_config

fi

# Workaround a bug where our Xkbconfig is not loaded sometimes:
echo "setxkbmap" > ${LIVE_ROOTDIR}/home/${LIVEUID}/.xprofile

# Give the live user a copy of our XFCE (and more) skeleton configuration:
cd ${LIVE_ROOTDIR}/etc/skel/
  find . -exec cp -a --parents "{}" ${LIVE_ROOTDIR}/home/${LIVEUID}/ \;
  find ${LIVE_ROOTDIR}/home/${LIVEUID}/ -type f -exec sed -i -e "s,/home/live,/home/${LIVEUID}," "{}" \;
cd - 1>/dev/null

if [ "${ADD_CACERT}" = "YES" -o "${ADD_CACERT}" = "yes" ]; then
  echo "-- Importing CACert root certificates into OS and browsers."
  # Import CACert root certificates into the OS:
  ( mkdir -p ${LIVE_ROOTDIR}/etc/ssl/certs
    cd ${LIVE_ROOTDIR}/etc/ssl/certs
    wget -q -O cacert-root.crt http://www.cacert.org/certs/root.crt
    wget -q -O cacert-class3.crt http://www.cacert.org/certs/class3.crt
    ln -s cacert-root.crt \
      $(openssl x509 -noout -hash -in cacert-root.crt).0
    ln -s cacert-class3.crt \
      $(openssl x509 -noout -hash -in cacert-class3.crt).0
  )

  # Create Mozilla Firefox profile:
  mkdir -p ${LIVE_ROOTDIR}/home/${LIVEUID}/.mozilla/firefox/${LIVEUID}_profile.default
  cat << EOT > ${LIVE_ROOTDIR}/home/${LIVEUID}/.mozilla/firefox/profiles.ini
[General]
StartWithLastProfile=1

[Profile0]
Name=default
IsRelative=1
Path=${LIVEUID}_profile.default
Default=1
EOT

  # Create Mozilla Seamonkey profile:
  mkdir -p ${LIVE_ROOTDIR}/home/${LIVEUID}/.mozilla/seamonkey/${LIVEUID}_profile.default
  cat << EOT > ${LIVE_ROOTDIR}/home/${LIVEUID}/.mozilla/seamonkey/profiles.ini
[General]
StartWithLastProfile=1

[Profile0]
Name=default
IsRelative=1
Path=${LIVEUID}_profile.default
Default=1
EOT

  # Create Pale Moon profile:
  mkdir -p ${LIVE_ROOTDIR}/home/${LIVEUID}/.moonchild\ productions/pale\ moon/${LIVEUID}_profile.default
    cat << EOT > ${LIVE_ROOTDIR}/home/${LIVEUID}/.moonchild\ productions/pale\ moon/profiles.ini
[General]
StartWithLastProfile=1

[Profile0]
Name=default
IsRelative=1
Path=${LIVEUID}_profile.default
Default=1
EOT

  # Import CACert root certificates into the browsers:
  (
    # Mozilla Firefox:
    certutil -N --empty-password -d ${LIVE_ROOTDIR}/home/${LIVEUID}/.mozilla/firefox/${LIVEUID}_profile.default
    certutil -d ${LIVE_ROOTDIR}/home/${LIVEUID}/.mozilla/firefox/${LIVEUID}_profile.default \
      -A -t TC -n "CAcert.org" -i ${LIVE_ROOTDIR}/etc/ssl/certs/cacert-root.crt
    certutil -d ${LIVE_ROOTDIR}/home/${LIVEUID}/.mozilla/firefox/${LIVEUID}_profile.default \
      -A -t TC -n "CAcert.org Class 3" -i ${LIVE_ROOTDIR}/etc/ssl/certs/cacert-class3.crt
    # Seamonkey and Pale Moon (can just be a copy of the Firefox files):
    cp -a \
      ${LIVE_ROOTDIR}/home/${LIVEUID}/.mozilla/firefox/${LIVEUID}_profile.default/* \
      ${LIVE_ROOTDIR}/home/${LIVEUID}/.mozilla/seamonkey/${LIVEUID}_profile.default/
    cp -a \
      ${LIVE_ROOTDIR}/home/${LIVEUID}/.mozilla/firefox/${LIVEUID}_profile.default/* \
      ${LIVE_ROOTDIR}/home/${LIVEUID}/.moonchild\ productions/pale\ moon/${LIVEUID}_profile.default/
    # NSS databases for Chrome based browsers have a different format (sql)
    # than Mozilla based browsers:
    mkdir -p ${LIVE_ROOTDIR}/home/${LIVEUID}/.pki/nssdb
    certutil -N --empty-password -d ${LIVE_ROOTDIR}/home/${LIVEUID}/.pki/nssdb
    certutil -d sql:${LIVE_ROOTDIR}/home/${LIVEUID}/.pki/nssdb \
      -A -t TC -n "CAcert.org" -i ${LIVE_ROOTDIR}/etc/ssl/certs/cacert-root.crt
    certutil -d sql:${LIVE_ROOTDIR}/home/${LIVEUID}/.pki/nssdb \
      -A -t TC -n "CAcert.org Class 3" -i ${LIVE_ROOTDIR}/etc/ssl/certs/cacert-class3.crt
  )
  # TODO: find out how to configure KDE with additional Root CA's.
fi # End ADD_CACERT

# Make sure that user 'live' owns her own files:
chroot ${LIVE_ROOTDIR} chown -R ${LIVEUID}:users home/${LIVEUID}

# -------------------------------------------------------------------------- #
echo "-- Tweaking system startup."
# -------------------------------------------------------------------------- #

# Configure the default DE when running startx:
if [ "$LIVEDE" = "MATE" ]; then
  ln -sf xinitrc.mate-session ${LIVE_ROOTDIR}/etc/X11/xinit/xinitrc
elif [ "$LIVEDE" = "CINNAMON" ]; then
  ln -sf xinitrc.cinnamon-session ${LIVE_ROOTDIR}/etc/X11/xinit/xinitrc
elif [ "$LIVEDE" = "DLACK" ]; then
  ln -sf xinitrc.gnome ${LIVE_ROOTDIR}/etc/X11/xinit/xinitrc
elif [ -f ${LIVE_ROOTDIR}/etc/X11/xinit/xinitrc.kde ]; then
  ln -sf xinitrc.kde ${LIVE_ROOTDIR}/etc/X11/xinit/xinitrc
elif [ -f ${LIVE_ROOTDIR}/etc/X11/xinit/xinitrc.xfce ]; then
  ln -sf xinitrc.xfce ${LIVE_ROOTDIR}/etc/X11/xinit/xinitrc
fi

# Configure the default runlevel:
sed -i ${LIVE_ROOTDIR}/etc/inittab -e "s/\(id:\).\(:initdefault:\)/\1${RUNLEVEL}\2/"

# Disable unneeded/unwanted services:
[ -f ${LIVE_ROOTDIR}/etc/rc.d/rc.acpid ] && chmod -x ${LIVE_ROOTDIR}/etc/rc.d/rc.acpid
[ -f ${LIVE_ROOTDIR}/etc/rc.d/rc.pcmcia ] && chmod -x ${LIVE_ROOTDIR}/etc/rc.d/rc.pcmcia
[ -f ${LIVE_ROOTDIR}/etc/rc.d/rc.pulseaudio ] && chmod -x ${LIVE_ROOTDIR}/etc/rc.d/rc.pulseaudio
[ -f ${LIVE_ROOTDIR}/etc/rc.d/rc.yp ] && chmod -x ${LIVE_ROOTDIR}/etc/rc.d/rc.yp
[ -f ${LIVE_ROOTDIR}/etc/rc.d/rc.sshd ] && chmod -x ${LIVE_ROOTDIR}/etc/rc.d/rc.sshd

# But enable NFS client support and CUPS:
[ -f ${LIVE_ROOTDIR}/etc/rc.d/rc.rpc ] && chmod +x ${LIVE_ROOTDIR}/etc/rc.d/rc.rpc
if [ -x ${LIVE_ROOTDIR}/usr/sbin/cupsd ] && [ -f ${LIVE_ROOTDIR}/etc/rc.d/rc.cups ]; then
  chmod +x ${LIVE_ROOTDIR}/etc/rc.d/rc.cups
fi
if [ -x ${LIVE_ROOTDIR}/usr/sbin/cupsd ] && [ -f ${LIVE_ROOTDIR}/etc/rc.d/rc.cups-browsed ]; then
  chmod +x ${LIVE_ROOTDIR}/etc/rc.d/rc.cups-browsed
fi

# Add a softvol pre-amp to ALSA - some computers have too low volumes.
# If etc/asound.conf exists it's configuring ALSA to use Pulse,
# so in that case the pre-amp is not needed:
if [ ! -f ${LIVE_ROOTDIR}/etc/asound.conf ]; then
  cat <<EOAL > ${LIVE_ROOTDIR}/etc/asound.conf
pcm.!default {
  type asym
  playback.pcm "plug:softvol"
  capture.pcm "plug:dsnoop"
}

pcm.softvol {
  type softvol
  slave.pcm "dmix"
  control { name "PCM"; card 0; }
  max_dB 32.0
}
EOAL
else
  if ! grep -q sysdefault ${LIVE_ROOTDIR}/etc/asound.conf ; then
    # If pulse is used, configure a fallback to use the system default
    # or else there will not be sound on first boot:
    sed -i ${LIVE_ROOTDIR}/etc/asound.conf \
        -e '/type pulse/ a \ \ fallback "sysdefault"'
  fi
fi

# Skip all filesystem checks at boot:
touch ${LIVE_ROOTDIR}/etc/fastboot

# We will not write to the hardware clock:
sed -i -e '/systohc/s/^/# /' ${LIVE_ROOTDIR}/etc/rc.d/rc.6

# Run some package setup scripts (usually run by the slackware installer),
# as well as some of the delaying commands in rc.M and rc.modules:

chroot ${LIVE_ROOTDIR} /bin/bash <<EOCR
# Run bits from rc.M so we won't need to run them again in the live system:
/sbin/depmod $KVER
/sbin/ldconfig
EOCR

chroot ${LIVE_ROOTDIR} /bin/bash <<EOCR
# Update the desktop database:
if [ -x /usr/bin/update-desktop-database ]; then
  /usr/bin/update-desktop-database /usr/share/applications > /dev/null 2>${DBGOUT}
fi

# Update hicolor theme cache:
if [ -d /usr/share/icons/hicolor ]; then
  if [ -x /usr/bin/gtk-update-icon-cache ]; then
    /usr/bin/gtk-update-icon-cache -f -t /usr/share/icons/hicolor 1>/dev/null 2>${DBGOUT}
  fi
fi

# Update the mime database:
if [ -x /usr/bin/update-mime-database ]; then
  /usr/bin/update-mime-database /usr/share/mime >/dev/null 2>${DBGOUT}
fi

# Font configuration:
if [ -x /usr/bin/fc-cache ]; then
  for fontdir in 100dpi 75dpi OTF Speedo TTF Type1 cyrillic ; do
    if [ -d /usr/share/fonts/\$fontdir ]; then
      mkfontscale /usr/share/fonts/\$fontdir 1>/dev/null 2>${DBGOUT}
      mkfontdir /usr/share/fonts/\$fontdir 1>/dev/null 2>${DBGOUT}
    fi
  done
  if [ -d /usr/share/fonts/misc ]; then
    mkfontscale /usr/share/fonts/misc  1>/dev/null 2>${DBGOUT}
    mkfontdir -e /usr/share/fonts/encodings -e /usr/share/fonts/encodings/large /usr/share/fonts/misc 1>/dev/null 2>${DBGOUT}
  fi
  /usr/bin/fc-cache -f 1>/dev/null 2>${DBGOUT}
fi

if [ -x /usr/bin/update-gtk-immodules ]; then
  /usr/bin/update-gtk-immodules
fi
if [ -x /usr/bin/update-gdk-pixbuf-loaders ]; then
  /usr/bin/update-gdk-pixbuf-loaders
fi
if [ -x /usr/bin/update-pango-querymodules ]; then
  /usr/bin/update-pango-querymodules
fi

if [ -x /usr/bin/glib-compile-schemas ]; then
  /usr/bin/glib-compile-schemas /usr/share/glib-2.0/schemas >/dev/null 2>${DBGOUT}
fi

# Delete unwanted cache files:
if [ -d usr/share/icons ]; then
  find usr/share/icons -name icon-theme.cache -exec rm "{}" \;
fi
EOCR

# Disable above commands in rc.M and rc.modules:
sed -e "s% /usr/bin/update.*verbose%#&%" -i ${LIVE_ROOTDIR}/etc/rc.d/rc.M 
sed -e '/^ *\/usr\/bin\/glib-c/ s, /usr/bin/glib-c,#&,' -i ${LIVE_ROOTDIR}/etc/rc.d/rc.M
sed -e "s% /sbin/depmod -%#&%" -i ${LIVE_ROOTDIR}/etc/rc.d/rc.modules 

# Start/stop the NVIDIA persistence daemon if a NVIDIA driver is loaded;
# Note that this assumes the nvidia-driver and nvidia-kernel packages
# from slackbuilds.org are being used:
cat <<EOT >> ${LIVE_ROOTDIR}/etc/rc.d/rc.local

# For CUDA/OpenCL to work after reboot, create missing nvidia device nodes:
if [ -x /usr/bin/nvidia-modprobe ]; then
  echo "Creating missing nvidia device nodes..."
  /usr/bin/nvidia-modprobe -c 0 -u
fi

# Start avahi daemon:
if [ -x /etc/rc.d/rc.avahidaemon ]; then
  echo "Starting Avahi Daemon..."
  /etc/rc.d/rc.avahidaemon start
fi

# Start avahidnsconfd:
if [ -x /etc/rc.d/rc.avahidnsconfd ]; then
  echo "Starting Avahi DNS Confd..."
  /etc/rc.d/rc.avahidnsconfd start
fi

# Start the nvidia-persistenced daemon:
if  [ -x /etc/rc.d/rc.nvidia-persistenced ] && [ -d /var/run/nvidia-persistenced ]; then
  echo "Starting nvidia persistence daemon..."
  sed -e "s/NVPD_USER=.*/NVPD_USER=${NVUID}/" -i /etc/rc.d/rc.nvidia-persistenced
  chown ${NVUID}:${NVGRP} /var/run/nvidia-persistenced 2>/dev/null
  /etc/rc.d/rc.nvidia-persistenced start
fi
EOT

cat <<EOT >> ${LIVE_ROOTDIR}/etc/rc.d/rc.local_shutdown

# Stop avahidnsconfd
if [ -x /etc/rc.d/rc.avahidnsconfd ]; then
  echo "Stopping Avahi DNS Confd..."
  /etc/rc.d/rc.avahidnsconfd stop
fi

# Stop avahidaemon
if [ -x /etc/rc.d/rc.avahidaemon ]; then
  echo "Stopping Avahi Daemon..."
  /etc/rc.d/rc.avahidaemon stop
fi

# Stop the nvidia-persistenced daemon:
if  [ -x /etc/rc.d/rc.nvidia-persistenced ]; then
  echo "Stopping nvidia persistence daemon..."
  /etc/rc.d/rc.nvidia-persistenced stop
fi
EOT

# Clean out the unneeded stuff:
# Note: this will fail when a directory is encountered. This failure points
# to a packaging issue; find and fix the responsible package.
rm -f ${LIVE_ROOTDIR}/tmp/[A-Za-z]*
rm -f ${LIVE_ROOTDIR}/var/mail/*
rm -f ${LIVE_ROOTDIR}/root/.bash*

# Create a locate cache:
echo "-- Creating locate cache, takes a few seconds..."
if [ -x ${LIVE_ROOTDIR}/etc/cron.daily/mlocate ]; then
  LOCATE_BIN=mlocate
else
  LOCATE_BIN=slocate
fi
chroot ${LIVE_ROOTDIR} /etc/cron.daily/${LOCATE_BIN} 2>${DBGOUT}

# -----------------------------------------------------------------------------
# Done with configuring the live system!
# -----------------------------------------------------------------------------

# Squash the configuration into its own module:
umount ${LIVE_ROOTDIR} 2>${DBGOUT} || true
mksquashfs ${INSTDIR} ${LIVE_MOD_SYS}/0099-${DISTRO}_zzzconf-${SL_VERSION}-${SL_ARCH}.sxz -noappend -comp ${SQ_COMP} ${SQ_COMP_PARAMS}
rm -rf ${INSTDIR}/*

# End result: we have our .sxz file and the INSTDIR is empty again,
# Next step is to loop-mount the squashfs file onto INSTDIR.

# Add the system configuration tree to the readonly lowerdirs for the overlay:
RODIRS="${INSTDIR}:${RODIRS}"

# Mount the module for use in the final assembly of the ISO:
mount -t squashfs -o loop ${LIVE_MOD_SYS}/0099-${DISTRO}_zzzconf-${SL_VERSION}-${SL_ARCH}.sxz ${INSTDIR}

unset INSTDIR

# -----------------------------------------------------------------------------
# Prepare the system for live booting.
# -----------------------------------------------------------------------------

echo "-- Preparing the system for live booting."
umount ${LIVE_ROOTDIR} 2>${DBGOUT} || true
mount -t overlay -o lowerdir=${RODIRS%:*},upperdir=${LIVE_BOOT},workdir=${LIVE_OVLDIR} overlay ${LIVE_ROOTDIR}

mount --bind /proc ${LIVE_ROOTDIR}/proc
mount --bind /sys ${LIVE_ROOTDIR}/sys
mount --bind /dev ${LIVE_ROOTDIR}/dev

# Determine the installed kernel version:
if [ "$SL_ARCH" = "x86_64" -o "$SMP32" = "NO" ]; then
  KGEN=$(ls --indicator-style=none ${LIVE_ROOTDIR}/var/log/packages/kernel*modules* |grep -v smp |head -1 |rev | cut -d- -f3 |tr _ - |rev)
  KVER=$(ls --indicator-style=none ${LIVE_ROOTDIR}/lib/modules/ |grep -v smp |head -1)
else
  KGEN=$(ls --indicator-style=none ${LIVE_ROOTDIR}/var/log/packages/kernel*modules* |grep smp |head -1 |rev | cut -d- -f3 |tr _ - |rev)
  KVER=$(ls --indicator-style=none ${LIVE_ROOTDIR}/lib/modules/ |grep smp |head -1)
fi

# Determine Slackware's GRUB version and build (we will use this later):
GRUBVER=$(find ${DEF_SL_PKGROOT}/../ -name "grub-*.t?z" |rev |cut -d- -f3 |rev)
GRUBBLD=$(find ${DEF_SL_PKGROOT}/../ -name "grub-*.t?z" |rev |cut -d- -f1 |cut -d. -f2 |rev)

# Create an initrd for the generic kernel, using a modified init script:
echo "-- Creating initrd for kernel-generic $KVER ..."
chroot ${LIVE_ROOTDIR} /sbin/mkinitrd -c -w ${WAIT} -l us -o /boot/initrd_${KVER}.img -k ${KVER} -m ${KMODS} -L -C dummy 1>${DBGOUT} 2>${DBGOUT}
# Modify the initrd content for the Live OS.
# Note: 'upslak.sh' needs to be updated when this 'cat' command changes:
cat $LIVE_TOOLDIR/liveinit.tpl | sed \
  -e "s/@LIVEMAIN@/$LIVEMAIN/g" \
  -e "s/@MARKER@/$MARKER/g" \
  -e "s/@MEDIALABEL@/$MEDIALABEL/g" \
  -e "s/@PERSISTENCE@/$PERSISTENCE/g" \
  -e "s/@DARKSTAR@/$LIVE_HOSTNAME/g" \
  -e "s/@LIVEUID@/$LIVEUID/g" \
  -e "s/@DISTRO@/$DISTRO/g" \
  -e "s/@CDISTRO@/${DISTRO^}/g" \
  -e "s/@UDISTRO@/${DISTRO^^}/g" \
  -e "s/@CORE2RAMMODS@/${CORE2RAMMODS}/g" \
  -e "s/@VERSION@/${VERSION}/g" \
  -e "s/@SQ_EXT_AVAIL@/${SQ_EXT_AVAIL}/g" \
  -e "s,@DEF_KBD@,${DEF_KBD},g" \
  -e "s,@DEF_LOCALE@,${DEF_LOCALE},g" \
  -e "s,@DEF_TZ@,${DEF_TZ},g" \
  > ${LIVE_ROOTDIR}/boot/initrd-tree/init
cat /dev/null > ${LIVE_ROOTDIR}/boot/initrd-tree/luksdev
# We do not add openobex to the initrd and don't want to see irrelevant errors:
rm ${LIVE_ROOTDIR}/boot/initrd-tree/lib/udev/rules.d/*openobex*rules 2>${DBGOUT} || true
# Add dhcpcd for NFS root support (just to have it - even if we won't need it):
DHCPD_PKG=$(find ${DEF_SL_PKGROOT}/../ -name "dhcpcd-*.t?z" |head -1)
tar -C ${LIVE_ROOTDIR}/boot/initrd-tree/ -xf ${DHCPD_PKG} \
  var/lib/dhcpcd lib/dhcpcd sbin/dhcpcd usr/lib${DIRSUFFIX}/dhcpcd \
  etc/dhcpcd.conf.new
mv ${LIVE_ROOTDIR}/boot/initrd-tree/etc/dhcpcd.conf{.new,}
# Add getfattr to read extended attributes (even if we won't need it):
ATTR_PKG=$(find ${DEF_SL_PKGROOT}/../ -name "attr-*.t?z" |head -1)
tar --wildcards -C ${LIVE_ROOTDIR}/boot/initrd-tree/ -xf ${ATTR_PKG} \
  lib${DIRSUFFIX}/libattr.so.* usr/bin/getfattr
# Generate library symlinks for libattr (getfattr depends on them):
( cd ${LIVE_ROOTDIR}/boot/initrd-tree/lib${DIRSUFFIX} ; ldconfig -n . )
# Stamp the Slackware version into the initrd (at least dhcpcd needs this):
mkdir -p ${LIVE_ROOTDIR}/boot/initrd-tree/etc/rc.d
cp -a ${LIVE_ROOTDIR}/etc/slackware-version ${LIVE_ROOTDIR}/etc/os-release \
  ${LIVE_ROOTDIR}/boot/initrd-tree/etc/
if [ "$NFSROOTSUP" = "YES" ]; then
  # Add just the right kernel network modules by pruning unneeded stuff:
  # We need the full kernel-modules package for deps resolving:
  # Get the kernel modules:
  for NETMODPATH in ${NETMODS} ; do 
    cd ${LIVE_ROOTDIR}
      cp -a --parents lib/modules/${KVER}/${NETMODPATH} \
        ${LIVE_ROOTDIR}/boot/initrd-tree/
    cd - 1>/dev/null
    # Prune the ones we do not need:
    for KNETRM in ${NETEXCL} ; do
      find ${LIVE_ROOTDIR}/boot/initrd-tree/lib/modules/${KVER}/${NETMODPATH} \
        -name $KNETRM -depth -exec rm -rf {} \;
    done
    # Add any dependency modules:
    for MODULE in $(find ${LIVE_ROOTDIR}/boot/initrd-tree/lib/modules/${KVER}/${NETMODPATH} -type f -exec basename {} .ko \;) ; do
      /sbin/modprobe --dirname ${LIVE_ROOTDIR} --set-version $KVER --show-depends --ignore-install $MODULE 2>/dev/null |grep "^insmod " |cut -f 2 -d ' ' |while read SRCMOD; do
        if [ "$(basename $SRCMOD .ko)" != "$MODULE" ]; then
          cd ${LIVE_ROOTDIR}
            # Need to strip ${LIVE_ROOTDIR} from the start of ${SRCMOD}:
            cp -a --parents $(echo $SRCMOD |sed 's|'${LIVE_ROOTDIR}'/|./|' ) \
              ${LIVE_ROOTDIR}/boot/initrd-tree/
          cd - 1>/dev/null
        fi
      done
    done
  done
  # We added extra modules to the initrd, so we run depmod again:
  chroot ${LIVE_ROOTDIR}/boot/initrd-tree /sbin/depmod $KVER
  # Add the firmware for network cards that need them:
  KFW_PKG=$(find ${DEF_SL_PKGROOT}/../ -name "kernel-firmware-*.t?z" |head -1)
  tar tf ${KFW_PKG} |grep -E "($(echo $NETFIRMWARE |tr ' ' '|'))" \
    |xargs tar -C ${LIVE_ROOTDIR}/boot/initrd-tree/ -xf ${KFW_PKG} \
    2>/dev/null || true
fi
# Wrap up the initrd.img again:
( cd ${LIVE_ROOTDIR}/boot/initrd-tree
  find . | cpio -o -H newc | $COMPR >${LIVE_ROOTDIR}/boot/initrd_${KVER}.img 2>${DBGOUT}
)
rm -rf ${LIVE_ROOTDIR}/boot/initrd-tree

# ... and cleanup these mounts again:
umount ${LIVE_ROOTDIR}/{proc,sys,dev} || true
umount ${LIVE_ROOTDIR} || true
# Paranoia:
[ ! -z "${LIVE_BOOT}" ] && rm -rf ${LIVE_BOOT}/{etc,tmp,usr,var} 1>${DBGOUT} 2>${DBGOUT}

# Copy kernel and move the modified initrd (we do not need it in the Live OS).
# Note to self: syslinux does not 'see' files unless they are DOS 8.3 names?
rm -rf ${LIVE_STAGING}/boot
mkdir -p ${LIVE_STAGING}/boot
cp -a ${LIVE_BOOT}/boot/vmlinuz-generic*-$KGEN ${LIVE_STAGING}/boot/generic
mv ${LIVE_BOOT}/boot/initrd_${KVER}.img ${LIVE_STAGING}/boot/initrd.img

# Squash the boot directory into its own module:
mksquashfs ${LIVE_BOOT} ${LIVE_MOD_SYS}/0000-${DISTRO}_boot-${SL_VERSION}-${SL_ARCH}.sxz -noappend -comp ${SQ_COMP} ${SQ_COMP_PARAMS}

# Determine additional boot parameters to be added:
if [ -z ${KAPPEND} ]; then
  eval KAPPEND=\$KAPPEND_${LIVEDE}
fi

# Copy the syslinux configuration.
# The next block checks here for a possible UEFI grub boot image:
cp -a ${LIVE_TOOLDIR}/syslinux ${LIVE_STAGING}/boot/

# EFI support always for 64bit architecture, but conditional for 32bit.
if [ "$SL_ARCH" = "x86_64" -o "$EFI32" = "YES" ]; then
  # Copy the UEFI boot directory structure:
  rm -rf ${LIVE_STAGING}/EFI/BOOT
  mkdir -p ${LIVE_STAGING}/EFI/BOOT
  cp -a ${LIVE_TOOLDIR}/EFI/BOOT/{grub-embedded.cfg,make-grub.sh,*.txt,theme} ${LIVE_STAGING}/EFI/BOOT/
  if [ ${SECUREBOOT} -eq 1 ]; then
    # User needs a DER-encoded copy of the signing cert for MOK enrollment:
    openssl x509 -outform der -in ${MOKCERT} -out ${LIVE_STAGING}/EFI/BOOT/liveslak.der
  fi
  if [ "$LIVEDE" = "XFCE" ]; then
    # We do not use the unicode font, so it can be removed to save space:
    rm -f ${LIVE_STAGING}/EFI/BOOT/theme/unicode.pf2
  fi

  # Create the grub fonts used in the theme.
  # Command outputs string like this: "Font name: DejaVu Sans Mono Regular 5".
  for FSIZE in 5 10 12 20 ; do
    grub-mkfont -s ${FSIZE} -av \
      -o ${LIVE_STAGING}/EFI/BOOT/theme/dejavusansmono${FSIZE}.pf2 \
      /usr/share/fonts/TTF/DejaVuSansMono.ttf \
      | grep "^Font name: "
  done

  # The grub-embedded.cfg in the bootx64.efi/bootia32.efi looks for this file:
  touch ${LIVE_STAGING}/EFI/BOOT/${MARKER}

  # Generate the UEFI grub boot image if needed:
  if [ ! -f ${LIVE_STAGING}/EFI/BOOT/boot${EFISUFF}.efi -o ! -f ${LIVE_STAGING}/boot/syslinux/efiboot.img ]; then
    ( cd ${LIVE_STAGING}/EFI/BOOT
      # Create a SBAT file 'grub_sbat.csv' to be used by make-grub.sh :
      cat <<HSBAT > ${LIVE_STAGING}/EFI/BOOT/grub_sbat.csv
sbat,1,SBAT Version,sbat,1,https://github.com/rhboot/shim/blob/main/SBAT.md
grub,1,Free Software Foundation,grub,2.06,https://www.gnu.org/software/grub/
grub.liveslak,1,The liveslak project,grub,${GRUBVER}-${GRUBBLD},https://download.liveslak.org/
HSBAT
      sed -i -e "s/SLACKWARELIVE/${MARKER}/g" grub-embedded.cfg
      sh make-grub.sh EFIFORM=${EFIFORM} EFISUFF=${EFISUFF}
    )
  fi

  # Generate the grub configuration for UEFI boot:
  gen_uefimenu ${LIVE_STAGING}/EFI/BOOT

  # Add SecureBoot support if requested:
  if [ ${SECUREBOOT} -eq 1 ]; then
    secureboot ${SHIM_3RDP}
  fi

fi # End EFI support menu.

if [ "$SYSMENU" = "NO" ]; then
  # Simple isolinux choices, no UEFI support.
  echo "include syslinux.cfg" > ${LIVE_STAGING}/boot/syslinux/isolinux.cfg
else
  # NOTE: Convert a PNG image to VESA bitmap before using it with vesamenu:
  # $ convert -depth 16 -colors 65536 in.png out.png
  cp -a /usr/share/syslinux/vesamenu.c32 ${LIVE_STAGING}/boot/syslinux/
  echo "include menu/vesamenu.cfg" > ${LIVE_STAGING}/boot/syslinux/isolinux.cfg
  # Generate the multi-language menu:
  gen_bootmenu ${LIVE_STAGING}/boot/syslinux
fi
for SLFILE in message.txt f2.txt syslinux.cfg lang.cfg ; do
  if [ -f ${LIVE_STAGING}/boot/syslinux/${SLFILE} ]; then
    sed -i ${LIVE_STAGING}/boot/syslinux/${SLFILE} \
      -e "s/@DIRSUFFIX@/$DIRSUFFIX/g" \
      -e "s/@DISTRO@/$DISTRO/g" \
      -e "s/@CDISTRO@/${DISTRO^}/g" \
      -e "s/@UDISTRO@/${DISTRO^^}/g" \
      -e "s/@KVER@/$KVER/g" \
      -e "s/@LIVEMAIN@/$LIVEMAIN/g" \
      -e "s/@MEDIALABEL@/$MEDIALABEL/g" \
      -e "s/@LIVEDE@/$(echo $LIVEDE |sed 's/BASE//')/g" \
      -e "s/@SL_VERSION@/$SL_VERSION/g"
  fi
done
# The iso2usb.sh script can use this copy of a MBR file as fallback:
cp -a /usr/share/syslinux/gptmbr.bin ${LIVE_STAGING}/boot/syslinux/
# We have memtest in the syslinux bootmenu:
mv ${LIVE_STAGING}/boot/syslinux/memtest ${LIVE_STAGING}/boot/

# Make use of proper console font if we have it available:
if [ -f /usr/share/kbd/consolefonts/${CONSFONT}.gz ]; then
  gunzip -cd /usr/share/kbd/consolefonts/${CONSFONT}.gz > ${LIVE_STAGING}/boot/syslinux/${CONSFONT}
elif [ ! -f ${LIVE_STAGING}/boot/syslinux/${CONSFONT} ]; then
  sed -i -e "s/^font .*/#&/" ${LIVE_STAGING}/boot/syslinux/menu/*menu*.cfg
fi

# -----------------------------------------------------------------------------
# Assemble the ISO
# -----------------------------------------------------------------------------

echo "-- Assemble the ISO image."

# We keep strict size requirements for the XFCE ISO:
# addons/optional modules will not be added.
if [ "$LIVEDE" != "XFCE"  ]; then
  # Copy our stockpile of add-on modules into place:
  if ls ${LIVE_TOOLDIR}/addons/*.sxz 1>/dev/null 2>&1 ; then
    cp ${LIVE_TOOLDIR}/addons/*.sxz ${LIVE_MOD_ADD}/
  fi
  # If we have optionals, copy those too:
  if ls ${LIVE_TOOLDIR}/optional/*.sxz 1>/dev/null 2>&1 ; then
    cp ${LIVE_TOOLDIR}/optional/*.sxz ${LIVE_MOD_OPT}/
  fi
fi

if [ "$LIVEDE" != "XFCE"  -a "$LIVEDE" != "LEAN" -a "$LIVEDE" != "SLACKWARE" ]
then
  # KDE/PLASMA etc will profit from accelerated graphics support;
  # however the SLACKWARE ISO should not have any non-Slackware content.
  # You can 'cheat' when building the SLACKWARE ISO by copying the graphics
  # drivers into the 'optional' directory yourself.
  if ls ${LIVE_TOOLDIR}/graphics/*${KVER}-${SL_VERSION}-${SL_ARCH}.sxz 1>/dev/null 2>&1 ; then
    # Add custom (proprietary) graphics drivers:
    echo "-- Adding binary GPU drivers supporting kernel ${KVER}."
    cp ${LIVE_TOOLDIR}/graphics/*${KVER}-${SL_VERSION}-${SL_ARCH}.sxz ${LIVE_MOD_OPT}/
    if ls ${LIVE_TOOLDIR}/graphics/nvidia-*xx.ids 1>/dev/null 2>&1 ; then
      cp ${LIVE_TOOLDIR}/graphics/nvidia-*xx.ids ${LIVE_MOD_OPT}/
    fi
  fi
fi

# Directory for rootcopy files (everything placed here will be copied
# verbatim into the overlay root):
mkdir -p ${LIVE_STAGING}/${LIVEMAIN}/rootcopy

# Mark our ISO as 'ventoy-compatible':
echo "This ISO is compatible with Ventoy. See https://www.ventoy.net/en/compatible.html" >${LIVE_STAGING}/ventoy.dat

# Create an ISO file from the directories found below ${LIVE_STAGING}:
create_iso ${LIVE_STAGING}

# Clean out the mounts etc:
cleanup

