#!/bin/bash
set -e

if [ "$EUID" -ne 0 ]
  then echo "Please run as root"
  exit
fi

hostnamectl set-hostname pibox
sed -i 's/raspberrypi/pibox/' /etc/hosts

# Unlimited bash history https://stackoverflow.com/a/19533853
sed -i 's/HISTSIZE=1000//' /home/pi/.bashrc
sed -i 's/HISTFILESIZE=2000//' /home/pi/.bashrc
cat <<EOF >> /home/pi/.bashrc
export HISTFILESIZE=
export HISTSIZE=
export HISTTIMEFORMAT="[%F %T] "
export HISTFILE=~/.bash_eternal_history
PROMPT_COMMAND="history -a; \$PROMPT_COMMAND"
EOF

cp /home/pi/.bashrc /root/.bashrc

apt-get update -yqq
apt-get full-upgrade -yqq
apt-get autoremove -yqq
apt-get autoclean -yqq
apt-get install -yqq vim lvm2 openssh-server raspberrypi-kernel-headers

# Reduce logging and store in memory to reduce EMMC wear
sed -i 's/.MaxLevelStore.*/MaxLevelStore=info/' /etc/systemd/journald.conf
sed -i 's/.MaxLevelSyslog.*/MaxLevelSyslog=info/' /etc/systemd/journald.conf
sed -i "s/#Storage.*/Storage=volatile/" /etc/systemd/journald.conf
systemctl restart systemd-journald.service

# Add tmpfs at /tmp to reduce EMMC wear
echo "tmpfs /var/tmp tmpfs defaults,noatime,nosuid,nodev,noexec,mode=0755,size=1M 0 0" >> /etc/fstab

# Enable Fan Support
git clone https://github.com/kubesail/pibox-os.git && \
  cd pibox-os/pwm-fan && \
  tar zxvf bcm2835-1.68.tar.gz && cd bcm2835-1.68 && \
  ./configure && make && make install && cd ../ && \
  make && make install && echo "PIBOX_RELEASE=$(git rev-parse --short HEAD)" > /etc/pibox-release && cd ../.. && rm -rf pibox-os

# Display driver
curl -s https://raw.githubusercontent.com/kubesail/pibox-os/main/setup-display.sh | bash

# SSH Config
echo "TCPKeepAlive yes" >> /etc/ssh/sshd_config
touch /boot/ssh

# Kernel settings
grep -qxF 'cgroup_enable=memory cgroup_memory=1' /boot/cmdline.txt || sed -i 's/$/ cgroup_enable=memory cgroup_memory=1/' /boot/cmdline.txt
# Show text output during startup / shutdown (useful if reboot hangs)
sed -i 's/quiet splash plymouth.ignore-serial-consoles//' /boot/cmdline.txt


# Swap
swapoff -a
dphys-swapfile swapoff
sysctl -w vm.swappiness=1
sed -i 's/vm.swappiness=.*/vm.swappiness=1/' /etc/sysctl.conf

#!/bin/bash
set -e

if [ "$EUID" -ne 0 ]
  then echo "Please run as root"
  exit
fi

# Install helm
curl -sLo helm.tar.gz https://get.helm.sh/helm-v3.7.2-linux-arm64.tar.gz
tar zxf helm.tar.gz
mv linux-arm64/helm /usr/local/bin/
chmod +x /usr/local/bin/helm
rm -rf linux-arm64 helm.tar.gz

# Pibox Disk Provisioner - Note, this script will potentially format attached disks. Careful!
mkdir -p /opt/kubesail/
curl -sLo /opt/kubesail/provision-disk.sh https://raw.githubusercontent.com/kubesail/pibox-os/main/provision-disk.sh
chmod +x /opt/kubesail/provision-disk.sh
/opt/kubesail/./provision-disk.sh
# Run disk provisioner before K3s starts
mkdir -p /etc/systemd/system/k3s.service.d
echo -e "[Service]\nExecStartPre=/opt/kubesail/provision-disk.sh" > /etc/systemd/system/k3s.service.d/override.conf
systemctl daemon-reload

# Install KubeSail helper services
curl -s https://raw.githubusercontent.com/kubesail/pibox-os/main/setup.sh | bash
# now you can run `kubesail` to initialize the KubeSail agent at any time

# Refresh SSH certs on first boot
touch /boot/refresh-ssh-certs

# This happens with PiShrink. Only uncomment if using packer
# truncate -s-1 /boot/cmdline.txt
# echo -n " init=/usr/lib/raspi-config/init_resize.sh" >> /boot/cmdline.txt

# Disable SSH
#systemctl stop ssh
#systemctl disable ssh

# Clean bash history
history -c && history -w
exit

# logout of root and do the same for pi user
history -c && history -w
exit