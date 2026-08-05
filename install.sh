#!/usr/bin/env bash
# Manually install the PPS-enabled cp210x driver for the running kernel
# (overwrites the in-tree module; keeps a .stock backup).
#
# Prefer ./install-dkms.sh on machines that get kernel updates.
#
# Usage:
#   sudo ./install.sh
#   sudo ./install.sh --build
#   sudo ./install.sh --reload
#   sudo ./install.sh --status

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=install-common.sh
source "${SCRIPT_DIR}/install-common.sh"

KVER="$(uname -r)"
KDIR="/lib/modules/${KVER}/build"
MODDIR="/lib/modules/${KVER}/kernel/drivers/usb/serial"

need_root() {
	if [[ "${EUID}" -ne 0 ]]; then
		die "run as root (e.g. sudo $0)"
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
	dest="$(installed_stock_path)"

	mkdir -p "${MODDIR}"
	backup_stock_if_needed "${dest}"

	log "Installing to ${dest}"
	compress_like_dest "${SCRIPT_DIR}/${MODNAME}.ko" "${dest}"
	depmod -a "${KVER}"

	log "Installed srcversion ${built_src}"
}

usage() {
	cat <<EOF
Usage: sudo $0 [command]

Manual install (overwrites in-tree module for this kernel only).
For automatic rebuilds on kernel updates, use: sudo ./install-dkms.sh

Commands:
  (default)  Build, overwrite in-tree module, and reload
  --build    Build only
  --install  Install an already-built .ko (no rebuild)
  --reload   Unload/load the module
  --status   Show module status
  -h, --help Show this help
EOF
}

main() {
	local cmd="${1:-}"

	read_pkg_version

	case "${cmd}" in
		-h|--help)
			usage
			;;
		--status)
			show_status
			;;
		--build)
			build_module
			;;
		--install)
			need_root
			install_module
			;;
		--reload)
			need_root
			reload_module
			show_status
			;;
		"")
			need_root
			build_module
			install_module
			reload_module
			show_status
			log "Done. Prefer ./install-dkms.sh on the NAS so kernel updates rebuild automatically."
			;;
		*)
			usage
			die "unknown command: ${cmd}"
			;;
	esac
}

main "$@"
