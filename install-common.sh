# Shared helpers for install.sh / install-dkms.sh / uninstall.sh
# shellcheck shell=bash

PKG_NAME="cp210x-pps"
MODNAME="cp210x"
PKG_VERSION=""

log()  { printf '==> %s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }

read_pkg_version() {
	local conf="${SCRIPT_DIR}/dkms.conf"
	[[ -f "${conf}" ]] || die "missing ${conf}"
	PKG_VERSION="$(sed -n 's/^PACKAGE_VERSION="\(.*\)"/\1/p' "${conf}" | head -n1)"
	[[ -n "${PKG_VERSION}" ]] || die "could not read PACKAGE_VERSION from dkms.conf"
}

installed_stock_path() {
	local moddir="/lib/modules/$(uname -r)/kernel/drivers/usb/serial"
	if [[ -e "${moddir}/${MODNAME}.ko.zst" ]]; then
		echo "${moddir}/${MODNAME}.ko.zst"
	elif [[ -e "${moddir}/${MODNAME}.ko.xz" ]]; then
		echo "${moddir}/${MODNAME}.ko.xz"
	elif [[ -e "${moddir}/${MODNAME}.ko.gz" ]]; then
		echo "${moddir}/${MODNAME}.ko.gz"
	elif [[ -e "${moddir}/${MODNAME}.ko" ]]; then
		echo "${moddir}/${MODNAME}.ko"
	else
		echo "${moddir}/${MODNAME}.ko.zst"
	fi
}

stop_gps_consumers() {
	if command -v fuser >/dev/null; then
		fuser -k /dev/ttyUSB0 2>/dev/null || true
		fuser -k /dev/ttyUSB1 2>/dev/null || true
	fi
	if systemctl is-active --quiet gpsd.socket 2>/dev/null || \
	   systemctl is-active --quiet gpsd.service 2>/dev/null; then
		log "Stopping gpsd"
		systemctl stop gpsd.socket gpsd.service 2>/dev/null || true
	fi
}

reload_module() {
	log "Reloading ${MODNAME}"
	stop_gps_consumers

	if lsmod | awk -v m="${MODNAME}" '$1 == m { found=1 } END { exit !found }'; then
		if ! rmmod "${MODNAME}" 2>/dev/null; then
			warn "could not unload ${MODNAME}; trying modprobe -r"
			modprobe -r "${MODNAME}" 2>/dev/null || \
				die "failed to unload ${MODNAME}; close gpsd/gpsmon/screen and retry"
		fi
	fi

	modprobe "${MODNAME}"
}

show_status() {
	local path src live dkms_st

	path="$(modinfo -n "${MODNAME}" 2>/dev/null || true)"
	src="$(modinfo -F srcversion "${MODNAME}" 2>/dev/null || true)"
	live="$(cat "/sys/module/${MODNAME}/srcversion" 2>/dev/null || true)"

	printf '\n'
	log "Kernel:     $(uname -r)"
	log "modinfo:    ${path:-not found}"
	log "installed:  ${src:-n/a}"
	log "loaded:     ${live:-not loaded}"

	if command -v dkms >/dev/null; then
		dkms_st="$(dkms status -m "${PKG_NAME}" 2>/dev/null || true)"
		if [[ -n "${dkms_st}" ]]; then
			log "DKMS:       ${dkms_st}"
		else
			log "DKMS:       ${PKG_NAME} not registered"
		fi
	fi

	if [[ "${path}" == *"/updates/"* ]] || [[ "${path}" == *"/dkms/"* ]]; then
		log "OK: module path looks like a DKMS/override install"
	elif [[ "${path}" == *"/kernel/drivers/usb/serial/"* ]]; then
		if [[ -e "$(installed_stock_path).stock" ]]; then
			log "OK: stock path overwritten (manual install; .stock backup present)"
		else
			warn "loading in-tree path; may be the stock driver"
		fi
	fi

	if [[ -e /dev/ttyUSB0 ]]; then
		log "Device:     /dev/ttyUSB0 present"
	else
		warn "Device:     /dev/ttyUSB0 not present (plug in GPS if needed)"
	fi
}
