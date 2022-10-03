#
# Cookbook:: cinc-omnibus
# Recipe:: default
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

package omnibus_packages

build_essential 'cinc-omnibus'

chef_ingredient 'omnibus-toolchain' do
  version 'latest'
  channel :stable
  architecture node['kernel']['machine']
  platform 'sles' if platform?('opensuseleap')
  platform_version_compatibility_mode true
  action(windows? ? :install : :upgrade)
end

group 'omnibus' do
  append true
end

user 'omnibus' do
  home build_user_home
  group 'omnibus'
  shell build_user_shell
end

directory build_user_home do
  owner 'omnibus'
  group 'omnibus'
end

directory '/var/cache/omnibus' do
  owner 'omnibus'
  group 'omnibus'
end

directory Chef::Config[:file_cache_path] do
  recursive true
end

# Ensure every platform has a sane .gitconfig
file File.join(build_user_home, '.gitconfig') do
  owner   'omnibus'
  group   'omnibus'
  mode    '0644'
  content <<-EOH.gsub(/^ {4}/, '')
    # This file is written by Chef for #{node['fqdn']}.
    # Do NOT modify this file by hand.

    [user]
      ; Set a sane user name and email. This makes git happy and prevents
      ; spammy output on each git command.
      name  = Omnibus
      email = omnibus@cinc.sh
    [color]
      ; Since this is a build machine, we do not want colored output.
      ui = false
    [core]
      editor = $EDITOR
      whitespace = fix
    [apply]
      whitespace = fix
    [push]
      default = tracking
    [branch]
      autosetuprebase = always
    [pull]
      rebase = preserve
  EOH
end

omnibus_env['OMNIBUS_TOOLCHAIN_INSTALL_DIR'] << toolchain_install_dir
omnibus_env['SSL_CERT_FILE'] << windows_safe_path_join(toolchain_install_dir, 'embedded', 'ssl', 'certs', 'cacert.pem')
omnibus_env['PATH'] << File.join(toolchain_install_dir, 'bin')
omnibus_env['PATH'] << '/usr/local/bin'
omnibus_path = omnibus_env.delete('PATH').uniq.join(File::PATH_SEPARATOR)

file ::File.join(build_user_home, 'load-omnibus-toolchain.sh') do
  content <<~EOH
    #!/usr/bin/env bash

    ###################################################################
    # Load the base Omnibus environment
    ###################################################################
    export PATH="#{omnibus_path}:$PATH"
    #{omnibus_env.map { |k, v| "export #{k}=#{v.first}" }.join("\n")}
    ###################################################################
    # Query tool versions
    ###################################################################

    echo ""
    echo "========================================"
    echo "= Tool Versions"
    echo "========================================"
    echo ""

    echo "$(head -1 /opt/omnibus-toolchain/version-manifest.txt)"
    echo ""

    echo "Bash.........$(bash --version | head -1)"
    echo "Berkshelf....$(berks --version | head -1)"
    echo "Bundler......$(bundle --version | head -1)"
    echo "Curl.........$(curl --version | head -1)"
    echo "GCC..........$(gcc --version | head -1)"
    echo "Git..........$(git --version | head -1)"
    echo "Java.........$(java -version 2>&1 | head -1)"
    echo "Make.........$(make --version | head -1)"
    echo "Patch........$(patch --version | head -1)"
    echo "Pkg-config...$(pkg-config --version | head -1)"
    echo "Ruby.........$(ruby --version | head -1)"
    echo "RubyGems.....$(gem --version | head -1)"
    echo "Tar..........$(tar --version | head -1)"

    echo ""
    echo "========================================"
  EOH
  owner 'omnibus'
  group 'omnibus'
  mode '0755'
end

cookbook_file '/usr/local/share/ruby-docker-copy-patch.rb'
