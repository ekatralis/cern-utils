#!/usr/bin/env bash

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Run as root or with sudo"
  exit 1
fi

if [[ -f "/etc/os-release" ]]; then
    source /etc/os-release
else
    echo "Are you sure that you are running this in the correct os?"
    exit 1
fi

if ! [[ "$ID" == "ubuntu" || "$ID_LIKE" == *"ubuntu"* ]]; then
    echo "This script only works with ubuntu based systems"
    exit 1
fi

if [[ " $* " == *" --force "* ]]; then
    rm -rf /eos /etc/eos
    rm -f /etc/auto.eos /etc/auto.master.d/eos.autofs
    rm -f /etc/apt/sources.list.d/eos-client.list
    rm -f /etc/apt/sources.list.d/xrootd.list
fi

if [[ -e "/eos" || -e /etc/eos || -e /etc/auto.eos || -e /etc/auto.master.d/eos.autofs ]]; then
     echo "EOS appears to be already installed on this system. Use --force to force a clean reconfiguration"
     exit 1
fi

echo "[Installer] Configuring eos repositories and installing client"
# ensure utilities are available
apt update
apt install -y curl gpg lsb-release

# Setup the APT repositories holding the EOS package:
# Import the EOS GPG key of the repository
curl -sL http://storage-ci.web.cern.ch/storage-ci/storageci.key | sudo gpg --dearmor -o /etc/apt/trusted.gpg.d/storage-ci.gpg
# Import xrd GPG key
curl -L https://xrootd.web.cern.ch/repo/RPM-GPG-KEY.txt -o /etc/apt/trusted.gpg.d/xrootd.asc

# Create the APT repository configuration for EOS
echo "deb [arch=$(dpkg --print-architecture)] http://storage-ci.web.cern.ch/storage-ci/debian/eos/diopside $(lsb_release -cs) $(lsb_release -cs)/tag $(lsb_release -cs)/commit" | tee /etc/apt/sources.list.d/eos-client.list > /dev/null
# Same for xrootd
echo "deb [arch=$(dpkg --print-architecture)] https://xrootd.web.cern.ch/ubuntu $(lsb_release -cs) stable" > /etc/apt/sources.list.d/xrootd.list

# Install the eos fuse client
apt update
apt install -y eos-fusex autofs

# Create eos mountpoint
mkdir -p /eos

echo "[Installer] Creating all EOS fuse config files created in /etc/eos/."
mkdir -p /etc/eos
# Create all eos config files
for letter in {a..z}; do
  # Create /etc/eos/fuse.home-<letter>.conf
  cat > "/etc/eos/fuse.home-${letter}.conf" <<EOF
{"name": "home-${letter}", "hostport": "eoshome-${letter}.cern.ch", "remotemountdir": "/eos/user/${letter}/"}
EOF

  # Create /etc/eos/fuse.project-<letter>.conf
  cat > "/etc/eos/fuse.project-${letter}.conf" <<EOF
{"name": "project-${letter}", "hostport": "eosproject-${letter}.cern.ch", "remotemountdir": "/eos/project/${letter}/"}
EOF

  echo "[Installer] Created home and project configs in /etc/eos/ for letter: ${letter}"
done

# Create /etc/eos/fuse.project.conf
cat > "/etc/eos/fuse.project.conf" <<EOF
{"name":"project","hostport":"eosproject-fuse.cern.ch","remotemountdir":"/eos/project/","rm-rf-protect-levels":1}
EOF

# Create /etc/eos/fuse.user.conf
cat > "/etc/eos/fuse.user.conf" <<EOF
{"name":"user","hostport":"eosuser-fuse.cern.ch","remotemountdir":"/eos/user/","rm-rf-protect-levels":2}
EOF

echo "[Installer] Creating eos autofs config in /etc/auto.eos"
cat > "/etc/auto.eos" <<EOF
user      -fstype=eosx,fsname=user       :eosxd
project   -fstype=eosx,fsname=project    :eosxd
EOF
for letter in {a..z}; do
  cat >> "/etc/auto.eos" <<EOF
home-${letter}    -fstype=eosx,fsname=home-${letter}     :eosxd
EOF
done

for letter in {a..z}; do
  cat >> "/etc/auto.eos" <<EOF
project-${letter} -fstype=eosx,fsname=project-${letter}  :eosxd
EOF

done

echo "[Installer] Creating eos autofs config in /etc/auto.master.d/eos.autofs"
cat > "/etc/auto.master.d/eos.autofs" <<EOF
/eos /etc/auto.eos --timeout=600
EOF

echo "[Installer] Enabling autofs browse_mode"
sed -i \
  's/^[[:space:]]*browse_mode[[:space:]]*=.*/browse_mode = yes/' \
  /etc/autofs.conf

# Restart autofs service to make eos work
echo "[Installer] Restarting autofs service"
systemctl restart autofs

# Install Kerberos utils to access EOS
echo "[Installer] Installing kerberos utils"
apt install -y krb5-user

echo "[Installer] Configuring xrootd utils"
apt install -y xrootd-client

echo "[Installer] Finished configuring eos. Ensure an active kerberos token is present by running:"
echo "[Installer] kinit yourusername@CERN.CH"
echo "[Installer] Then ensure you can access your desired eos folder"

