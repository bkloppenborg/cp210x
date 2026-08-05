#!/usr/bin/env bash
# Install the PPS-enabled cp210x driver via DKMS (rebuilds on kernel updates).
#
# Usage:
#   sudo ./install-dkms.sh
#   sudo ./install-dkms.sh --status
#   sudo ./install-dkms.sh --reload
#
# Requires: dkms, linux-headers-$(uname -r), build-essential

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=install-common.sh
source "${SCRIPT_DIR}/install-common.sh"

need_root() {
	if [[ "${EUID}" -ne 0 ]]; then
		die "run as root (e.g. sudo $0)"
	fi
}

need_dkms() {
	command -v dkms >/dev/null || die "dkms not found; install with: sudo apt install dkms"
}

check_headers() {
	local kdir="/lib/modules/$(uname -r)/build"
	if [[ ! -d "${kdir}" ]]; then
		die "kernel headers not found at ${kdir}
Install them, e.g.:
  sudo apt install linux-headers-$(uname -r)"
	fi
}

dkms_tree_dir() {
	echo "/usr/src/${PKG_NAME}-${PKG_VERSION}"
}

sync_sources_to_dkms_tree() {
	local dest
	dest="$(dkms_tree_dir)"

	log "Installing sources to ${dest}"
	rm -rf "${dest}"
	mkdir -p "${dest}"
	cp -a "${SCRIPT_DIR}/cp210x.c" "${SCRIPT_DIR}/Makefile" "${SCRIPT_DIR}/dkms.conf" "${dest}/"
}

dkms_is_added() {
	dkms status -m "${PKG_NAME}" -v "${PKG_VERSION}" 2>/dev/null | grep -q .
}

remove_dkms_build() {
	if dkms_is_added; then
		log "Removing existing DKMS build of ${PKG_NAME}/${PKG_VERSION}"
		dkms remove -m "${PKG_NAME}" -v "${PKG_VERSION}" --all || true
	fi
}

install_dkms() {
	need_dkms
	check_headers
	read_pkg_version

	# If a manual overwrite of the stock module exists, leave it but warn:
	# DKMS installs under updates/ which already takes precedence.
	local stock_path
	stock_path="$(installed_stock_path)"
	if [[ -e "${stock_path}" ]] && [[ ! -e "${stock_path}.stock" ]]; then
		log "Note: stock in-tree module remains at ${stock_path}"
		log "DKMS module will take precedence via updates/"
	fi

	remove_dkms_build
	sync_sources_to_dkms_tree

	log "Adding ${PKG_NAME}/${PKG_VERSION} to DKMS"
	dkms add -m "${PKG_NAME}" -v "${PKG_VERSION}"

	log "Building and installing for $(uname -r)"
	dkms install -m "${PKG_NAME}" -v "${PKG_VERSION}" -k "$(uname -r)"

	reload_module
	show_status
	log "DKMS install complete. Future kernel updates will rebuild automatically."
}

usage() {
	cat <<EOF
Usage: sudo $0 [command]

Commands:
  (default)  Install via DKMS for the running kernel (AUTOINSTALL on updates)
  --reload   Unload/load cp210x
  --status   Show DKMS / module status
  -h, --help Show this help

Dependencies:
  sudo apt install dkms linux-headers-\$(uname -r) build-essential
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
		--reload)
			need_root
			reload_module
			;;
		"")
			need_root
			install_dkms
			;;
		*)
			usage
			die "unknown command: ${cmd}"
			;;
	esac
}

main "$@"
