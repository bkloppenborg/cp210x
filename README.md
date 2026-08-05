# cp210x driver with PPS support

This project modifies the stock Linux kernel driver for the Silicon Labs
CP210X suite of devices to add support for modem control / status line
changes with particular attention to the Pulse Per Second (PPS) signal.

This tree is based on the upstream Linux **7.0** `cp210x` driver, with the
PPS-on-RI changes originally developed by Brian Kloppenborg for 5.15
(https://github.com/bkloppenborg/cp210x) ported forward.

It was developed for the Adafruit Ultimate GPS with USB-C (CP2102N), which
routes the PPS signal to the Ring Indicator (RI) pin.

# Driver will NOT make it into the Linux kernel

Unfortunately, the changes contained herein will NOT appear in the upstream
Linux kernel. The original patch was rejected for two reasons:

1. This driver requires every character coming from the serial device be
   inspected for a special escape sequence. While necessary for the GPS
   receiver, it is unnecessary for the majority of devices. As such, it was
   regarded as undesirable behavior.

2. The timing precision provided by this device was regarded as inferior when
   compared to traditional serial devices. Traditional serial PPS devices yield
   timing precision of ~5-10 nanoseconds relative to UTC. Because this device
   connects as a full-speed (USB 1.1) device, its timing precision is limited
   to 1 millisecond. If it could be made to operate as a high-speed (USB 2.0)
   device its timing precision would be 0.125 ms. Both were regarded as
   inferior compared with a true PPS device.

I would caution the user to keep these things in consideration before using
this driver.

# Summary of modifications (relative to stock 7.0)

1. Always enable CP210x `EMBED_EVENTS` while the port is open (stock only
   enables it when input parity checking / `INPCK` is set).
2. Implement modem-status event handling (`CTS` / `DSR` / `RI` / `DCD`) and
   wire up `TIOCMIWAIT` via `usb_serial_generic_tiocmiwait`.
3. Treat RI trailing-edge events as PPS: notify the `N_PPS` line discipline
   through `dcd_change` (without hanging up the tty on a clear edge).
4. Keep stock 7.0 APIs (`kzalloc_obj`, `gpio_chip.set` returning `int`,
   current `usb_serial_driver` / termios signatures, device ID table).

# Building, testing, and installing

1. Install build deps for your running kernel:

```
sudo apt install linux-headers-$(uname -r) build-essential zstd
```

2. Build, install over the stock module (keeps a `.stock` backup), and reload:

```
git clone https://github.com/sergei202/cp210x
cd cp210x
sudo ./install.sh
```

Re-run `sudo ./install.sh` after every kernel update. Subcommands:
`--status`, `--build`, `--reload`.

3. With the GPS attached (e.g. `/dev/ttyUSB0`) and a 3D fix:

```
# Kernel PPS via line discipline (creates /dev/ppsN)
sudo ldattach 18 /dev/ttyUSB0 &
sudo ppstest /dev/pps0

# Or let gpsd attach KPPS itself
sudo gpsmon /dev/ttyUSB0
```

You should see regular assert events from `ppstest`, and gpsd should no
longer report that kernel PPS / TIOCMIWAIT is unavailable.
