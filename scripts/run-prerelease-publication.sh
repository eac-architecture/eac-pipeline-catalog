#!/usr/bin/env bash

set -euo pipefail

repo_url="${1:-}"
revision="${2:-}"
authorized_branch="${3:-}"
release_tag="${4:-}"
integration_profile="${5:-${INTEGRATION_PROFILE:-default}}"
namespace="${TEKTON_NAMESPACE:-eac-cicd}"
context="${KUBE_CONTEXT:-kind-eac-cicd}"
pipeline="${EAC_PUBLISH_PIPELINE:-eac-nuget-prerelease-publication}"
service_account="${TEKTON_SERVICE_ACCOUNT:-eac-release}"

if [[ -z "$repo_url" || -z "$revision" || -z "$authorized_branch" || -z "$release_tag" ]]; then
    printf 'Usage: %s <repository-url> <immutable-commit> <release-branch> <release-tag> [default|kafka|postgresql|mongodb|elasticsearch]\n' "$0" >&2
    exit 2
fi
case "$integration_profile" in
    default|kafka|postgresql|mongodb|elasticsearch) ;;
    *) printf '[ERROR] Integration profile must be default, kafka, postgresql, mongodb or elasticsearch: %s\n' "$integration_profile" >&2; exit 2 ;;
esac

temp_dir="$(mktemp -d)"
workspace_template="$temp_dir/workspace.yaml"
pod_template="$temp_dir/pod-template.yaml"
trap 'rm -rf "$temp_dir"' EXIT

cat >"$workspace_template" <<'YAML'
spec:
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 2Gi
YAML

cat >"$pod_template" <<'YAML'
securityContext:
  fsGroup: 65532
  fsGroupChangePolicy: OnRootMismatch
YAML

printf '[INFO] Starting %s for %s at approved commit %s\n' "$pipeline" "$release_tag" "$revision"
tkn pipeline start "$pipeline" \
    --context "$context" \
    --namespace "$namespace" \
    --serviceaccount "$service_account" \
    --param "repo-url=$repo_url" \
    --param "revision=$revision" \
    --param "authorized-branch=$authorized_branch" \
    --param "release-tag=$release_tag" \
    --param "integration-profile=$integration_profile" \
    --workspace "name=source,volumeClaimTemplateFile=$workspace_template" \
    --pod-template "$pod_template" \
    --showlog \
    --exit-with-pipelinerun-error
