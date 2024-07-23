# Dynamic UI tool test cases

This document contains test cases for Dynamic UI tool. The tool depends upon
DPP Package Manager, so some test cases will depend upon specific tests from
[the package manager test file](./package-manager.md).

## Premium packages submenu is working

This test verifies whether the premium DPP packages submenu works.

Prerequisites:
* DTS built with Dynamic UI tool support;
* `dl.dasharo.com` is up and working properly;
* Access to a test package with menu script in `dl.dasharo.com`.

Dependencies:
* Test `A package can be downloaded and installed` from [the package manager
  test file](./package-manager.md)

Test steps:
1. Boot into DTS uo to the main menu;
2. Choose option to provide DPP credentials;
3. Provide DPP credentials with the access to the test package;
4. Wait until the test package is installed;
5. Return to the main menu;
6. Locate `Premium options` option in main menu options list;
7. Choose `Premium options` from the main menu options list;
8. Verify that submenu is being rendered appropriately:
    1. Verify that DTS header is being rendered;
    2. Verify that DTS footer is being rendered;
    3. Verify that the return to main menu option is being rendered;
9. Verify that submenu option provided by the test package menu script is being
  rendered;
10. Choose the submenu option provided by the test package menu script;
11. Verify that the work that should be done after choosing the option is being
  done properly.

Expected results:
* `Premium options` main menu option should be rendered after the test package
  with the correct menu script was installed;
* After choosing `Premium options` main menu option the submenu should be
  rendered;
* The submenu should contain four parts:
    - DTS header;
    - DTS footer;
    - Return to main menu option;
    - Option provided by the test package menu script;
* The option provided by the test package menu script should be choosable;
* After choosing the option provided by the test package menu script the
  appropriate work defined in the test package menu script should be done.
