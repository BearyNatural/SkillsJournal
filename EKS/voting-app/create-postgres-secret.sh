#!/usr/bin/env bash
set -euo pipefail

: "${POSTGRES_USER:?Set POSTGRES_USER before creating the Kubernetes secret.}"
: "${POSTGRES_PASSWORD:?Set POSTGRES_PASSWORD before creating the Kubernetes secret.}"
: "${POSTGRES_DB:?Set POSTGRES_DB before creating the Kubernetes secret.}"

kubectl create secret generic postgres-secret \
  --from-literal=POSTGRES_USER="$POSTGRES_USER" \
  --from-literal=POSTGRES_PASSWORD="$POSTGRES_PASSWORD" \
  --from-literal=POSTGRES_DB="$POSTGRES_DB"
