#!/usr/bin/env bash
set -e

echo "==> Limpieza profunda..."
kubeadm reset -f || true
systemctl stop kubelet || true
systemctl stop containerd || true

rm -rf /etc/kubernetes /var/lib/etcd /var/lib/kubelet /root/.kube
rm -rf /etc/cni/net.d
iptables -F && iptables -X
iptables -t nat -F && iptables -t nat -X

echo "==> Reiniciando containerd limpio..."
systemctl start containerd
sleep 5

echo "==> Asignando IP a k8s-int..."
ip addr add 10.10.10.1/24 dev enp0s10 2>/dev/null || true
ip link set enp0s10 up

echo "==> Verificando conectividad..."
ping -c 1 10.10.10.1

echo "==> Iniciando kubelet..."
systemctl start kubelet
sleep 3

echo "==> Inicializando clúster..."
kubeadm init \
  --pod-network-cidr=10.244.0.0/16 \
  --apiserver-advertise-address=10.10.10.1 \
  --ignore-preflight-errors=all \
  2>&1 | tee /root/kubeadm-init.log

echo "==> Configurando kubectl..."
mkdir -p /root/.kube
cp /etc/kubernetes/admin.conf /root/.kube/config
chown root:root /root/.kube/config

echo "==> Instalando Flannel..."
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml

echo ""
echo "======================================"
kubectl get nodes
echo ""
echo "==> Join command para el worker:"
grep -A2 "kubeadm join" /root/kubeadm-init.log | tail -3
