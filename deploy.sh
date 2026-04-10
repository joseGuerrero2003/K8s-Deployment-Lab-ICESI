#!/usr/bin/env bash
# =============================================================================
# deploy.sh — Flujo completo automatizado del laboratorio K8s
# Universidad ICESI — Infraestructura III
# =============================================================================

set -euo pipefail

# ─── Colores ─────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

ok()   { echo -e "${GREEN}[OK]${RESET} $*"; }
info() { echo -e "${CYAN}[INFO]${RESET} $*"; }
warn() { echo -e "${YELLOW}[WARN]${RESET} $*"; }
fail() { echo -e "${RED}[ERROR]${RESET} $*"; exit 1; }
header() { echo -e "\n${BOLD}${CYAN}════════════════════════════════════════${RESET}"; \
           echo -e "${BOLD}${CYAN}  $*${RESET}"; \
           echo -e "${BOLD}${CYAN}════════════════════════════════════════${RESET}"; }

# ─── Configuración ───────────────────────────────────────────────────────────
REPO_URL="https://github.com/mariocr73/K8S-apps.git"
REPO_DIR="K8S-apps"
NAMESPACE="default"
WAIT_TIMEOUT="120s"
SCALE_REPLICAS=3
PORT_FORWARD_LOCAL=8080
PORT_FORWARD_REMOTE=80

# =============================================================================
# FASE 1: PREPARACIÓN
# =============================================================================
phase1_preparacion() {
  header "FASE 1 — Preparación del entorno"

  # Verificar kubectl disponible
  command -v kubectl &>/dev/null || fail "kubectl no encontrado en PATH"
  ok "kubectl disponible: $(kubectl version --client --short 2>/dev/null | head -1)"

  # Verificar conectividad al clúster
  info "Verificando conectividad al clúster..."
  kubectl cluster-info &>/dev/null || fail "No hay conectividad al clúster. Verifica kubeconfig."
  ok "Conectividad al clúster confirmada"

  # Validar nodos en estado Ready
  info "Estado de los nodos:"
  kubectl get nodes -o wide

  NOT_READY=$(kubectl get nodes --no-headers 2>/dev/null \
    | grep -v " Ready " | wc -l | tr -d ' ')

  if [[ "$NOT_READY" -gt 0 ]]; then
    warn "$NOT_READY nodo(s) NO están en estado Ready:"
    kubectl get nodes --no-headers | grep -v " Ready "
    fail "Corrige el estado del clúster antes de continuar"
  fi
  ok "Todos los nodos están en estado Ready"

  # Clonar repositorio
  if [[ -d "$REPO_DIR" ]]; then
    warn "Directorio '$REPO_DIR' ya existe — haciendo git pull..."
    git -C "$REPO_DIR" pull --rebase || warn "git pull falló, continuando con estado actual"
  else
    info "Clonando $REPO_URL..."
    git clone "$REPO_URL" "$REPO_DIR" || fail "Error clonando repositorio"
    ok "Repositorio clonado en ./$REPO_DIR"
  fi
}

# =============================================================================
# FASE 2: ANÁLISIS DEL REPOSITORIO
# =============================================================================
phase2_analisis() {
  header "FASE 2 — Análisis del repositorio"

  cd "$REPO_DIR"

  # Listar archivos YAML encontrados
  YAML_FILES=$(find . -maxdepth 3 -name "*.yaml" -o -name "*.yml" 2>/dev/null | sort)
  if [[ -z "$YAML_FILES" ]]; then
    fail "No se encontraron archivos YAML en el repositorio"
  fi

  info "Archivos YAML encontrados:"
  echo "$YAML_FILES"

  echo ""
  info "Clasificación de recursos definidos:"
  printf "%-40s %-20s %-20s\n" "ARCHIVO" "KIND" "NOMBRE"
  printf "%-40s %-20s %-20s\n" "-------" "----" "------"

  while IFS= read -r f; do
    KIND=$(grep -m1 "^kind:" "$f" 2>/dev/null | awk '{print $2}' || echo "desconocido")
    NAME=$(grep -m1 "^  name:" "$f" 2>/dev/null | awk '{print $2}' || echo "—")
    printf "%-40s %-20s %-20s\n" "$f" "$KIND" "$NAME"
  done <<< "$YAML_FILES"

  echo ""
  info "Pregunta del laboratorio:"
  echo -e "${YELLOW}¿Por qué usar Deployment en lugar de Pods directamente?${RESET}"
  echo ""
  echo "  Un Pod creado directamente es un objeto efímero: si falla o el nodo muere,"
  echo "  nadie lo recrea. Un Deployment introduce un ReplicaSet que actúa como"
  echo "  controlador de reconciliación: compara el estado deseado (replicas: N)"
  echo "  con el estado real, y corrige divergencias de forma autónoma."
  echo "  Esto habilita: self-healing, rolling updates, rollback y escalamiento."
  echo ""

  cd ..
}

# =============================================================================
# FASE 3: DESPLIEGUE
# =============================================================================
phase3_despliegue() {
  header "FASE 3 — Despliegue de manifiestos"

  cd "$REPO_DIR"
  info "Aplicando todos los manifiestos YAML..."
  kubectl apply -f . --namespace="$NAMESPACE"

  info "Esperando a que los pods estén Running (timeout: $WAIT_TIMEOUT)..."
  # Obtener deployments en el namespace
  DEPLOYMENTS=$(kubectl get deployments -n "$NAMESPACE" --no-headers -o custom-columns="NAME:.metadata.name" 2>/dev/null || true)

  if [[ -n "$DEPLOYMENTS" ]]; then
    while IFS= read -r dep; do
      info "Esperando rollout de Deployment: $dep"
      kubectl rollout status deployment/"$dep" -n "$NAMESPACE" --timeout="$WAIT_TIMEOUT" \
        || warn "Timeout esperando $dep — verifica manualmente"
    done <<< "$DEPLOYMENTS"
  fi

  echo ""
  info "Estado actual de los recursos:"
  echo "--- Pods ---"
  kubectl get pods -n "$NAMESPACE" -o wide

  echo ""
  echo "--- Deployments ---"
  kubectl get deployments -n "$NAMESPACE"

  echo ""
  echo "--- Services ---"
  kubectl get services -n "$NAMESPACE"

  # Detectar pods con problemas
  PROBLEM_PODS=$(kubectl get pods -n "$NAMESPACE" --no-headers 2>/dev/null \
    | grep -E "CrashLoopBackOff|ImagePullBackOff|Error|OOMKilled|Pending" || true)

  if [[ -n "$PROBLEM_PODS" ]]; then
    warn "Pods con problemas detectados:"
    echo "$PROBLEM_PODS"
    echo ""
    echo "  CrashLoopBackOff  → El contenedor falla al iniciar. Revisar: kubectl logs <pod>"
    echo "  ImagePullBackOff  → No puede descargar la imagen. Verifica nombre/tag/registry"
    echo "  Pending           → Sin nodo disponible. Verifica recursos y taints"
    echo ""
    warn "Ejecuta: kubectl describe pod <nombre-pod> -n $NAMESPACE  para más detalle"
  else
    ok "Todos los pods están en estado Running"
  fi

  cd ..
}

# =============================================================================
# FASE 4: EXPOSICIÓN
# =============================================================================
phase4_exposicion() {
  header "FASE 4 — Exposición de la aplicación"

  # Obtener servicios (excluye kubernetes default)
  SERVICES=$(kubectl get services -n "$NAMESPACE" --no-headers \
    | grep -v "^kubernetes " || true)

  if [[ -z "$SERVICES" ]]; then
    warn "No se encontraron Services desplegados"
    return 0
  fi

  info "Services disponibles:"
  kubectl get services -n "$NAMESPACE"
  echo ""

  # Iterar servicios y determinar acceso
  while IFS= read -r svc_line; do
    SVC_NAME=$(echo "$svc_line" | awk '{print $1}')
    SVC_TYPE=$(echo "$svc_line" | awk '{print $2}')
    SVC_PORT=$(echo "$svc_line" | awk '{print $5}' | cut -d'/' -f1 | cut -d':' -f1)
    CLUSTER_IP=$(echo "$svc_line" | awk '{print $3}')

    info "Analizando Service: $SVC_NAME (tipo: $SVC_TYPE)"

    case "$SVC_TYPE" in
      NodePort)
        NODE_PORT=$(kubectl get svc "$SVC_NAME" -n "$NAMESPACE" \
          -o jsonpath='{.spec.ports[0].nodePort}')
        NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
        ok "Acceso NodePort: http://${NODE_IP}:${NODE_PORT}"
        ;;
      LoadBalancer)
        EXTERNAL_IP=$(kubectl get svc "$SVC_NAME" -n "$NAMESPACE" \
          -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
        if [[ -z "$EXTERNAL_IP" || "$EXTERNAL_IP" == "" ]]; then
          warn "LoadBalancer sin IP externa asignada (normal en kubeadm sin MetalLB)"
          info "Usando port-forward como alternativa..."
          _port_forward "$SVC_NAME"
        else
          ok "Acceso LoadBalancer: http://${EXTERNAL_IP}:${SVC_PORT}"
        fi
        ;;
      ClusterIP)
        info "Service tipo ClusterIP — acceso solo interno al clúster"
        info "Usando port-forward para acceso local..."
        _port_forward "$SVC_NAME"
        ;;
      *)
        warn "Tipo de Service desconocido: $SVC_TYPE"
        ;;
    esac
  done <<< "$SERVICES"
}

_port_forward() {
  local SVC="$1"
  SVC_PORT_REMOTE=$(kubectl get svc "$SVC" -n "$NAMESPACE" \
    -o jsonpath='{.spec.ports[0].port}' 2>/dev/null || echo "$PORT_FORWARD_REMOTE")

  ok "Ejecuta en otra terminal para acceder a la app:"
  echo ""
  echo "  kubectl port-forward svc/${SVC} ${PORT_FORWARD_LOCAL}:${SVC_PORT_REMOTE} -n ${NAMESPACE}"
  echo ""
  echo "  Luego abre: http://localhost:${PORT_FORWARD_LOCAL}"
}

# =============================================================================
# FASE 5: ESCALAMIENTO
# =============================================================================
phase5_escalamiento() {
  header "FASE 5 — Escalamiento horizontal"

  DEPLOYMENTS=$(kubectl get deployments -n "$NAMESPACE" --no-headers \
    -o custom-columns="NAME:.metadata.name" 2>/dev/null || true)

  if [[ -z "$DEPLOYMENTS" ]]; then
    warn "No hay Deployments para escalar"
    return 0
  fi

  while IFS= read -r dep; do
    CURRENT=$(kubectl get deployment "$dep" -n "$NAMESPACE" \
      -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "?")
    info "Escalando Deployment '$dep': $CURRENT → $SCALE_REPLICAS réplicas"
    kubectl scale deployment "$dep" --replicas="$SCALE_REPLICAS" -n "$NAMESPACE"
    kubectl rollout status deployment/"$dep" -n "$NAMESPACE" --timeout="$WAIT_TIMEOUT" \
      || warn "Timeout en rollout de $dep"
  done <<< "$DEPLOYMENTS"

  echo ""
  ok "Estado después del escalamiento:"
  kubectl get pods -n "$NAMESPACE" -o wide
  echo ""
  kubectl get deployments -n "$NAMESPACE"
}

# =============================================================================
# FASE 6: RESILIENCIA (SELF-HEALING)
# =============================================================================
phase6_resiliencia() {
  header "FASE 6 — Prueba de resiliencia (self-healing)"

  # Seleccionar el primer pod de un deployment
  TARGET_POD=$(kubectl get pods -n "$NAMESPACE" --no-headers 2>/dev/null \
    | grep "Running" | awk '{print $1}' | head -1 || true)

  if [[ -z "$TARGET_POD" ]]; then
    warn "No hay pods en Running para eliminar"
    return 0
  fi

  info "Pod seleccionado para eliminar: $TARGET_POD"
  info "Estado ANTES de la eliminación:"
  kubectl get pods -n "$NAMESPACE"

  echo ""
  info "Eliminando pod $TARGET_POD..."
  kubectl delete pod "$TARGET_POD" -n "$NAMESPACE"

  echo ""
  info "Observando recreación automática (espera 5 segundos)..."
  sleep 5
  kubectl get pods -n "$NAMESPACE"

  echo ""
  info "Esperando que el nuevo pod alcance estado Running..."
  # Esperar hasta que el número de pods Running sea igual al deseado
  TIMEOUT=60
  ELAPSED=0
  while true; do
    RUNNING=$(kubectl get pods -n "$NAMESPACE" --no-headers 2>/dev/null \
      | grep -c "Running" || echo 0)
    TOTAL=$(kubectl get pods -n "$NAMESPACE" --no-headers 2>/dev/null \
      | wc -l | tr -d ' ')
    if [[ "$RUNNING" -eq "$TOTAL" && "$TOTAL" -gt 0 ]]; then
      break
    fi
    if [[ "$ELAPSED" -ge "$TIMEOUT" ]]; then
      warn "Timeout esperando recuperación completa"
      break
    fi
    sleep 3
    ELAPSED=$((ELAPSED + 3))
  done

  ok "Estado DESPUÉS de la recreación:"
  kubectl get pods -n "$NAMESPACE"

  echo ""
  echo -e "${BOLD}Análisis de self-healing:${RESET}"
  echo "  El componente responsable es el ReplicaSet, gestionado por el Deployment."
  echo "  Cuando el pod fue eliminado, el ReplicaSet detectó que el estado actual"
  echo "  (N-1 pods) difiere del estado deseado (N réplicas) y creó un nuevo pod"
  echo "  de forma automática. Este es el ciclo de reconciliación de Kubernetes."
}

# =============================================================================
# EXTRAS
# =============================================================================
phase_extras() {
  header "EXTRAS — Operaciones adicionales"

  DEPLOYMENTS=$(kubectl get deployments -n "$NAMESPACE" --no-headers \
    -o custom-columns="NAME:.metadata.name" 2>/dev/null | head -1 || true)
  [[ -z "$DEPLOYMENTS" ]] && return 0
  DEP="$DEPLOYMENTS"

  echo -e "${BOLD}Cambiar imagen del Deployment:${RESET}"
  echo "  kubectl set image deployment/${DEP} <container>=<nueva-imagen>:<tag> -n ${NAMESPACE}"
  echo "  Ejemplo: kubectl set image deployment/${DEP} nginx=nginx:1.25 -n ${NAMESPACE}"

  echo ""
  echo -e "${BOLD}Agregar variable de entorno:${RESET}"
  echo "  kubectl set env deployment/${DEP} ENV_VAR=valor -n ${NAMESPACE}"
  echo "  Ejemplo: kubectl set env deployment/${DEP} APP_ENV=production -n ${NAMESPACE}"

  echo ""
  echo -e "${BOLD}Ver logs en tiempo real:${RESET}"
  POD=$(kubectl get pods -n "$NAMESPACE" --no-headers 2>/dev/null \
    | grep "Running" | awk '{print $1}' | head -1 || true)
  if [[ -n "$POD" ]]; then
    echo "  kubectl logs -f ${POD} -n ${NAMESPACE}"
    echo "  kubectl logs -f ${POD} --previous -n ${NAMESPACE}   # logs del contenedor anterior"
  fi

  echo ""
  echo -e "${BOLD}Crear Service tipo NodePort (si no existe):${RESET}"
  echo "  kubectl expose deployment/${DEP} --type=NodePort --port=80 --name=${DEP}-nodeport -n ${NAMESPACE}"

  echo ""
  echo -e "${BOLD}Historial de rollouts:${RESET}"
  echo "  kubectl rollout history deployment/${DEP} -n ${NAMESPACE}"
  echo "  kubectl rollout undo deployment/${DEP}           # rollback"
}

# =============================================================================
# MENÚ PRINCIPAL
# =============================================================================
main() {
  echo -e "${BOLD}${CYAN}"
  echo "  ╔═══════════════════════════════════════════╗"
  echo "  ║   K8s Lab — Deploy Automation Script      ║"
  echo "  ║   Universidad ICESI — Infraestructura III ║"
  echo "  ╚═══════════════════════════════════════════╝"
  echo -e "${RESET}"

  case "${1:-all}" in
    fase1)  phase1_preparacion ;;
    fase2)  phase2_analisis ;;
    fase3)  phase3_despliegue ;;
    fase4)  phase4_exposicion ;;
    fase5)  phase5_escalamiento ;;
    fase6)  phase6_resiliencia ;;
    extras) phase_extras ;;
    all)
      phase1_preparacion
      phase2_analisis
      phase3_despliegue
      phase4_exposicion
      phase5_escalamiento
      phase6_resiliencia
      phase_extras
      ;;
    *)
      echo "Uso: $0 [fase1|fase2|fase3|fase4|fase5|fase6|extras|all]"
      exit 1
      ;;
  esac

  echo ""
  ok "Script finalizado correctamente"
}

main "$@"
