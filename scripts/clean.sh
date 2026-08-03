#!/usr/bin/env bash

set -euo pipefail

namespace="${TEKTON_NAMESPACE:-eac-cicd}"
context="${KUBE_CONTEXT:-kind-eac-cicd}"

if [[ "${1:-}" != "--confirm" ]]; then
    printf 'Usage: %s --confirm\n' "$0" >&2
    printf 'Removes all Tekton definitions, executions and repository registrations from %s/%s.\n' \
        "$context" \
        "$namespace" >&2
    exit 2
fi

kubectl --context "$context" get namespace "$namespace" >/dev/null

printf '[INFO] Cleaning Tekton resources from %s/%s\n' "$context" "$namespace"

kubectl --context "$context" --namespace "$namespace" \
    delete pipelineruns.tekton.dev --all --ignore-not-found=true
kubectl --context "$context" --namespace "$namespace" \
    delete taskruns.tekton.dev --all --ignore-not-found=true
kubectl --context "$context" --namespace "$namespace" \
    delete pipelines.tekton.dev --all --ignore-not-found=true
kubectl --context "$context" --namespace "$namespace" \
    delete tasks.tekton.dev --all --ignore-not-found=true
kubectl --context "$context" --namespace "$namespace" \
    delete repositories.pipelinesascode.tekton.dev --all --ignore-not-found=true
kubectl --context "$context" --namespace "$namespace" \
    delete persistentvolumeclaims --all --ignore-not-found=true

printf '[OK] Tekton resources removed from %s/%s\n' "$context" "$namespace"
printf '[INFO] Tekton, Pipelines as Code, credentials and service accounts were preserved\n'
