#!/usr/bin/env bash

set -euo pipefail

repo_url="${1:-}"
revision="${2:-}"
target_api="${3:-}"
target_namespace="${4:-}"
workload="${5:-}"
container="${6:-}"
image_reference="${7:-}"
namespace="${TEKTON_NAMESPACE:-eac-cicd}"
context="${KUBE_CONTEXT:-kind-eac-cicd}"

if [[ -z "$image_reference" ]]; then
    printf 'Usage: %s <repository-url> <revision> <target-api> <target-namespace> <workload> <container> <image@sha256:digest>\n' "$0" >&2
    exit 2
fi
[[ "$image_reference" =~ @sha256:[0-9a-f]{64}$ ]] || { printf '[ERROR] deployment requires an immutable image digest\n' >&2; exit 2; }

temp_dir="$(mktemp -d)"
trap 'rm -rf "$temp_dir"' EXIT
printf 'spec:\n  accessModes: [ReadWriteOnce]\n  resources:\n    requests:\n      storage: 1Gi\n' > "$temp_dir/workspace.yaml"

tkn pipeline start eac-deployment-promotion \
    --context "$context" --namespace "$namespace" --serviceaccount eac-deployment \
    --param "repo-url=$repo_url" --param "revision=$revision" \
    --param "target-api=$target_api" --param "target-namespace=$target_namespace" \
    --param "workload=$workload" --param "container=$container" \
    --param "image-reference=$image_reference" \
    --workspace "name=source,volumeClaimTemplateFile=$temp_dir/workspace.yaml" \
    --showlog --exit-with-pipelinerun-error
