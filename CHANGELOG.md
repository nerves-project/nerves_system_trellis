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
