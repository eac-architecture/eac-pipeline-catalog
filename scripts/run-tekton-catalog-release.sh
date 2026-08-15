#!/usr/bin/env bash
set -euo pipefail
repo_url="${1:-}"
revision="${2:-}"
version="${3:-}"
namespace="${TEKTON_NAMESPACE:-eac-cicd}"
context="${KUBE_CONTEXT:-kind-eac-cicd}"
[[ -n "$repo_url" && -n "$revision" && -n "$version" ]] || {
  printf 'Usage: %s <repository-url> <revision> <version>\n' "$0" >&2
  exit 2
}
temp_dir="$(mktemp -d)"
trap 'rm -rf "$temp_dir"' EXIT
cat >"$temp_dir/workspace.yaml" <<'YAML'
spec:
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 2Gi
YAML
tkn pipeline start eac-tekton-catalog-stable-release \
  --context "$context" --namespace "$namespace" --serviceaccount eac-release \
  --param "repo-url=$repo_url" --param "revision=$revision" --param "version=$version" \
  --workspace "name=source,volumeClaimTemplateFile=$temp_dir/workspace.yaml" \
  --showlog --exit-with-pipelinerun-error
