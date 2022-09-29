os_version = os.release

control 'default' do
  case os.name
  when 'amazon'
    packages = %w(
      automake
      ca-certificates
      iproute
      openssh-clients
      rsync
      tar
      tzdata
      wget
    )
  when 'centos', 'redhat'
    packages = %w(
      automake
      bzip2
      ca-certificates
      iproute
      libffi-devel
      openssh-clients
      rpm-build
      rpm-sign
      rsync
      tar
      tzdata
      wget
      zlib-devel
    )
    packages << %w(glibc-langpack-en glibc-locale-source) if os_version.to_i >= 8
  when 'debian', 'ubuntu'
    packages = %w(
      automake
      ca-certificates
      iproute2
      libssl-dev
      locales-all
      openssh-client
      rsync
      tzdata
      wget
    )
  when 'opensuse'
    packages = %w(
      automake
      curl
      gzip
      hostname
      iproute2
      openssh
      rpm-build
      rsync
      tar
      timezone
      wget
    )
  end

  packages.flatten.sort.each do |pkg|
    describe package pkg do
      it { should be_installed }
    end
  end

  describe package 'omnibus-toolchain' do
    it { should be_installed }
  end

  describe command '/opt/omnibus-toolchain/bin/ruby --version' do
    its('exit_status') { should eq 0 }
  end

  describe command '/home/omnibus/load-omnibus-toolchain.sh' do
    its('exit_status') { should eq 0 }
    its('stderr') { should eq '' }
  end

  describe command 'localectl' do
    its('stdout') { should match /System Locale: LANG=en_US.UTF-8/ }
  end
end
