#!/usr/bin/env bash
set -e

echo "==> Instalando conntrack..."
dnf install -y conntrack-tools

echo "==> Deshabilitando firewalld..."
systemctl disable --now firewalld

echo "==> Corrigiendo hostname en /etc/hosts..."
MASTER_IP=$(ip addr show enp0s3 | grep 'inet ' | awk '{print $2}' | cut -d/ -f1)
echo "$MASTER_IP master" >> /etc/hosts
echo "127.0.0.1 master" >> /etc/hosts

echo "==> Inicializando el clúster kubeadm..."
kubeadm init --pod-network-cidr=10.244.0.0/16 2>&1 | tee /root/kubeadm-init.log

echo "==> Configurando kubectl..."
mkdir -p /root/.kube
cp /etc/kubernetes/admin.conf /root/.kube/config
chown root:root /root/.kube/config

echo "==> Instalando red Flannel..."
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml

echo ""
echo "======================================"
echo "  Cluster listo"
echo "======================================"
kubectl get nodes

echo ""
echo "==> Comando para unir el worker:"
grep "kubeadm join" /root/kubeadm-init.log -A2 | tail -3
