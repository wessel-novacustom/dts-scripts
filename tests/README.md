# DTS scripts unit tests

This directory contains stub scripts for testing DTS update and deploy logic
in complex scenarios.

## Running on host

Running test on the host may result in unpredictable results because of the
missing programs and different version of certain tools. It is advised to run
the DTS image in QEMU as a development environment. Running on host is
generally not supported and should be avoided.

## Running in QEMU

### Credentials setup

We need credentials for each test variant. You can use provided template and
fill it in accordingly.

```bash
cp des-credentials.sh.example des-credentials.sh
```

### Running automatically

Some scenarios are have been already migrated into [OSFV](TBD).

```bash
robot -L TRACE -v config:qemu -v rte_ip:127.0.0.1 -v snipeit:no dts/dts-tests.robot
```

### Running manually

1. Boot the latest DTS image in QEMU. Recommended steps:
    - start QEMU according to
    [OSFV documentation](https://github.com/Dasharo/open-source-firmware-validation/blob/develop/docs/qemu.md#booting)
    (use `os` switch, not `firmware`)
    - enable network boot and boot into DTS via iPXE
    - enable SSH server (option `8` in main menu)

1. Deploy updated scripts and tests into qemu

    ```bash
    PORT=5222 ./scripts/local-deploy.sh 127.0.0.1
    ```

1. Execute desired test as described in below section. E.g.:

    ```shell
    ssh -p 5222 root@127.0.0.1
    export BOARD_VENDOR="Notebook" SYSTEM_MODEL="NV4xPZ" BOARD_MODEL="NV4xPZ"
    export BIOS_VERSION="Dasharo (coreboot+UEFI) v1.7.2" TEST_DES=y DES_TYPE="heads" && dts-boot
    ```

## Test cases

The general idea is that we override some variables, so DTS scripts consider
they are running on the given board. Then we select `Install` or `Update`
actions from DTS menu, and check if the flow is as expected in certain
scenario.

After each `dts-boot -> 5) Check and apply Dasharo firmware updates` scenario
execution, we can drop to DTS shell and continue with the next scenario.

### NovaCustom

```bash
export BOARD_VENDOR="Notebook" SYSTEM_MODEL="NV4xPZ" BOARD_MODEL="NV4xPZ"
```

1. Dasharo v1.7.2 on NV4x_PZ eligible for updates to heads with heads DES and
   regular update:

    ```bash
    export BIOS_VERSION="Dasharo (coreboot+UEFI) v1.7.2" TEST_DES=y DES_TYPE="heads" && dts-boot
    ```

    Expected output:
    - heads fw should be offered

1. Dasharo v1.7.2 on NV4x_PZ eligible for updates to heads without DES
   (regular update only):

    ```bash
    export BIOS_VERSION="Dasharo (coreboot+UEFI) v1.7.2" TEST_DES=n && dts-boot
    ```

    Expected output:
    - no update should be offered

1. Dasharo v1.6.0 on NV4x_PZ not eligible for updates to heads with heads DES
   (regular update only):

    ```bash
    export BIOS_VERSION="Dasharo (coreboot+UEFI) v1.6.0" TEST_DES=y DES_TYPE="heads" && dts-boot
    ```

    Expected output:
    - UEFI fw update should be offered (this is too old release to transition to
    heads directly, need to flash latest UEFI fw first)

1. Dasharo v1.6.0 on NV4x_PZ not eligible for updates to heads without heads
   DES (regular update only):

    ```bash
    export BIOS_VERSION="Dasharo (coreboot+UEFI) v1.6.0" TEST_DES=n && dts-boot
    ```

    Expected output:
    - UEFI fw update should be offered

1. Dasharo heads v0.9.0 on NV4x_PZ eligible for updates to heads with heads
   DES and switch back (heads updates):

    ```bash
    export BIOS_VERSION="Dasharo (coreboot+heads) v0.9.0" TEST_DES=y DES_TYPE="heads" && dts-boot
    ```

    Expected output:
    - migration to UEFI should be offered first
    - if we say `n` to switch, heads update should be offered

1. Dasharo heads v0.9.0 on NV4x_PZ without DES switch back, no heads updates:

    ```bash
    export BIOS_VERSION="Dasharo (coreboot+heads) v0.9.0" TEST_DES=n && dts-boot
    ```

    Expected output:
    - migration to UEFI should be offered first
    - if we say `n` to switch, no heads update should be offered

Another case is to edit `dts-functions.sh` and set `DASHARO_REL_VER` to
`v1.7.3` to detect possible regular firmware updates and `HEADS_REL_VER_DES`
to `v0.9.1` to detect possible heads firmware updates and repeat all test
cases. The URLs for non-existing versions may fail.

The NovaCustom test binaries for credentials in `dts-boot` are placed in
[/projects/projects/2022/novacustom/dts_test](https://cloud.3mdeb.com/index.php/f/659609)
on 3mdeb cloud. These are just public coreboot+UEFI v1.7.2 binaries.
Analogically with MSI, cloud directory is
[/projects/projects/2022/msi/dts_test](https://cloud.3mdeb.com/index.php/f/667474)
and binaries are simply Z690-A public coreboot+UEFI v1.1.1 binaries with
changed names for both Z690-A and Z790-P (resigned with appropriate keys).

### MSI MS-7D25

```bash
export BOARD_VENDOR="Micro-Star International Co., Ltd." SYSTEM_MODEL="MS-7D25" BOARD_MODEL="PRO Z690-A WIFI DDR4(MS-7D25)"
```

1. Dasharo v1.1.1 on MS-7D25 eligible for updates to heads with heads DES and
   regular update:

    ```bash
    export BIOS_VERSION="Dasharo (coreboot+UEFI) v1.1.1" TEST_DES=y DES_TYPE="heads" && dts-boot
    ```

1. Dasharo v1.1.1 on MS-7D25 eligible for updates to heads without DES
   (regular update only):

    ```bash
    export BIOS_VERSION="Dasharo (coreboot+UEFI) v1.1.1" TEST_DES=n && dts-boot
    ```

1. Dasharo v1.1.2 on MS-7D25 eligible for updates to heads with heads DES
   (regular update only through regular DES):

    ```bash
    export BIOS_VERSION="Dasharo (coreboot+UEFI) v1.1.2" TEST_DES=y DES_TYPE="heads" && dts-boot
    ```

1. Dasharo v1.1.2 on MS-7D25 not eligible for updates to heads without heads
   DES (regular update only through regular DES):

    ```bash
    export BIOS_VERSION="Dasharo (coreboot+UEFI) v1.1.2" TEST_DES=n && dts-boot
    ```

1. Dasharo heads v0.9.0 on MS-7D25 eligible for updates to heads with heads
   DES and switch back (regular update and switch-back):

    ```bash
    export BIOS_VERSION="Dasharo (coreboot+heads) v0.9.0" TEST_DES=y DES_TYPE="heads" && dts-boot
    ```

1. Dasharo heads v0.9.0 on MS-7D25 without DES switch back, no heads updates
   (regular update and switch-back):

    ```bash
    export BIOS_VERSION="Dasharo (coreboot+heads) v0.9.0" TEST_DES=n && dts-boot
    ```

### MSI MS-7E06

```bash
export BOARD_VENDOR="Micro-Star International Co., Ltd." SYSTEM_MODEL="MS-7E06" BOARD_MODEL="PRO Z790-P WIFI (MS-7E06)"
```

1. Dasharo heads v0.9.0 on MS-7E06 eligible for updates to heads with heads
   DES and switch back (regular update and switch-back only through regular
   DES, no community release):

    ```bash
    export BIOS_VERSION="Dasharo (coreboot+heads) v0.9.0" TEST_DES=y DES_TYPE=heads && dts-boot
    ```

    Expected output:
    - migration to UEFI should be offered first
    - if we say `n` to switch, no heads (no more recent update available yet)

1. Dasharo heads v0.9.0 on MS-7E06 without DES switch back, no heads updates
   (regular update and switch-back only through regular DES, no community
   release):

    ```bash
    export BIOS_VERSION="Dasharo (coreboot+heads) v0.9.0" TEST_DES=n && dts-boot
    ```

    Expected output:
    - should print info on DES availability in the shop
    - migration to UEFI should be offered

### PC Engines

```bash
export BOARD_VENDOR="PC Engines" SYSTEM_MODEL="APU2" BOARD_MODEL="APU2"
```

1. Initial deployment from legacy firmware (no DES credentials)

    ```bash
    export BIOS_VERSION="v4.19.0.1" TEST_DES=n && dts-boot
    ```

    Expected output:
    - no DES - no deployment should be offered
    - info on DES availailbity in the shop should be shown

1. Initial deployment from legacy firmware (UEFI DES credentials)

    ```bash
    export BIOS_VERSION="v4.19.0.1" TEST_DES=y DES_TYPE="UEFI" && dts-boot
    ```

    Expected output:
    - UEFI deployment should be offered
    - info on DES availailbity in the shop should not be shown

1. Initial deployment from legacy firmware (seabios DES credentials)

    ```bash
    export BIOS_VERSION="v4.19.0.1" TEST_DES=y DTS_TYPE="seabios" && dts-boot
    ```

    Expected output:
    - Seabios deployment should be offered
    - info on DES availailbity in the shop should not be shown

1. Initial deployment from legacy firmware (correct DES credentials)

    ```bash
    export BIOS_VERSION="v4.19.0.1" TEST_DES=n && dts-boot
    ```

    Expected output:
    - seabios deployment should be offered
    - info on DES availailbity in the shop should not be shown
