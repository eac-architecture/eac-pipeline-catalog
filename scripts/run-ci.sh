#!/usr/bin/env bash

set -euo pipefail

repo_url="${1:-}"
revision="${2:-main}"
namespace="${TEKTON_NAMESPACE:-eac-cicd}"
context="${KUBE_CONTEXT:-kind-eac-cicd}"
pipeline="${EAC_CI_PIPELINE:-eac-nuget-ci}"
service_account="${TEKTON_SERVICE_ACCOUNT:-eac-ci}"
configuration="${BUILD_CONFIGURATION:-Release}"

if [[ -z "$repo_url" ]]; then
    printf 'Usage: %s <repository-url> [revision]\n' "$0" >&2
    exit 2
fi

temp_dir="$(mktemp -d)"
workspace_template="$temp_dir/workspace.yaml"
pod_template="$temp_dir/pod-template.yaml"
trap 'rm -rf "$temp_dir"' EXIT

cat >"$workspace_template" <<'YAML'
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 2Gi
YAML

cat >"$pod_template" <<'YAML'
securityContext:
  fsGroup: 65532
  fsGroupChangePolicy: OnRootMismatch
YAML

printf '[INFO] Starting %s for %s at %s\n' \
    "$pipeline" \
    "$repo_url" \
    "$revision"

tkn pipeline start "$pipeline" \
    --context "$context" \
    --namespace "$namespace" \
    --serviceaccount "$service_account" \
    --param "repo-url=$repo_url" \
    --param "revision=$revision" \
    --param "configuration=$configuration" \
    --workspace "name=source,volumeClaimTemplateFile=$workspace_template" \
    --pod-template "$pod_template" \
    --showlog \
    --exit-with-pipelinerun-error
