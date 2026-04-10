#!/usr/bin/env bash
# check-cluster.sh — Diagnóstico rápido del estado del clúster
set -euo pipefail

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; RESET='\033[0m'

ok()   { echo -e "${GREEN}[OK]${RESET} $*"; }
fail() { echo -e "${RED}[FAIL]${RESET} $*"; }
info() { echo -e "${CYAN}[INFO]${RESET} $*"; }
warn() { echo -e "${YELLOW}[WARN]${RESET} $*"; }

echo -e "${CYAN}=== Diagnóstico del Clúster Kubernetes ===${RESET}"
echo ""

# 1. kubectl disponible
if command -v kubectl &>/dev/null; then
  ok "kubectl: $(kubectl version --client --short 2>/dev/null | head -1)"
else
  fail "kubectl no encontrado"; exit 1
fi

# 2. Conectividad
info "Verificando conectividad al API server..."
if kubectl cluster-info &>/dev/null; then
  ok "API server accesible"
  kubectl cluster-info | head -2
else
  fail "No hay conectividad al API server"
  exit 1
fi

# 3. Nodos
echo ""
info "Estado de nodos:"
kubectl get nodes -o wide

NOT_READY=$(kubectl get nodes --no-headers | grep -vc " Ready " || true)
if [[ "$NOT_READY" -gt 0 ]]; then
  warn "$NOT_READY nodo(s) fuera de Ready"
else
  ok "Todos los nodos Ready"
fi

# 4. Pods del sistema
echo ""
info "Pods del sistema (kube-system):"
kubectl get pods -n kube-system --no-headers \
  | awk '{printf "  %-50s %s\n", $1, $3}'

# 5. Recursos disponibles
echo ""
info "Uso de recursos por nodo:"
kubectl top nodes 2>/dev/null || warn "metrics-server no disponible (kubectl top no funciona)"

echo ""
ok "Diagnóstico completado"
