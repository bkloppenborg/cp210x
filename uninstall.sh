#!/usr/bin/env bash
# Remove the PPS-enabled cp210x driver (DKMS and/or manual install).
#
# Usage:
#   sudo ./uninstall.sh           # remove DKMS + restore stock if backed up
#   sudo ./uninstall.sh --dkms    # DKMS only
#   sudo ./uninstall.sh --manual  # restore stock module overwrite only
#   sudo ./uninstall.sh --status

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=install-common.sh
source "${SCRIPT_DIR}/install-common.sh"

need_root() {
	if [[ "${EUID}" -ne 0 ]]; then
		die "run as root (e.g. sudo $0)"
	fi
}

uninstall_dkms() {
	read_pkg_version

	if ! command -v dkms >/dev/null; then
		warn "dkms not installed; skipping DKMS removal"
		return 0
	fi

	if dkms status -m "${PKG_NAME}" -v "${PKG_VERSION}" 2>/dev/null | grep -q .; then
		log "Removing DKMS module ${PKG_NAME}/${PKG_VERSION}"
		dkms remove -m "${PKG_NAME}" -v "${PKG_VERSION}" --all || true
	else
		log "No DKMS registration for ${PKG_NAME}/${PKG_VERSION}"
	fi

	local src_tree="/usr/src/${PKG_NAME}-${PKG_VERSION}"
	if [[ -d "${src_tree}" ]]; then
		log "Removing ${src_tree}"
		rm -rf "${src_tree}"
	fi
}

restore_stock_module() {
	local dest backup
	dest="$(installed_stock_path)"
	backup="${dest}.stock"

	if [[ -e "${backup}" ]]; then
		log "Restoring stock module from ${backup}"
		cp -a "${backup}" "${dest}"
		rm -f "${backup}"
		depmod -a "$(uname -r)"
	else
		log "No stock backup at ${backup} (nothing to restore)"
	fi
}

unload_if_loaded() {
	stop_gps_consumers
	if lsmod | awk -v m="${MODNAME}" '$1 == m { found=1 } END { exit !found }'; then
		log "Unloading ${MODNAME}"
		rmmod "${MODNAME}" 2>/dev/null || modprobe -r "${MODNAME}" 2>/dev/null || \
			warn "could not unload ${MODNAME}; reboot may be needed"
	fi
}

usage() {
	cat <<EOF
Usage: sudo $0 [command]

Commands:
  (default)  Remove DKMS package and restore any manual stock overwrite
  --dkms     Remove DKMS registration/sources only
  --manual   Restore stock module from *.stock backup only
  --status   Show current module status
  -h, --help Show this help
EOF
}

main() {
	local cmd="${1:-}"

	case "${cmd}" in
		-h|--help)
			usage
			;;
		--status)
			read_pkg_version
			show_status
			;;
		--dkms)
			need_root
			read_pkg_version
			unload_if_loaded
			uninstall_dkms
			modprobe "${MODNAME}" 2>/dev/null || true
			show_status
			log "DKMS uninstall complete"
			;;
		--manual)
			need_root
			unload_if_loaded
			restore_stock_module
			modprobe "${MODNAME}" 2>/dev/null || true
			show_status
			log "Manual uninstall complete"
			;;
		"")
			need_root
			read_pkg_version
			unload_if_loaded
			uninstall_dkms
			restore_stock_module
			modprobe "${MODNAME}" 2>/dev/null || true
			show_status
			log "Uninstall complete (stock cp210x should load if present)"
			;;
		*)
			usage
			die "unknown command: ${cmd}"
			;;
	esac
}

main "$@"
