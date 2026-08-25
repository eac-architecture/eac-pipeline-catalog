#!/usr/bin/env bash

set -euo pipefail

repo_url="${1:-}"
revision="${2:-main}"
integration_profile="${3:-${INTEGRATION_PROFILE:-default}}"
namespace="${TEKTON_NAMESPACE:-eac-cicd}"
context="${KUBE_CONTEXT:-kind-eac-cicd}"
pipeline="${EAC_RELEASE_PIPELINE:-eac-nuget-release-candidate}"
service_account="${TEKTON_SERVICE_ACCOUNT:-eac-release}"

if [[ -z "$repo_url" ]]; then
    printf 'Usage: %s <repository-url> [revision] [default|kafka|postgresql|mongodb]\n' "$0" >&2
    exit 2
fi
case "$integration_profile" in
    default|kafka|postgresql|mongodb) ;;
    *) printf '[ERROR] Integration profile must be default, kafka, postgresql or mongodb: %s\n' "$integration_profile" >&2; exit 2 ;;
esac

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

printf '[INFO] Starting %s for %s at %s; version will be read from VERSION\n' \
    "$pipeline" \
    "$repo_url" \
    "$revision"

tkn pipeline start "$pipeline" \
    --context "$context" \
    --namespace "$namespace" \
    --serviceaccount "$service_account" \
    --param "repo-url=$repo_url" \
    --param "revision=$revision" \
    --param "integration-profile=$integration_profile" \
    --workspace "name=source,volumeClaimTemplateFile=$workspace_template" \
    --pod-template "$pod_template" \
    --showlog \
    --exit-with-pipelinerun-error
