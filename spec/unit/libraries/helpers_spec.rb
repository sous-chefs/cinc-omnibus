# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../libraries/helpers'

RSpec.describe CincOmnibus::Cookbook::Helpers do
  subject(:helper) { Class.new { include CincOmnibus::Cookbook::Helpers }.new }

  describe '#to_msys_path' do
    it 'converts a Windows drive path to MSYS POSIX form' do
      expect(helper.to_msys_path('C:\\Users\\vagrant\\cache')).to eq('/c/Users/vagrant/cache')
    end

    it 'converts a mixed-separator drive path' do
      expect(helper.to_msys_path('C:/Users/vagrant/cache')).to eq('/c/Users/vagrant/cache')
    end

    it 'lowercases the drive letter' do
      expect(helper.to_msys_path('D:\\tools')).to eq('/d/tools')
    end

    it 'leaves a path without a drive letter unchanged' do
      expect(helper.to_msys_path('/tmp/cache')).to eq('/tmp/cache')
    end
  end

  describe '#mac_build_user_secure_token?' do
    before { allow(helper).to receive(:mac_os_x?).and_return(true) }

    def sysadminctl(stderr)
      instance_double(Mixlib::ShellOut, stdout: '', stderr: stderr)
        .tap { |s| allow(helper).to receive(:shell_out).and_return(s) }
    end

    it 'is true when sysadminctl reports the token ENABLED' do
      sysadminctl('Secure token is ENABLED for user omnibus')
      expect(helper.mac_build_user_secure_token?('omnibus')).to be true
    end

    it 'is false when sysadminctl reports the token DISABLED' do
      sysadminctl('Secure token is DISABLED for user omnibus')
      expect(helper.mac_build_user_secure_token?('omnibus')).to be false
    end

    it 'is false when sysadminctl is unavailable' do
      allow(helper).to receive(:shell_out).and_raise(Errno::ENOENT)
      expect(helper.mac_build_user_secure_token?('omnibus')).to be false
    end

    it 'is false off macOS and does not shell out' do
      allow(helper).to receive(:mac_os_x?).and_return(false)
      expect(helper).not_to receive(:shell_out)
      expect(helper.mac_build_user_secure_token?('omnibus')).to be false
    end
  end

  describe '#mac_brew_prefix' do
    it 'is /opt/homebrew on Apple Silicon' do
      allow(helper).to receive(:arm?).and_return(true)
      expect(helper.mac_brew_prefix).to eq('/opt/homebrew')
    end

    it 'is /usr/local on Intel' do
      allow(helper).to receive(:arm?).and_return(false)
      expect(helper.mac_brew_prefix).to eq('/usr/local')
    end
  end

  describe '#gitlab_runner_mac_binary' do
    it 'resolves under the Homebrew prefix' do
      allow(helper).to receive(:arm?).and_return(true)
      expect(helper.gitlab_runner_mac_binary).to eq('/opt/homebrew/bin/gitlab-runner')
    end
  end
end
