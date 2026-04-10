#!/usr/bin/env bash
kubectl patch replicaset webapp-replicaset --type=json \
  -p='[{"op":"replace","path":"/spec/template/spec/containers/0/image","value":"nginx:latest"}]'

kubectl delete pod webapp-replicaset-7h6dw webapp-replicaset-dnsd5 webapp-replicaset-rkhn7 --ignore-not-found=true
