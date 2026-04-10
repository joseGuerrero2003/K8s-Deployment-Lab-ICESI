#!/usr/bin/env bash
set -e

echo "==> Reseteando kubeadm..."
kubeadm reset -f
rm -rf /root/.kube /etc/kubernetes /var/lib/etcd

echo "==> Asignando IP a red interna k8s-int (enp0s10)..."
ip addr add 10.10.10.1/24 dev enp0s10 2>/dev/null || true
ip link set enp0s10 up

echo "==> Haciendo la IP persistente..."
cat <<EOF > /etc/NetworkManager/system-connections/k8s-int.nmconnection
[connection]
id=k8s-int
type=ethernet
interface-name=enp0s10
autoconnect=yes

[ipv4]
method=manual
addresses=10.10.10.1/24
EOF
chmod 600 /etc/NetworkManager/system-connections/k8s-int.nmconnection
nmcli connection reload 2>/dev/null || true

echo "==> Inicializando clúster con IP correcta..."
kubeadm init \
  --pod-network-cidr=10.244.0.0/16 \
  --apiserver-advertise-address=10.10.10.1 \
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
echo "==> Comando join para el worker:"
grep -A2 "kubeadm join" /root/kubeadm-init.log | tail -3
