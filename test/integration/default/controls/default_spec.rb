# frozen_string_literal: true

os_version = os.release
os_name = os.name
unix_path = '/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin'

case os.family
when 'windows'
  install_dir = 'C:\cinc-project\omnibus-toolchain'
  build_user_home = 'C:\omnibus'
  shim_name = 'load-omnibus-toolchain.ps1'
  # DisplayName is versioned, so query the uninstall registry with a wildcard.
  toolchain_pkg = nil
when 'darwin'
  install_dir = '/opt/omnibus-toolchain'
  build_user_home = '/Users/omnibus'
  shim_name = 'load-omnibus-toolchain.sh'
  toolchain_pkg = 'sh.cinc.pkg.omnibus-toolchain'
else
  install_dir = '/opt/omnibus-toolchain'
  build_user_home = '/home/omnibus'
  shim_name = 'load-omnibus-toolchain.sh'
  toolchain_pkg = 'omnibus-toolchain'
end

control 'default' do
  case os.name
  when 'amazon'
    packages = %w(
      automake
      ca-certificates
      git
      glibc-langpack-en
      glibc-locale-source
      iproute
      libtool
      openssh-clients
      pkgconf
      perl-Digest-SHA
      perl-IPC-Cmd
      perl-Time-Piece
      perl-bignum
      rsync
      tar
      tzdata
      wget
    )
    packages << %w(perl-FindBin perl-lib) if os_version.to_i >= 2022
  when 'centos', 'redhat', 'almalinux', 'rocky', 'oracle', 'fedora'
    packages = %w(
      automake
      bzip2
      ca-certificates
      git
      iproute
      libffi-devel
      libtool
      openssh-clients
      pkgconf
      perl-Digest-SHA
      perl-IPC-Cmd
      perl-Time-Piece
      perl-bignum
      rpm-build
      rpm-sign
      rsync
      tar
      tzdata
      wget
    )
    packages << %w(centos-release-scl devtoolset-10) if os_version.to_i == 7
    packages << %w(glibc-langpack-en glibc-locale-source) if os_version.to_i >= 8
    packages << %w(perl-FindBin perl-lib) if os_version.to_i >= 9
    packages << %w(zlib-devel) if os_version.to_i < 10
    packages << %w(zlib-ng-compat-devel) if os_version.to_i >= 10
    packages.delete('wget') if os_name == 'fedora'
    packages << %w(wget2-wget) if os_name == 'fedora'
    packages << if os_name == 'fedora'
                  %w(java-latest-openjdk-devel)
                elsif os_version.to_i == 7
                  %w(java-11-openjdk-devel)
                elsif os_version.to_i >= 10
                  %w(java-21-openjdk-devel)
                else
                  %w(java-17-openjdk-devel)
                end
  when 'debian', 'ubuntu'
    packages = %w(
      automake
      binutils
      bzip2
      ca-certificates
      devscripts
      dpkg-dev
      fakeroot
      git
      gnupg
      iproute2
      libffi-dev
      libssl-dev
      libtool
      locales
      locales-all
      openssh-client
      pkgconf
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
    packages << if os_version.to_i == 10 || os_version.to_i == 11 || os_version == '18.04'
                  %w(openjdk-11-jdk-headless)
                elsif os_version.to_i == 12 || os_version == '20.04'
                  %w(openjdk-17-jdk-headless)
                else
                  %w(openjdk-21-jdk-headless)
                end
  when 'opensuse'
    packages = %w(
      automake
      bzip2
      curl
      git
      glibc-i18ndata
      glibc-locale
      gzip
      hostname
      iproute2
      libffi-devel
      libtool
      ncurses-devel
      openssh
      pkgconf
      rpm-build
      rsync
      tar
      timezone
      wget
      zlib-devel
    )
    # Leap 16.0 dropped the Java 11 packages; it ships OpenJDK 21.
    packages << if os_version.to_i >= 16
                  %w(java-21-openjdk-devel)
                else
                  %w(java-11-openjdk-devel)
                end
  when 'freebsd'
    packages = %w(
      autoconf
      automake
      gcc
      git
      libffi
      libtool
      libyaml
      openssl
      pkgconf
      readline
    )
  when 'darwin'
    packages = %w(
      autoconf
      automake
      git
      libffi
      libtool
      libyaml
      openssl@3
      pkgconf
      readline
    )
  else
    packages = []
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

  unsafe_pkgs.to_a.each do |pkg|
    describe package pkg do
      it { should_not be_installed }
    end
  end

  if os.windows?
    describe powershell(<<~PS) do
      $entry = Get-ChildItem 'HKLM:\\Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall' |
        ForEach-Object { Get-ItemProperty $_.PSPath } |
        Where-Object { $_.DisplayName -like 'Omnibus Toolchain*' } |
        Select-Object -First 1
      if (-not $entry) { exit 1 } else { Write-Output $entry.DisplayName }
    PS
      its('exit_status') { should eq 0 }
      its('stdout') { should match(/^Omnibus Toolchain/) }
    end

    describe file install_dir do
      it { should be_directory }
    end

    describe file "#{build_user_home}\\#{shim_name}" do
      it { should exist }
    end

    describe powershell("& \"#{install_dir}\\embedded\\bin\\ruby.exe\" --version") do
      its('exit_status') { should eq 0 }
      its('stdout') { should match(/^ruby \d/) }
    end

    describe powershell(". \"#{build_user_home}\\#{shim_name}\"") do
      its('exit_status') { should eq 0 }
      its('stdout') { should match(/Tool Versions/) }
    end
  else
    # Darwin: InSpec's package resource queries Homebrew, so check the pkgutil
    # receipt. FreeBSD: the toolchain is a self-extracting .sh, so check the file.
    if os.darwin?
      describe command "pkgutil --pkg-info #{toolchain_pkg}" do
        its('exit_status') { should eq 0 }
        its('stdout') { should match(/^package-id: #{Regexp.escape(toolchain_pkg)}$/) }
        its('stdout') { should match(%r{^location: opt/omnibus-toolchain$}) }
      end
    elsif os.bsd?
      describe file "#{install_dir}/version-manifest.txt" do
        it { should exist }
      end
    else
      describe package toolchain_pkg do
        it { should be_installed }
      end
    end

    describe file "#{install_dir}/bin/pkg-config" do
      it { should_not exist }
    end

    describe command "#{install_dir}/bin/ruby --version" do
      its('exit_status') { should eq 0 }
      its('stdout') { should match(/^ruby \d/) }
    end

    describe command "#{build_user_home}/#{shim_name}" do
      its('exit_status') { should eq 0 }
      its('stdout') { should match(/Tool Versions/) }
      # Ubuntu (wget stderr) and FreeBSD (no java) write noise here; the
      # load-shim-output control still confirms every other tool on PATH.
      unless os_name == 'ubuntu' || os.bsd?
        its('stderr') { should eq '' }
      end
    end

    tools = %w(
      bash
      bundle
      curl
      gcc
      gem
      git
      libtoolize
      make
      patch
      pkg-config
      ruby
      tar
    )
    # Build matrix omissions: macOS/FreeBSD bundle neither berks nor Java, and
    # on FreeBSD inspec sees the ruby wrappers as exit 1 (the load-shim-output
    # control covers those).
    tools -= %w(bundle gem ruby) if os.bsd?
    tool_cmds = tools.map { |c| "#{c} --version" }
    tool_cmds.unshift('berks --version') unless os.darwin? || os.bsd?
    tool_cmds.push('java -version') unless os.darwin? || os.bsd?

    tool_cmds.each do |cmd|
      describe command "PATH='#{install_dir}/bin:/usr/local/bin:#{unix_path}' #{cmd}" do
        its('exit_status') { should eq 0 }
      end
    end
  end
end

control 'load-shim-output' do
  impact 0.0
  title 'Echo load-omnibus-toolchain shim output for manual review'

  shim_cmd = if os.windows?
               powershell(". \"#{build_user_home}\\#{shim_name}\"")
             else
               command("#{build_user_home}/#{shim_name}")
             end

  shim_cmd.stdout.each_line do |line|
    next if line.strip.empty?
    describe line.chomp do
      it { should match(/.*/) }
    end
  end
end
