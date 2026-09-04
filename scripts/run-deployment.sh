#!/usr/bin/env bash

set -euo pipefail

repo_url="${1:-}"
revision="${2:-}"
workload="${3:-}"
container="${4:-}"
image_reference="${5:-}"
namespace="${TEKTON_NAMESPACE:-eac-cicd}"
context="${KUBE_CONTEXT:-kind-eac-cicd}"

if [[ -z "$repo_url" || -z "$revision" || -z "$workload" || -z "$container" || -z "$image_reference" ]]; then
    printf 'Usage: %s <repository-url> <revision> <workload> <container> <image@sha256:digest>\n' "$0" >&2
    exit 2
fi
[[ "$workload" =~ ^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$ && ${#workload} -le 253 ]] || { printf '[ERROR] workload must be a Kubernetes DNS subdomain\n' >&2; exit 2; }
[[ "$container" =~ ^[a-z0-9]([-a-z0-9]*[a-z0-9])?$ && ${#container} -le 63 ]] || { printf '[ERROR] container must be a Kubernetes DNS label\n' >&2; exit 2; }
[[ "$image_reference" =~ ^[a-z0-9.-]+(/[a-z0-9._-]+)+@sha256:[0-9a-f]{64}$ ]] || { printf '[ERROR] deployment requires a fully qualified immutable image digest\n' >&2; exit 2; }

temp_dir="$(mktemp -d)"
trap 'rm -rf "$temp_dir"' EXIT
printf 'spec:\n  accessModes: [ReadWriteOnce]\n  resources:\n    requests:\n      storage: 1Gi\n' > "$temp_dir/workspace.yaml"

tkn pipeline start eac-deployment-promotion \
    --context "$context" --namespace "$namespace" --serviceaccount eac-deployment \
    --param "repo-url=$repo_url" --param "revision=$revision" \
    --param "workload=$workload" --param "container=$container" \
    --param "image-reference=$image_reference" \
    --workspace "name=source,volumeClaimTemplateFile=$temp_dir/workspace.yaml" \
    --showlog --exit-with-pipelinerun-error
