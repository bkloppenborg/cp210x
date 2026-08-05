#!/usr/bin/env bash
# Install the PPS-enabled cp210x driver for the running kernel.
#
# Usage:
#   sudo ./install.sh           # build, install, reload
#   sudo ./install.sh --build   # build only
#   sudo ./install.sh --reload  # reload already-installed module
#   sudo ./install.sh --status  # show which module is active
#
# Re-run after every kernel update.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KVER="$(uname -r)"
KDIR="/lib/modules/${KVER}/build"
MODDIR="/lib/modules/${KVER}/kernel/drivers/usb/serial"
MODNAME="cp210x"

log()  { printf '==> %s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }

need_root() {
	if [[ "${EUID}" -ne 0 ]]; then
		die "run as root (e.g. sudo $0 ${*:-})"
	fi
}

installed_path() {
	# Prefer the compressed Ubuntu/Debian layout when present.
	if [[ -e "${MODDIR}/${MODNAME}.ko.zst" ]]; then
		echo "${MODDIR}/${MODNAME}.ko.zst"
	elif [[ -e "${MODDIR}/${MODNAME}.ko.xz" ]]; then
		echo "${MODDIR}/${MODNAME}.ko.xz"
	elif [[ -e "${MODDIR}/${MODNAME}.ko.gz" ]]; then
		echo "${MODDIR}/${MODNAME}.ko.gz"
	elif [[ -e "${MODDIR}/${MODNAME}.ko" ]]; then
		echo "${MODDIR}/${MODNAME}.ko"
	else
		echo "${MODDIR}/${MODNAME}.ko.zst"
	fi
}

backup_stock_if_needed() {
	local dest="$1"
	local backup="${dest}.stock"

	if [[ -e "${dest}" && ! -e "${backup}" ]]; then
		log "Backing up stock module to ${backup}"
		cp -a "${dest}" "${backup}"
	fi
}

compress_like_dest() {
	local src_ko="$1"
	local dest="$2"

	case "${dest}" in
		*.ko.zst)
			command -v zstd >/dev/null || die "zstd is required to install ${dest}"
			zstd -f -q -o "${dest}" "${src_ko}"
			;;
		*.ko.xz)
			command -v xz >/dev/null || die "xz is required to install ${dest}"
			xz -c -f "${src_ko}" >"${dest}"
			;;
		*.ko.gz)
			command -v gzip >/dev/null || die "gzip is required to install ${dest}"
			gzip -c -f "${src_ko}" >"${dest}"
			;;
		*.ko)
			cp -f "${src_ko}" "${dest}"
			;;
		*)
			die "unsupported module path: ${dest}"
			;;
	esac
}

check_headers() {
	if [[ ! -d "${KDIR}" ]]; then
		die "kernel headers not found at ${KDIR}
Install them, e.g.:
  sudo apt install linux-headers-$(uname -r)"
	fi
}

build_module() {
	check_headers
	log "Building ${MODNAME} for ${KVER}"
	make -C "${SCRIPT_DIR}" clean >/dev/null
	make -C "${SCRIPT_DIR}"
	[[ -f "${SCRIPT_DIR}/${MODNAME}.ko" ]] || die "build failed: ${MODNAME}.ko missing"
	log "Built $(modinfo -F srcversion "${SCRIPT_DIR}/${MODNAME}.ko")"
}

install_module() {
	local dest built_src

	[[ -f "${SCRIPT_DIR}/${MODNAME}.ko" ]] || die "nothing to install; run build first"
	built_src="$(modinfo -F srcversion "${SCRIPT_DIR}/${MODNAME}.ko")"
	dest="$(installed_path)"

	mkdir -p "${MODDIR}"
	backup_stock_if_needed "${dest}"

	log "Installing to ${dest}"
	compress_like_dest "${SCRIPT_DIR}/${MODNAME}.ko" "${dest}"
	depmod -a "${KVER}"

	log "Installed srcversion ${built_src}"
}

module_in_use() {
	local holders
	holders="$(lsmod | awk -v m="${MODNAME}" '$1 == m { print $3 }')"
	[[ -n "${holders}" && "${holders}" != "0" ]]
}

reload_module() {
	log "Reloading ${MODNAME}"

	# Free typical GPS consumers so rmmod can succeed.
	if command -v fuser >/dev/null; then
		fuser -k /dev/ttyUSB0 2>/dev/null || true
		fuser -k /dev/ttyUSB1 2>/dev/null || true
	fi
	if systemctl is-active --quiet gpsd.socket 2>/dev/null || \
	   systemctl is-active --quiet gpsd.service 2>/dev/null; then
		log "Stopping gpsd for reload"
		systemctl stop gpsd.socket gpsd.service 2>/dev/null || true
	fi

	if lsmod | awk -v m="${MODNAME}" '$1 == m { found=1 } END { exit !found }'; then
		if ! rmmod "${MODNAME}" 2>/dev/null; then
			warn "could not unload ${MODNAME} (device still busy?); will try modprobe -r"
			modprobe -r "${MODNAME}" 2>/dev/null || \
				die "failed to unload ${MODNAME}; close gpsd/gpsmon/screen and retry"
		fi
	fi

	modprobe "${MODNAME}"
	show_status
}

show_status() {
	local path src live

	path="$(modinfo -n "${MODNAME}" 2>/dev/null || true)"
	src="$(modinfo -F srcversion "${MODNAME}" 2>/dev/null || true)"
	live="$(cat /sys/module/${MODNAME}/srcversion 2>/dev/null || true)"

	printf '\n'
	log "Kernel:     ${KVER}"
	log "modinfo:    ${path:-not found}"
	log "installed:  ${src:-n/a}"
	log "loaded:     ${live:-not loaded}"

	if [[ -n "${live}" && -f "${SCRIPT_DIR}/${MODNAME}.ko" ]]; then
		local built
		built="$(modinfo -F srcversion "${SCRIPT_DIR}/${MODNAME}.ko")"
		if [[ "${live}" == "${built}" ]]; then
			log "OK: running patched module (${live})"
		else
			warn "loaded srcversion (${live}) != built (${built})"
		fi
	fi

	if [[ -e /dev/ttyUSB0 ]]; then
		log "Device:     /dev/ttyUSB0 present"
	else
		warn "Device:     /dev/ttyUSB0 not present (plug in GPS if needed)"
	fi
}

usage() {
	cat <<EOF
Usage: sudo $0 [command]

Commands:
  (default)  Build, install into /lib/modules/\$(uname -r), and reload
  --build    Build only
  --install  Install an already-built .ko (no rebuild)
  --reload   Unload/load the installed module
  --status   Show installed vs loaded module
  -h, --help Show this help

After a kernel upgrade, re-run: sudo $0
EOF
}

main() {
	local cmd="${1:-}"

	case "${cmd}" in
		-h|--help)
			usage
			;;
		--status)
			show_status
			;;
		--build)
			# Build does not require root if headers are world-readable,
			# but out-of-tree builds are usually done with sudo for simplicity.
			build_module
			;;
		--install)
			need_root "$@"
			install_module
			;;
		--reload)
			need_root "$@"
			reload_module
			;;
		"")
			need_root
			build_module
			install_module
			reload_module
			log "Done. Test with: sudo ppstest /dev/pps0  (after N_PPS / gpsd attach)"
			;;
		*)
			usage
			die "unknown command: ${cmd}"
			;;
	esac
}

main "$@"
