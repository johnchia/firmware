# tapo-d130_ssc377d_sc5239_rtl8192eu

The main board of a TP-Link Tapo D130 doorbell, on the bench as a camera:
an SSC377D (QFN88), a SmartSens SC5239 (5 MP) and a Realtek RTL8192EU on
USB. `camera.conf` layers it on `ssc377d_raptor`, which holds everything
about the SoC, the flash layout and the software stack; this directory holds
what is soldered around the chip.

## What is on the board

- **Flash: 16 MB SPI NOR, converted.** The board shipped with SPI NAND; the
  PM_SPI_DO boot-strap pull-down was lifted (2026-09-21) to make it boot from
  NOR, and it booted the first image it was given. The layout is the base's:
  `256k(boot),64k(env),2048k(kernel),8192k(rootfs),-(rootfs_data)`.
- **Sensor: SC5239**, pinned, and named in the baked environment as
  `sensor=sc5239` because that is where `load_sigmastar` reads it. The part
  answers the SC5235's ID (0x3107/0x3108 = 0x52 0x35, 0x3109 = 0x01), which
  is what the SDK's sc5235 driver, the D130's own `sc5239_MIPI.ko` and
  Ingenic's two drivers all check, and there is no register that tells the
  two apart, so `ipcinfo` saying sc5235 is correct. The tree carries a
  `sensor_sc5239_mipi` driver (the SDK's sc5235 skeleton with the D130
  module's tables and gain schedule: hts 1440, vts 2000, 30 fps full frame)
  and the D130's own `isp_day.bin` as `sc5239.bin`. The pin ships that blob
  alone; the old `ssc377d_raptorwifi` target shipped the family's eight.
- **Radio: RTL8192EU**, power-gated. Its supply enable is pin 42 of the QFN88,
  PAD_FUART_RX, GPIO 42, which is WIFI_PWR_EN on SigmaStar's own SSC37X
  reference design and the pin the Tapo C120 uses for the same job. This
  kernel muxes that pad to PWM0 at boot and the idle output holds it low, so
  until something drives it there is nothing on the USB bus for
  `/etc/wireless/detect` to find. The `rtl8192eu-ssc377d-refboard` arm in the
  shared `/etc/wireless/usb` raises it and modprobes; `wlandev` in
  `uboot.env.txt` is what names that arm before S40network runs. A board
  whose dongle is always powered wants none of this: the `rtl8192eu-generic`
  arm and detection.
- **Ethernet** is on the SoC but unused on the bench; the radio is the way in.
- **The environment is baked** (`uboot.env.txt`) for that one `wlandev` line
  and the `sensor` line. Everything else in it is a transcription of what
  U-Boot compiles in, carried in full because a stored environment with a
  good CRC replaces the default rather than merging with it. A unit
  sysupgraded from before the sensor line existed wants
  `fw_setenv sensor sc5239` by hand; a whole-flash image writes it.
- **The clock restarts from fake-hwclock** each boot, so timestamps on this
  unit do not measure reboot gaps; use `/proc/uptime`.

## Verification log

- 2026-09-22, on `ssc377d_raptorwifi` build 2923b643 with the sc5239 driver
  and tuning: cold boot streams the SC5239 at 2592x1944, snapshots through
  rhd, picture neutral once AWB settles (the first snapshot within about
  20 s is magenta; AWB, not a fault). Registers 0x3905/07/08 = d8/01/11 and
  0x5000 = 20 read back after the module swap that proved the driver.
  The same build fixed the cold-boot failure where a preset `sensor` made
  `load_sigmastar` skip the `srcfg` write and the first `MI_SNR_Enable`
  failed.
- 2026-09-21: the first boot after the NOR conversion, over WiFi, RTL8192EU
  bound through the GPIO 42 arm, `wlan0` associated.
- Not yet run on this unit: the camera-named image from this directory. It
  composes to the same configuration as `ssc377d_raptorwifi` apart from the
  sensor pin, which drops the seven other IQ blobs.
