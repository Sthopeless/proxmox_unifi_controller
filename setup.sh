#!/usr/bin/env bash

# Setup script environment
set -o errexit  #Exit immediately if a pipeline returns a non-zero status
set -o errtrace #Trap ERR from shell functions, command substitutions, and commands from subshell
set -o nounset  #Treat unset variables as an error
set -o pipefail #Pipe will exit with last non-zero status if applicable
shopt -s expand_aliases
alias die='EXIT=$? LINE=$LINENO error_exit'
trap die ERR
trap 'die "Script interrupted."' INT

function error_exit() {
  trap - ERR
  local DEFAULT='Unknown failure occured.'
  local REASON="\e[97m${1:-$DEFAULT}\e[39m"
  local FLAG="\e[91m[ERROR:LXC] \e[93m$EXIT@$LINE"
  msg "$FLAG $REASON"
  exit $EXIT
}
function msg() {
  local TEXT="$1"
  echo -e "$TEXT"
}

# Prepare container OS
msg "Setting up container OS..."
sed -i "/$LANG/ s/\(^# \)//" /etc/locale.gen
locale-gen >/dev/null
apt-get -y purge openssh-{client,server} >/dev/null
apt-get autoremove >/dev/null

# Update container OS
msg "Updating container OS..."
apt-get update >/dev/null
apt-get -qqy upgrade &>/dev/null

# Install prerequisites
msg "Installing prerequisites..."
apt-get -qqy install \
    curl &>/dev/null

# Customize Docker configuration
msg "Customizing Docker..."
DOCKER_CONFIG_PATH='/etc/docker/daemon.json'
mkdir -p $(dirname $DOCKER_CONFIG_PATH)
cat >$DOCKER_CONFIG_PATH <<'EOF'
{
  "log-driver": "journald"
}
EOF

# Install Docker
msg "Installing Docker..."
sh <(curl -sSL https://get.docker.com) &>/dev/null

# Install Portainer
msg "Installing Portainer..."
FOLDER_PORTAINER='/docker/portainer'
mkdir -p $(dirname $FOLDER_PORTAINER)
docker run -d \
  -p 8000:8000 \
  -p 9000:9000 \
  --label com.centurylinklabs.watchtower.enable=true \
  --name=portainer \
  --restart=always \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v /docker/portainer:/data \
  portainer/portainer-ce &>/dev/null

# Install Watchtower
msg "Installing Watchtower..."
docker run -d \
  --name watchtower \
  -v /var/run/docker.sock:/var/run/docker.sock \
  containrrr/watchtower \
  --cleanup \
  --label-enable &>/dev/null

# Install VSCode
msg "Installing VSCode..."
FOLDER_VSCODE='/docker/vscode'
mkdir -p $(dirname $FOLDER_VSCODE)
docker run -d \
  --name=vscode \
  -e TZ=Europe/Amsterdam \
  -p 8443:8443 \
  --label com.centurylinklabs.watchtower.enable=true \
  -v /docker/vscode:/config \
  -v /docker:/config/workspace/Server \
  --restart unless-stopped \
  ghcr.io/linuxserver/code-server &>/dev/null

# Install UNIFI Controller (linuxserver)
msg "Installing UNIFI Controller..."
FOLDER_UNIFI='/docker/unifi_controller'
mkdir -p $(dirname $FOLDER_UNIFI)
docker run -d \
  --name=unifi-controller \
  -e PUID=1000 \
  -e PGID=1000 \
  -e MEM_LIMIT=1024M \
  -e MEM_STARTUP=1024M \
  -p 3478:3478/udp \
  -p 10001:10001/udp \
  -p 8080:8080 \
  -p 8443:8443 \
  -p 1900:1900/udp \
  -p 8843:8843 \
  -p 8880:8880 \
  -p 6789:6789 \
  -p 5514:5514/udp \
  -v /docker/unifi_controller:/config \
  --restart unless-stopped \
  --label com.centurylinklabs.watchtower.enable=true \
  ghcr.io/linuxserver/unifi-controller:latest &>/dev/null


# Customize container
msg "Customizing container..."
rm /etc/motd # Remove message of the day after login
rm /etc/update-motd.d/10-uname # Remove kernel information after login
touch ~/.hushlogin # Remove 'Last login: ' and mail notification after login
GETTY_OVERRIDE="/etc/systemd/system/container-getty@1.service.d/override.conf"
mkdir -p $(dirname $GETTY_OVERRIDE)
cat << EOF > $GETTY_OVERRIDE
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin root --noclear --keep-baud tty%I 115200,38400,9600 \$TERM
EOF
systemctl daemon-reload
systemctl restart $(basename $(dirname $GETTY_OVERRIDE) | sed 's/\.d//')

# Cleanup container
msg "Cleanup..."
rm -rf /setup.sh /var/{cache,log}/* /var/lib/apt/lists/*
