name              'cinc-omnibus'
maintainer        'Sous Chefs'
maintainer_email  'help@sous-chefs.org'
license           'Apache-2.0'
description       'Installs/Configures cinc-omnibus'
version           '1.0.1'
chef_version      '>= 16.0'
issues_url        'https://github.com/sous-chefs/cinc-omnibus'
source_url        'https://github.com/sous-chefs/cinc-omnibus/issues'

%w(redhat centos scientific oracle amazon fedora debian ubuntu suse opensuseleap).each do |os|
  supports os
end

depends 'chef-ingredient'
