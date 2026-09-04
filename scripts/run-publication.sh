#!/usr/bin/env bash

set -euo pipefail

profile="${1:-}"
repo_url="${2:-}"
revision="${3:-}"
authorized_branch="${4:-}"
release_tag="${5:-}"
publication_channel="${6:-}"
image_repository="${7:-}"
namespace="${TEKTON_NAMESPACE:-eac-cicd}"
context="${KUBE_CONTEXT:-kind-eac-cicd}"

case "$profile" in
    npm) pipeline=eac-npm-publication; storage=2Gi ;;
    dotnet-service)
        pipeline=eac-dotnet-service-publication
        storage=4Gi
        [[ -n "$image_repository" ]] || { printf '[ERROR] image-repository is required for dotnet-service\n' >&2; exit 2; }
        ;;
    *) printf 'Usage: %s <npm|dotnet-service> <repository-url> <revision> <authorized-branch> <release-tag> <prerelease|stable> [image-repository]\n' "$0" >&2; exit 2 ;;
esac
[[ -n "$repo_url" && -n "$revision" && -n "$authorized_branch" && -n "$release_tag" ]] || { printf '[ERROR] release source parameters are required\n' >&2; exit 2; }
case "$publication_channel" in prerelease|stable) ;; *) printf '[ERROR] publication channel must be prerelease or stable\n' >&2; exit 2 ;; esac

temp_dir="$(mktemp -d)"
trap 'rm -rf "$temp_dir"' EXIT
printf 'spec:\n  accessModes: [ReadWriteOnce]\n  resources:\n    requests:\n      storage: %s\n' "$storage" > "$temp_dir/workspace.yaml"
params=(
    --param "repo-url=$repo_url"
    --param "revision=$revision"
    --param "authorized-branch=$authorized_branch"
    --param "release-tag=$release_tag"
    --param "publication-channel=$publication_channel"
)
if [[ "$profile" == dotnet-service ]]; then
    params+=(--param "image-repository=$image_repository")
fi

tkn pipeline start "$pipeline" \
    --context "$context" --namespace "$namespace" --serviceaccount eac-release \
    "${params[@]}" \
    --workspace "name=source,volumeClaimTemplateFile=$temp_dir/workspace.yaml" \
    --showlog --exit-with-pipelinerun-error
