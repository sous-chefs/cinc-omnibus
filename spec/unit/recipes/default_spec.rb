#
# Cookbook:: cinc-omnibus
# Spec:: default
#
# Copyright:: 2020, Cinc Project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require 'spec_helper'

describe 'cinc-omnibus::default' do
  context 'ubuntu' do
    platform 'ubuntu'

    it { expect { chef_run }.to_not raise_error }

    it do
      is_expected.to upgrade_chef_ingredient('omnibus-toolchain').with(
        rubygems_url: nil,
        version: 'latest',
        channel: :stable,
        architecture: 'x86_64',
        platform: nil,
        platform_version_compatibility_mode: true
      )
    end

    context 'ubuntu - ppc64le' do
      automatic_attributes['kernel']['machine'] = 'ppc64le'

      it { expect { chef_run }.to_not raise_error }
      it do
        is_expected.to upgrade_chef_ingredient('omnibus-toolchain').with(
          rubygems_url: 'https://packagecloud.io/cinc-project/stable',
          version: 'latest',
          channel: :stable,
          architecture: 'ppc64le',
          platform: nil,
          platform_version_compatibility_mode: true
        )
      end
    end
  end

  context 'opensuse' do
    platform 'opensuse'

    it { expect { chef_run }.to_not raise_error }
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

  context 'windows' do
    platform 'windows'

    it { expect { chef_run }.to_not raise_error }
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

  context 'debian - ppc64le' do
    platform 'debian'
    automatic_attributes['kernel']['machine'] = 'ppc64le'

    it { expect { chef_run }.to_not raise_error }
    it do
      is_expected.to upgrade_chef_ingredient('omnibus-toolchain').with(
        rubygems_url: 'https://packagecloud.io/cinc-project/stable',
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

    it { expect { chef_run }.to_not raise_error }
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

    it do
      is_expected.to upgrade_chef_ingredient('omnibus-toolchain').with(
        rubygems_url: 'https://packagecloud.io/cinc-project/stable',
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

    it do
      is_expected.to upgrade_chef_ingredient('omnibus-toolchain').with(
        rubygems_url: 'https://packagecloud.io/cinc-project/stable',
        version: 'latest',
        channel: :stable,
        architecture: 's390x',
        platform: nil,
        platform_version_compatibility_mode: true
      )
    end
  end
end
