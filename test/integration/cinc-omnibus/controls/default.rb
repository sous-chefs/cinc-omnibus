os_version = os.release
path = '/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin'

control 'default' do
  case os.name
  when 'amazon'
    packages = %w(
      automake
      ca-certificates
      glibc-langpack-en
      glibc-locale-source
      iproute
      libtool
      openssh-clients
      perl-Digest-SHA
      perl-IPC-Cmd
      perl-bignum
      rsync
      tar
      tzdata
      wget
    )
    packages << %w(perl-FindBin perl-lib) if os_version.to_i >= 2022
  when 'centos', 'redhat', 'almalinux', 'rocky'
    packages = %w(
      automake
      bzip2
      ca-certificates
      iproute
      libffi-devel
      libtool
      openssh-clients
      perl-Digest-SHA
      perl-IPC-Cmd
      perl-bignum
      rpm-build
      rpm-sign
      rsync
      tar
      tzdata
      wget
      zlib-devel
    )
    packages << %w(centos-release-scl devtoolset-10) if os_version.to_i == 7
    packages << %w(glibc-langpack-en glibc-locale-source) if os_version.to_i >= 8
    packages << %w(perl-FindBin perl-lib) if os_version.to_i >= 9
  when 'debian', 'ubuntu'
    packages = %w(
      automake
      binutils
      bzip2
      ca-certificates
      devscripts
      dpkg-dev
      fakeroot
      gnupg
      iproute2
      libffi-dev
      libssl-dev
      libtool
      locales
      locales-all
      openssh-client
      rsync
      tar
      tzdata
      wget
      zlib1g-dev
    )
    packages << if os_version.to_i == 9 || os_version == '18.04'
                  %w(libncurses5-dev)
                else
                  %w(libncurses-dev)
                end
  when 'opensuse'
    packages = %w(
      automake
      curl
      glibc-i18ndata
      glibc-locale
      gzip
      hostname
      iproute2
      libtool
      openssh
      rpm-build
      rsync
      tar
      timezone
      wget
    )
  end

  case os.family
  when 'amazon', 'redhat', 'fedora', 'suse'
    unsafe_pkgs = %w(pcre2-devel libselinux-devel)
  when 'debian'
    unsafe_pkgs = %w(libpcre2-dev libselinux1-dev)
  end

  packages.flatten.sort.each do |pkg|
    describe package pkg do
      it { should be_installed }
    end
  end

  unsafe_pkgs.each do |pkg|
    describe package pkg do
      it { should_not be_installed }
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

  [
    'bash --version',
    'berks --version',
    'bundle --version',
    'curl --version',
    'gcc --version',
    'gem --version',
    'git --version',
    'java -version',
    'libtoolize --version',
    'make --version',
    'patch --version',
    'pkg-config --version',
    'ruby --version',
    'tar --version',
  ].each do |cmd|
    describe command "PATH='/opt/omnibus-toolchain/bin:/usr/local/bin:#{path}' #{cmd}" do
      its('exit_status') { should eq 0 }
    end
  end
end
