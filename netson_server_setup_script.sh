#!/usr/bin/env bash
set -euo pipefail

# set maxn power mode
#nvpmodel -m 0

# create journal settings file
cat << EOF > /etc/systemd/journald.conf
[Journal]
Storage=volatile
RuntimeMaxUse=50M
EOF
systemctl restart systemd-journald

# create network stats file script
cat << EOF > /sbin/write_network_stats.sh
#!/usr/bin/env bash
set -euo pipefail

IP=\$(/sbin/ifconfig ens5 | grep 'inet ' | awk '{print \$2}')
MAC=\$(cat /sys/class/net/ens5/address)
HOSTNAME=\$(cat /proc/sys/kernel/hostname)
echo "{\"ip\":\"\${IP}\",\"mac\":\"\${MAC}\",\"hostname\":\"\${HOSTNAME}\"}" > /tmp/network.json
EOF
chmod a+x /sbin/write_network_stats.sh

# set crontab
crontab -l > current_cron || touch current_cron
echo "* * * * * /sbin/write_network_stats.sh" >> current_cron
echo "0 * * * * docker image prune -a -f" >> current_cron
cat current_cron | sort | uniq > new_cron
crontab new_cron
rm current_cron new_cron

# clean OS
apt remove -y --purge \
 libreoffice-* \
 libreoffice-core \
 libreoffice-common \
 thunderbird \
 fonts-noto-cjk
apt purge -y
apt autoremove -y
apt clean -y

# update OS
apt update
apt upgrade -y

# NCB install required apps
apt remove -y --purge containerd
apt install -y curl
curl https://packages.microsoft.com/config/ubuntu/18.04/multiarch/prod.list > ./microsoft-prod.list
cp ./microsoft-prod.list /etc/apt/sources.list.d/
curl https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > microsoft.gpg
cp ./microsoft.gpg /etc/apt/trusted.gpg.d/
apt update
apt upgrade -y
apt install -y moby-engine
apt install -y iotedge

curl -s -L https://nvidia.github.io/nvidia-container-runtime/gpgkey | \
  sudo apt-key add -
distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
curl -s -L https://nvidia.github.io/nvidia-container-runtime/$distribution/nvidia-container-runtime.list | \
  sudo tee /etc/apt/sources.list.d/nvidia-container-runtime.list
sudo apt-get update
sudo apt-get install -y nvidia-container-runtime
sudo mkdir -p /etc/systemd/system/docker.service.d
sudo tee /etc/systemd/system/docker.service.d/override.conf <<EOF
[Service]
ExecStart=
ExecStart=/usr/bin/dockerd --host=fd:// --add-runtime=nvidia=/usr/bin/nvidia-container-runtime
EOF
sudo systemctl daemon-reload
sudo systemctl restart docker
sudo tee /etc/docker/daemon.json <<EOF
{
    "runtimes": {
        "nvidia": {
            "path": "/usr/bin/nvidia-container-runtime",
            "runtimeArgs": []
        }
    }
}
EOF
sudo pkill -SIGHUP dockerd
distribution=$(. /etc/os-release;echo $ID$VERSION_ID)    && curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | sudo apt-key add -    && curl -s -L https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.list | sudo tee /etc/apt/sources.list.d/nvidia-docker.list
sudo apt-get update
sudo apt download nvidia-docker2
sudo sudo dpkg-deb -xv *.deb /
rm *.deb

# NCB end of install required apps

apt purge -y
apt autoremove -y
apt clean -y
if [ -f /var/run/reboot-required ]; then
  echo "A reboot is required to complete the setup process"
  echo "You have 10 seconds to cancel the reboot using ctrl+c"
  sleep 10
  reboot
fi
