# frozen_string_literal: true

require 'spec_helper'

describe 'cinc_omnibus_msys2' do
  step_into :cinc_omnibus_msys2
  platform 'windows'

  # Stub the gpg key guard, the daemon-present guard, and the mirror-listing
  # HTTP GET (no network).
  before do
    stub_command(/--list-keys/).and_return(false)
    allow_any_instance_of(CincOmnibus::Cookbook::Helpers).to receive(:msys2_gpg_daemons_running?).and_return(true)
    allow_any_instance_of(Chef::HTTP::Simple).to receive(:get)
      .and_return('msys2-base-x86_64-20250830.sfx.exe msys2-base-x86_64-20260611.sfx.exe')
  end

  context 'with defaults' do
    recipe do
      cinc_omnibus_msys2 'default'
    end

    it { expect { chef_run }.to_not raise_error }

    it 'downloads the newest dated MSYS2 base archive from the mirror scan' do
      archive = chef_run.find_resource('remote_file', ::File.join(Chef::Config[:file_cache_path], 'msys2-base-x86_64.sfx.exe'))
      expect(Array(archive.source).first)
        .to eq('https://repo.msys2.org/distrib/x86_64/msys2-base-x86_64-20260611.sfx.exe')
    end

    it 'imports the vendored signing key and fetches the detached signature' do
      expect(chef_run).to create_cookbook_file(/msys2-signing-key\.asc\z/)
        .with(source: 'msys2-signing-key.asc', cookbook: 'cinc-omnibus')
      expect(chef_run).to run_execute('import msys2 signing key')
        .with(command: /--import .*msys2-signing-key\.asc/)
      expect(chef_run).to create_remote_file(/msys2-base-x86_64\.sfx\.exe\.sig\z/)
    end

    it 'verifies the archive signature before extracting' do
      expect(chef_run).to run_execute('verify msys2 base signature')
        .with(command: /gpg\.exe" --homedir ".* --verify ".*\.sfx\.exe\.sig" ".*\.sfx\.exe"/)
    end

    it 'self-extracts the sfx into the install dir parent' do
      expect(chef_run).to run_execute('extract msys2 base')
        .with(command: %r{msys2-base-x86_64\.sfx\.exe" -y -o"C:/"})
    end

    it { is_expected.to run_execute('initialize msys2') }

    it 'declares the IgnorePkg freeze block' do
      # only_if { pacman.conf exists } is false on the host, so assert declared, not run.
      expect(chef_run.ruby_block('set msys2 IgnorePkg')).to_not be_nil
    end

    it 'refreshes and installs the ucrt64 toolchain' do
      expect(chef_run).to run_execute('install msys2 packages')
        .with(command: /pacman -Sy --needed --noconfirm .*mingw-w64-ucrt-x86_64-toolchain/)
    end

    it { is_expected.to_not run_execute('install pinned msys2 packages') }

    it 'reaps the gpg-agent/dirmngr daemons so the converge can return' do
      expect(chef_run).to run_execute('stop msys2 gpg daemons')
        .with(command: /taskkill .*gpg-agent\.exe .*dirmngr\.exe/, returns: [0, 128])
    end
  end

  context 'with verify_signature false' do
    recipe do
      cinc_omnibus_msys2 'default' do
        verify_signature false
      end
    end

    it { is_expected.to_not create_cookbook_file(/msys2-signing-key\.asc\z/) }
    it { is_expected.to_not run_execute('import msys2 signing key') }

    it { is_expected.to_not run_execute('verify msys2 base signature') }
  end

  context 'with pinned_packages' do
    recipe do
      cinc_omnibus_msys2 'default' do
        pinned_packages %w(https://example.com/mingw-w64-ucrt-x86_64-gcc-14.2.0-3-any.pkg.tar.zst)
      end
    end

    it 'installs the pinned packages with pacman -U' do
      expect(chef_run).to run_execute('install pinned msys2 packages')
        .with(command: %r{pacman -U --needed --noconfirm https://example.com/.*gcc-14\.2\.0-3})
    end
  end

  context 'on :remove' do
    recipe do
      cinc_omnibus_msys2 'default' do
        action :remove
      end
    end

    it { is_expected.to delete_directory('C:/msys64') }
  end
end
