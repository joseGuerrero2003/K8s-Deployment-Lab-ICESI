#!/usr/bin/env bash
# watch-pods.sh — Monitoreo continuo de pods en tiempo real
# Uso: ./scripts/watch-pods.sh [namespace]

NAMESPACE="${1:-default}"
echo "Monitoreando pods en namespace: $NAMESPACE  (Ctrl+C para salir)"
echo ""
watch -n 2 "kubectl get pods -n ${NAMESPACE} -o wide && echo '' && \
             kubectl get deployments -n ${NAMESPACE} && echo '' && \
             kubectl get services -n ${NAMESPACE}"
