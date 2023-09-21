# cinc-omnibus CHANGELOG

This file is used to list changes made in each version of the cinc-omnibus cookbook.

## Unreleased

- Use correct linking for install path

## 1.1.5 - *2023-09-21*

- Add fixes for missing install path for Debian 11 and older on AArch64

## 1.1.4 - *2023-09-11*

- Update actions/checkout action to v4 (#12)

## 1.1.3 - *2023-08-21*

- Exclude mkdir fix for Debian 12 on AArch64

## 1.1.2 - *2023-07-10*

- Update sous-chefs/.github action to v2.0.5 (#10)

## 1.1.1 - *2023-05-16*

- Update sous-chefs/.github action to v2.0.4 (#9)

## 1.1.0 - *2023-05-03*

- Add support for ppc64le on Debian & Ubuntu
- Add support for:
  - AlmaLinux 8 & 9
  - Amazon Linux 2023
  - Debian 12
- Remove support for:
  - Amazon Linux 2 & 2022
  - Debian 9
- Set sane default for Windows System Drive
- Update and improved unit and integration tests

## 1.0.4 - *2023-05-03*

- Update sous-chefs/.github action to v2.0.2

## 1.0.3 - *2023-04-01*

- Update actions/stale action to v8

## 1.0.2 - *2023-03-02*

- Fix yaml

## 1.0.1 - *2022-10-20*

- Create symlink for mkdir for Debian on ARM

## 1.0.0 - *2022-10-17*

- Initial release focused on Linux platforms
- Based upon original omnibus cookbook
