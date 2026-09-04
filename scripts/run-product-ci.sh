#!/usr/bin/env bash

set -euo pipefail

profile="${1:-}"
repo_url="${2:-}"
revision="${3:-main}"
namespace="${TEKTON_NAMESPACE:-eac-cicd}"
context="${KUBE_CONTEXT:-kind-eac-cicd}"

case "$profile" in
    npm) pipeline=eac-npm-ci; storage=2Gi; fs_group=1000 ;;
    angular) pipeline=eac-angular-ci; storage=2Gi; fs_group=1000 ;;
    dotnet-service) pipeline=eac-dotnet-service-ci; storage=4Gi; fs_group=65532 ;;
    *) printf 'Usage: %s <npm|angular|dotnet-service> <repository-url> [revision]\n' "$0" >&2; exit 2 ;;
esac
[[ -n "$repo_url" ]] || { printf '[ERROR] repository-url is required\n' >&2; exit 2; }

temp_dir="$(mktemp -d)"
trap 'rm -rf "$temp_dir"' EXIT
printf 'spec:\n  accessModes: [ReadWriteOnce]\n  resources:\n    requests:\n      storage: %s\n' "$storage" > "$temp_dir/workspace.yaml"
printf 'securityContext:\n  fsGroup: %s\n  fsGroupChangePolicy: OnRootMismatch\n' "$fs_group" > "$temp_dir/pod-template.yaml"

tkn pipeline start "$pipeline" \
    --context "$context" --namespace "$namespace" --serviceaccount eac-ci \
    --param "repo-url=$repo_url" --param "revision=$revision" \
    --workspace "name=source,volumeClaimTemplateFile=$temp_dir/workspace.yaml" \
    --pod-template "$temp_dir/pod-template.yaml" --showlog --exit-with-pipelinerun-error
