# Package manager test cases

This document contains test cases for DPP package manager which is, for now,
a part of Dynamic UI tool implementation.

## A package can be downloaded and installed

This test verifies whether a package can be downloaded from `dl.dasharo.com`
(it is the only repository supported for now) and installed properly in the
system.

Prerequisites:
* DTS built with Dynamic UI tool support;
* `dl.dasharo.com` is up and working properly;
* Access to a test package in `dl.dasharo.com`.

Test steps:
1. Boot into DTS uo to the main menu;
2. Choose option to provide DPP credentials;
3. Provide DPP credentials with the access to the test package;
4. Verify that the test package installation logs appear;
5. After the installation completes press `s` to enter shell;
6. Look for the files the package should have installed on `rootfs`:

    ```bash
    find / -name FILE_NAME
    ```

    > Note: replace `FILE_NAME` with the name of the file the test package
    > provides.

Expected results:
* The test package installation logs should appear after the credentials has
  been provided;
* The files the package provides should be found on the system `rootfs`.
