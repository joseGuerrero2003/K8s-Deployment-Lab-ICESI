#!/usr/bin/env bash
# install-k8s-master.sh — Instalación completa de kubeadm en Rocky Linux 9
set -e

echo "==> [1/7] Deshabilitando swap y configurando SELinux..."
swapoff -a
sed -i '/swap/d' /etc/fstab
setenforce 0 || true
sed -i 's/^SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config

echo "==> [2/7] Cargando módulos del kernel..."
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

echo "==> [3/7] Instalando containerd..."
dnf install -y dnf-plugins-core
dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
dnf install -y containerd.io
containerd config default > /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
systemctl enable --now containerd

echo "==> [4/7] Instalando kubeadm, kubelet, kubectl..."
cat <<EOF > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v1.31/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.31/rpm/repodata/repomd.xml.key
EOF
dnf install -y kubelet kubeadm kubectl
systemctl enable --now kubelet

echo "==> [5/7] Inicializando el clúster..."
kubeadm init --pod-network-cidr=10.244.0.0/16 2>&1 | tee /root/kubeadm-init.log

echo "==> [6/7] Configurando kubectl..."
mkdir -p /root/.kube
cp -i /etc/kubernetes/admin.conf /root/.kube/config
chown root:root /root/.kube/config

echo "==> [7/7] Instalando red Flannel..."
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml

echo ""
echo "======================================"
echo "  Instalacion completada"
echo "======================================"
kubectl get nodes
echo ""
echo "Comando para unir el worker (guardalo):"
grep "kubeadm join" /root/kubeadm-init.log | tail -1
