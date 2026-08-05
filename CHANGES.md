# Changelog

## 1.1.0 — 2026-08-05

- Add DKMS packaging (`dkms.conf`, `install-dkms.sh`) so the module rebuilds
  on kernel updates.
- Add `install.sh` (manual overwrite), `uninstall.sh`, and shared helpers.
- Expose `MODULE_VERSION` / clearer `modinfo` description (`PPS on RI`).

## 1.0.0 — 2026-08-05

- Port PPS-on-RI support to Linux kernel **7.0** (rebased on stock `cp210x`).
- Always enable `EMBED_EVENTS` while the port is open (not only when `INPCK`
  is set).
- Implement modem-status handling for CTS/DSR/RI/DCD and wire up `TIOCMIWAIT`.
- Report RI trailing-edge events to the `N_PPS` line discipline as assert
  edges, without hanging up the tty on a clear edge.
