# Nerves System Trellis

[![Hex version](https://img.shields.io/hexpm/v/nerves_system_trellis.svg "Hex version")](https://hex.pm/packages/nerves_system_trellis)
[![CI](https://github.com/nerves-project/nerves_system_trellis/actions/workflows/ci.yml/badge.svg)](https://github.com/nerves-project/nerves_system_trellis/actions/workflows/ci.yml)
[![REUSE status](https://api.reuse.software/badge/github.com/nerves-project/nerves_system_trellis)](https://api.reuse.software/info/github.com/nerves-project/nerves_system_trellis)

This project provides the base Nerves System configuration for the Trellis
hardware platform. Unlike traditional single-board computers, Trellis is
designed as a hardware template for creating custom embedded devices.

## Hardware Platform

Trellis is a flexible design centered around the Allwinner T113-S4 SoC. This
dual-core ARM Cortex-A7 processor includes 256 MB of integrated DDR3 RAM, which
simplifies PCB routing and reduces the overall footprint of custom designs.

A Trellis-compatible design typically adheres to the following core
specifications:

- The system is based on the Allwinner T113-S4 SoC.
- Storage and booting are handled via an SDIO flash chip usually connected to
  the MMC0 peripheral.
- High-speed wireless connectivity can be provided by attached WiFi modules,
  such as the Realtek RTL8188 or RTL8723.
- A USB-C connector attached to USB0 (for FEL mode and initial flashing)
- Debug console on UART4

### Reference Designs

There are several open-source hardware projects that utilize the Trellis
template. These repositories provide KiCad source files that can be used as a
starting point for your own custom hardware.

- [Trellis Core](https://github.com/protolux-electronics/trellis_core) contains
  the primary KiCad source files for the base hardware template.
- [Wisteria Hardware](https://github.com/protolux-electronics/wisteria_hardware)
  is the hardware implementation used for the 2025 Goatmire conference name
  badge, demonstrating the template's use in a specific form factor.

## Features

This system configuration enables a standard set of peripherals across
Trellis-based hardware.

| Feature        | Description                                                         |
| -------------- | ------------------------------------------------------------------- |
| CPU            | 1.2 GHz Dual-core ARM Cortex-A7                                     |
| Memory         | 256 MB Integrated DDR3                                              |
| Storage        | SDIO Flash (on MMC0)                                                |
| Linux kernel   | 6.12 with patches                                                   |
| IEx terminal   | UART `ttyS4`                                                        |
| GPIO, I2C, SPI | Supported via [Elixir Circuits](https://github.com/elixir-circuits) |
| WiFi           | Various Realtek modules supported                                   |
| HW Watchdog    | Enabled                                                             |

## Using

The most common way of creating a Nerves project using this system is to run
`mix nerves.new my_app` and export `MIX_TARGET=trellis`. See the
[Getting started guide](https://hexdocs.pm/nerves/getting-started.html) for more
information.

Initial flashing of Trellis hardware without an SD card is typically performed
using FEL mode. This allows you to load firmware onto a blank device over USB
without needing an SD card slot. You can find the necessary tools and
instructions for this process in the
[usb_fel_loaders](https://github.com/gworkman/usb_fel_loaders) repository.

Once the initial firmware is loaded, standard Nerves over-the-air (OTA) updates
can be used for subsequent deployments.

If you need custom modifications to this system for your device, see the
[Nerves documentation on customizing
systems](https://hexdocs.pm/nerves/customizing-systems.html).

## Linux kernel

The Linux kernel is built from the mainline 6.12 release with patches for the
Allwinner T113-S4. The default kernel configuration is in `linux_defconfig`.

## Special Thanks

Thank you to Connor Rigby who brought up initial support for the Allwinner
T113-S3.
