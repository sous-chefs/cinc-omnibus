# cinc-omnibus CHANGELOG

This file is used to list changes made in each version of the cinc-omnibus cookbook.

## 1.1.20 - *2024-07-31*

- Update rubygems_url to new Cinc rubygems server

## 1.1.19 - *2024-07-31*

- Add basic support for riscv64

## 1.1.18 - *2024-07-10*

- Add EL9 s390x Cinc omnibus-toolchain package

## 1.1.17 - *2024-07-09*

- Add missing perl-Digest-SHA and perl-bignum needed for newer OpenSSL builds on EL-based platforms
- Remove EOL CentOS Stream 8
- Add Rocky Linux 8/9 to CI testing

## 1.1.16 - *2024-05-23*

- Manually update to standardized files
- Remove testing for EOL platforms (but keep support for now)
- Add support for Ubuntu 24.04
- MDL fixes

## 1.1.15 - *2024-05-02*

## 1.1.14 - *2023-12-21*

## 1.1.13 - *2023-12-17*

- Install libtool needed for workstation builds

## 1.1.12 - *2023-12-08*

- Only install perl-FindBin perl-lib on newer AmazonLinux releases
- Install devtoolset-10 instead of devtoolset-11 since the aarch64 install is broken

## 1.1.11 - *2023-12-08*

- Install perl-FindBin & perl-lib on EL 9 and AmazonLinux (needed for OpenSSL v3)
- Install devtoolset-11-toolchain on EL 7 (needed for newer git)

## 1.1.10 - *2023-12-08*

- Ensure Perl IPC-Cmd is installed on EL based systems which is required for building OpenSSL v3

## 1.1.9 - *2023-10-31*

## 1.1.8 - *2023-10-16*

## 1.1.7 - *2023-10-14*

- Ensure "unsafe" development packages are removed

## 1.1.6 - *2023-09-21*

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
