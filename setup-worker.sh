#!/usr/bin/env bash
set -e

echo "==> [1/5] Deshabilitando swap y SELinux..."
swapoff -a
sed -i '/swap/d' /etc/fstab
setenforce 0 || true
sed -i 's/^SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config

echo "==> [2/5] Módulos del kernel..."
cat <<EOF > /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
modprobe overlay
modprobe br_netfilter
cat <<EOF > /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sysctl --system

echo "==> [3/5] Instalando containerd y kubeadm..."
dnf install -y dnf-plugins-core conntrack-tools
dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
dnf install -y containerd.io
containerd config default > /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
systemctl enable --now containerd

cat <<EOF > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v1.31/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.31/rpm/repodata/repomd.xml.key
EOF
dnf install -y kubelet kubeadm
systemctl enable kubelet

echo "==> [4/5] Configurando red interna k8s-int..."
ip addr add 10.10.10.2/24 dev enp0s10 2>/dev/null || true
ip link set enp0s10 up
cat <<EOF > /etc/NetworkManager/system-connections/k8s-int.nmconnection
[connection]
id=k8s-int
type=ethernet
interface-name=enp0s10
autoconnect=yes

[ipv4]
method=manual
addresses=10.10.10.2/24
EOF
chmod 600 /etc/NetworkManager/system-connections/k8s-int.nmconnection
nmcli connection reload 2>/dev/null || true

echo "==> [5/5] Deshabilitando firewalld..."
systemctl disable --now firewalld

echo "==> Corrigiendo hostname..."
echo "127.0.0.1 worker" >> /etc/hosts
echo "10.10.10.1 master" >> /etc/hosts

echo ""
echo "Worker listo. Ahora ejecuta el kubeadm join."
