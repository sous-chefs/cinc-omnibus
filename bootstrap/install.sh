#!/bin/sh
set -ex

REPO_BRANCH="${REPO_BRANCH:-main}"
CHEF_INGREDIENT_BRANCH="${CHEF_INGREDIENT_BRANCH:-main}"

if [ -e /usr/bin/apt-get ] ; then
  apt-get update
  apt-get -y install curl unzip
elif [ -e /usr/bin/dnf ] ; then
  dnf -y install curl unzip
elif [ -e /usr/bin/yum ] ; then
  yum -y install curl unzip
elif [ "$(uname -s)" = "FreeBSD" ] ; then
  # FreeBSD lacks bash, which the omnitruck install.sh below pipes through.
  pkg install -y curl unzip bash
fi
# macOS ships with curl + unzip + bash; no prereq install needed.

if [ ! -e /opt/cinc/bin/cinc-client ] ; then
  curl https://omnitruck.cinc.sh/install.sh | bash
fi

rm -rf /tmp/cinc
mkdir -p /tmp/cinc/cache /tmp/cinc/cookbooks
chmod -R 777 /tmp/cinc

curl -L -o /tmp/cinc/cinc-omnibus.zip \
  "https://github.com/sous-chefs/cinc-omnibus/archive/refs/heads/${REPO_BRANCH}.zip"
curl -L -o /tmp/cinc/chef-ingredient.zip \
  "https://github.com/chef-cookbooks/chef-ingredient/archive/refs/heads/${CHEF_INGREDIENT_BRANCH}.zip"

cd /tmp/cinc
unzip -q cinc-omnibus.zip
unzip -q chef-ingredient.zip
mv "cinc-omnibus-${REPO_BRANCH}" cookbooks/cinc-omnibus
mv "chef-ingredient-${CHEF_INGREDIENT_BRANCH}" cookbooks/chef-ingredient
cp -r cookbooks/cinc-omnibus/bootstrap/cookbooks/cinc-omnibus-bootstrap cookbooks/
cp cookbooks/cinc-omnibus/bootstrap/client.rb client.rb
cp cookbooks/cinc-omnibus/bootstrap/runlist/builder.json dna.json

/opt/cinc/bin/cinc-client \
  --local-mode \
  --config /tmp/cinc/client.rb \
  --log_level auto \
  --force-formatter \
  --no-color \
  --json-attributes /tmp/cinc/dna.json \
  --chef-zero-port 8889

if [ -e /usr/bin/apt-get ] ; then
  apt-get -y purge cinc
  apt-get -y autoremove
elif [ -e /usr/bin/dnf ] ; then
  dnf -y remove cinc
elif [ -e /usr/bin/yum ] ; then
  yum -y remove cinc
elif [ "$(uname -s)" = "FreeBSD" ] ; then
  pkg delete -y cinc
fi
# On macOS the rm -rf below removes /opt/cinc directly; nothing else to undo.

rm -rf /tmp/cinc /opt/cinc
