# frozen_string_literal: true

require 'spec_helper'

describe 'cinc_omnibus_builder' do
  step_into :cinc_omnibus_builder

  context 'on ubuntu' do
    platform 'ubuntu', '24.04'

    recipe do
      cinc_omnibus_builder 'default'
    end

    it { expect { chef_run }.to_not raise_error }
    it { is_expected.to install_package(%w(automake binutils bzip2 ca-certificates devscripts dpkg-dev fakeroot git gnupg iproute2 libffi-dev libncurses-dev libssl-dev libtool locales locales-all openjdk-21-jdk-headless openssh-client pkgconf rsync tar tzdata wget zlib1g-dev)) }
    it { is_expected.to install_build_essential('cinc-omnibus') }
    it { is_expected.to remove_package(%w(libpcre2-dev libselinux1-dev)) }
    it { is_expected.to upgrade_chef_ingredient('omnibus-toolchain') }
    it { is_expected.to create_group('omnibus') }
    it { is_expected.to create_user('omnibus') }
    it { is_expected.to create_file('/home/omnibus/.gitconfig') }
    it { is_expected.to create_file('/home/omnibus/load-omnibus-toolchain.sh') }
    it { is_expected.to create_file('/usr/local/share/ruby-docker-copy-patch.rb') }
  end

  context 'ubuntu - ppc64le' do
    platform 'ubuntu', '24.04'
    automatic_attributes['kernel']['machine'] = 'ppc64le'

    recipe do
      cinc_omnibus_builder 'default'
    end

    it do
      is_expected.to upgrade_chef_ingredient('omnibus-toolchain').with(
        rubygems_url: 'https://rubygems.cinc.sh',
        version: 'latest',
        channel: :stable,
        architecture: 'ppc64le',
        platform: nil,
        platform_version_compatibility_mode: true
      )
    end
  end

  context 'on opensuse' do
    platform 'opensuse', '15'

    recipe do
      cinc_omnibus_builder 'default'
    end

    it do
      is_expected.to upgrade_chef_ingredient('omnibus-toolchain').with(
        rubygems_url: nil,
        version: 'latest',
        channel: :stable,
        architecture: 'x86_64',
        platform: 'sles',
        platform_version_compatibility_mode: true
      )
    end
  end

  context 'on windows' do
    platform 'windows'

    recipe do
      cinc_omnibus_builder 'default'
    end

    it do
      is_expected.to install_chef_ingredient('omnibus-toolchain').with(
        rubygems_url: nil,
        version: 'latest',
        channel: :stable,
        architecture: 'x86_64',
        platform: nil,
        platform_version_compatibility_mode: true
      )
    end
  end

  context 'with externally managed toolchain' do
    platform 'ubuntu', '24.04'

    recipe do
      cinc_omnibus_builder 'default' do
        manage_toolchain false
      end
    end

    it { is_expected.to_not upgrade_chef_ingredient('omnibus-toolchain') }
  end

  context 'debian - ppc64le' do
    platform 'debian', '12'
    automatic_attributes['kernel']['machine'] = 'ppc64le'

    recipe do
      cinc_omnibus_builder 'default'
    end

    it do
      is_expected.to upgrade_chef_ingredient('omnibus-toolchain').with(
        rubygems_url: 'https://rubygems.cinc.sh',
        version: 'latest',
        channel: :stable,
        architecture: 'ppc64le',
        platform: nil,
        platform_version_compatibility_mode: true
      )
    end
  end

  context 'almalinux 8 - ppc64le' do
    platform 'almalinux', '8'
    automatic_attributes['kernel']['machine'] = 'ppc64le'

    recipe do
      cinc_omnibus_builder 'default'
    end

    it do
      is_expected.to upgrade_chef_ingredient('omnibus-toolchain').with(
        rubygems_url: nil,
        version: 'latest',
        channel: :stable,
        architecture: 'ppc64le',
        platform: nil,
        platform_version_compatibility_mode: true
      )
    end
  end

  context 'almalinux 9 - ppc64le' do
    platform 'almalinux', '9'
    automatic_attributes['kernel']['machine'] = 'ppc64le'

    recipe do
      cinc_omnibus_builder 'default'
    end

    it do
      is_expected.to upgrade_chef_ingredient('omnibus-toolchain').with(
        rubygems_url: 'https://rubygems.cinc.sh',
        version: 'latest',
        channel: :stable,
        architecture: 'ppc64le',
        platform: nil,
        platform_version_compatibility_mode: true
      )
    end
  end

  context 'almalinux 9 - s390x' do
    platform 'almalinux', '9'
    automatic_attributes['kernel']['machine'] = 's390x'

    recipe do
      cinc_omnibus_builder 'default'
    end

    it do
      is_expected.to upgrade_chef_ingredient('omnibus-toolchain').with(
        rubygems_url: 'https://rubygems.cinc.sh',
        version: 'latest',
        channel: :stable,
        architecture: 's390x',
        platform: nil,
        platform_version_compatibility_mode: true
      )
    end
  end

  context 'on oracle linux' do
    platform 'oracle', '9'

    recipe do
      cinc_omnibus_builder 'default' do
        manage_toolchain false
      end
    end

    it { expect { chef_run }.to_not raise_error }
    it { is_expected.to install_package(%w(automake bzip2 ca-certificates git glibc-langpack-en glibc-locale-source iproute java-17-openjdk-devel libffi-devel libtool openssh-clients perl-Digest-SHA perl-FindBin perl-IPC-Cmd perl-Time-Piece perl-bignum perl-lib pkgconf rpm-build rpm-sign rsync tar tzdata wget zlib-devel)) }
  end

  context 'on fedora' do
    platform 'fedora', '32'
    automatic_attributes['platform_version'] = '44'

    recipe do
      cinc_omnibus_builder 'default' do
        manage_toolchain false
      end
    end

    it { expect { chef_run }.to_not raise_error }
    it { is_expected.to install_package(%w(automake bzip2 ca-certificates git glibc-langpack-en glibc-locale-source iproute java-latest-openjdk-devel libffi-devel libtool openssh-clients perl-Digest-SHA perl-FindBin perl-IPC-Cmd perl-Time-Piece perl-bignum perl-lib pkgconf rpm-build rpm-sign rsync tar tzdata wget2-wget zlib-ng-compat-devel)) }
  end

  context 'with remove action' do
    platform 'ubuntu', '24.04'

    recipe do
      cinc_omnibus_builder 'default' do
        action :remove
      end
    end

    it { is_expected.to delete_file('/home/omnibus/.gitconfig') }
    it { is_expected.to delete_file('/home/omnibus/load-omnibus-toolchain.sh') }
    it { is_expected.to delete_file('/usr/local/share/ruby-docker-copy-patch.rb') }
    it { is_expected.to delete_directory('/var/cache/omnibus') }
  end
end
