#!/usr/bin/env bash

set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
namespace="${TEKTON_NAMESPACE:-eac-cicd}"
context="${KUBE_CONTEXT:-kind-eac-cicd}"

kubectl --context "$context" get namespace "$namespace" >/dev/null
kubectl --context "$context" \
    --namespace "$namespace" \
    apply \
    --recursive \
    --filename "$root_dir/catalog/shared"
kubectl --context "$context" \
    --namespace "$namespace" \
    apply \
    --recursive \
    --filename "$root_dir/catalog/profiles"
kubectl --context "$context" \
    --namespace "$namespace" \
    delete task eac-main-revision-gate \
    --ignore-not-found >/dev/null

printf '[OK] EAC Pipeline Catalog %s installed in %s\n' \
    "$(tr -d '[:space:]' < "$root_dir/VERSION")" \
    "$namespace"
