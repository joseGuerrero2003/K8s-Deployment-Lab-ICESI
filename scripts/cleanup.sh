#!/usr/bin/env bash
# cleanup.sh — Elimina todos los recursos del laboratorio del namespace
set -euo pipefail

NAMESPACE="${1:-default}"
REPO_DIR="K8S-apps"

YELLOW='\033[1;33m'; GREEN='\033[0;32m'; RESET='\033[0m'

echo -e "${YELLOW}[WARN] Esto eliminará todos los recursos aplicados del laboratorio en namespace: $NAMESPACE${RESET}"
read -rp "Confirmar (s/N): " CONFIRM
[[ "$CONFIRM" =~ ^[sS]$ ]] || { echo "Cancelado"; exit 0; }

if [[ -d "$REPO_DIR" ]]; then
  echo "Eliminando recursos desde manifiestos..."
  kubectl delete -f "$REPO_DIR/" -n "$NAMESPACE" --ignore-not-found=true
fi

echo -e "${GREEN}[OK] Limpieza completada${RESET}"
kubectl get all -n "$NAMESPACE"
