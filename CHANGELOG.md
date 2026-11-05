# Changelog

This project does NOT follow semantic versioning. The version increases as
follows:

1. Major version updates are breaking updates to the build infrastructure. These
   should be very rare.
2. Minor version updates are made for every major Buildroot release. This may
   also include Erlang/OTP and Linux kernel updates. These are made four times a
   year shortly after the Buildroot releases.
3. Patch version updates are made for Buildroot minor releases, Erlang/OTP
   releases, and Linux kernel updates. They're also made to fix bugs and add
   features to the build infrastructure.

## v0.6.1

This is a security and bug fix release.

* Changes
  * Use CRC32 for FIT image hashes to reduce boot time

* Package updates
  * [nerves_system_br 1.35.3](https://github.com/nerves-project/nerves_system_br/releases/tag/v1.35.3)
  * [Buildroot 2026.08.1](https://lore.kernel.org/buildroot/buildroot-2026.08.1-announce-1792682049@buildroot.org/T/)

## v0.6.0

This is a major Buildroot update with security and feature updates throughout.

It does not appear that custom systems require modification for this upgrade,
but your system might use something not tested by the officially supported ones.

* Package updates
  * [nerves_system_br 1.35.2](https://github.com/nerves-project/nerves_system_br/releases/tag/v1.35.2)
  * [Buildroot 2026.08](https://lore.kernel.org/buildroot/878q5hf0yd.fsf@dell.be.48ers.dk/T/)
  * [Erlang/OTP 29.1.2](https://erlang.org/download/OTP-29.1.2.README.md)

## v0.5.0

IMPORTANT: This is a non-backwards compatible release. You will have to reflash
your NSK or Goatmire badge.

* Changes
  * Change U-Boot failure recovery to use U-Boot's upgrade_available feature.
    This fixes an issue preventing first-boot rollback.
  * Use FIT images rather than read kernels from the rootfs. This adds
    flexibility to kernel/dts configurations and possible future initrd use.
  * Allow booting from EROFS root filesystems. This will be supported with
    Nerves 2.
  * Trim U-Boot wait time to 0 seconds. It's still possible to break into
    U-Boot, and this saves 2 seconds of boot time.
  * Add balance bot device tree configuration. This is not enabled by default.
  * Add a redundant U-Boot environment block to protect against corruption
    there.
  * Allow Nerves 2 pre-releases to be used

* Package updates
  * [nerves_system_br 1.34.4](https://github.com/nerves-project/nerves_system_br/releases/tag/v1.34.4)

## v0.4.2

This is a security and bug fix release.

* Changes
  * Include rootfs.tar for use with Nerves 2.0 development builds (ignored by Nerves 1.x)

* Package updates
  * [nerves_system_br 1.34.1](https://github.com/nerves-project/nerves_system_br/releases/tag/v1.34.1)

## v0.4.1

* Changes
  * Disable UART0 to avoid conflict with expansion GPIOs. In the future, the
    plan is to allow it to be enabled via a DTS overlay.
  * Add GPIO labels for PE2 - PE13 to make it easier to refer to them with
    Circuits.GPIO.

## v0.4.0

This is a major update with support for the Nerves Starter Kit. It still
supports the Goatmire badge on OTA updates from previous versions and if you
modify the U-Boot start script before flashing a new device. The plan is to
autodetect the device in the next release.

* Changes
  * linux 6.18.35
  * GCC 15.3.0
  * nerves_system_br v1.34.0

## v0.3.1

Bump `nerves_system_br` and `nerves`. This also adds support for the hardware
PWM, and fixes several clock issues relating to the RTC that slowed down the
initial startup time. Additionally, this renames the default hostname to
`nerves-SERIALNUM` to follow convention of other nerves systems.

This is the final release with primary support for the 2025 Goatmire name
badges. Future releases will target the Nerves Starter Kit.

## v0.3.0

Bump `nerves_system_br` version to latest. This release also relaxes the fwup
checks for the platform name changed in v0.2.0, so upgrading from v0.1.x should
no longer result in errors when upgrading via OTA.

## v0.2.0

Bump `nerves_system_br` and `nerves` versions to latest. This update provides
support for OTP 28 and Elixir 1.19.

Additionally, this changes the platform name from `vitis` to `trellis` in
`fwup.conf`. This may result in an error when upgrading firmware OTA via fwup.
Please reflash any affected boards using FEL mode and
[`usb_fel_loaders`](https://github.com/gworkman/usb_fel_loaders)

## v0.1.1

Add support for RTL8723 wifi modules.

## v0.1.0

This is the initial release.
