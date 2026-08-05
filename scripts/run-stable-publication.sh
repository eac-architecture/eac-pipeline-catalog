#!/usr/bin/env bash

set -euo pipefail

repo_url="${1:-}"
revision="${2:-}"
authorized_branch="${3:-main}"
release_tag="${4:-}"
candidate_run="${5:-}"
candidate_commit="${6:-}"
package_file="${7:-}"
package_sha256="${8:-}"
symbols_file="${9:-}"
sbom_sha256="${10:-}"
evidence_file="${11:-}"
namespace="${TEKTON_NAMESPACE:-eac-cicd}"
context="${KUBE_CONTEXT:-kind-eac-cicd}"
pipeline="${EAC_PUBLISH_PIPELINE:-eac-nuget-stable-publication}"
service_account="${TEKTON_SERVICE_ACCOUNT:-eac-release}"

if [[ -z "$repo_url" || -z "$revision" || -z "$authorized_branch" || \
      -z "$release_tag" || -z "$candidate_run" || -z "$candidate_commit" || \
      -z "$package_file" || -z "$package_sha256" || -z "$symbols_file" || \
      -z "$sbom_sha256" || -z "$evidence_file" ]]; then
    printf 'Usage: %s <repository-url> <main-commit> <main-branch> <stable-tag> <candidate-run> <candidate-commit> <package-file> <package-sha256> <symbols-file> <sbom-sha256> <evidence-file>\n' "$0" >&2
    exit 2
fi

candidate_pvc="$({
    kubectl --context "$context" --namespace "$namespace" get pvc \
        --sort-by=.metadata.creationTimestamp \
        --output 'custom-columns=NAME:.metadata.name,OWNER:.metadata.ownerReferences[0].name' \
        --no-headers
} | awk -v owner="$candidate_run" '$2 == owner { claim=$1 } END { print claim }')"

if [[ -z "$candidate_pvc" ]]; then
    printf '[ERROR] The retained workspace for candidate PipelineRun %s is unavailable\n' \
        "$candidate_run" >&2
    exit 1
fi

pod_template="$(mktemp)"
trap 'rm -f "$pod_template"' EXIT
cat >"$pod_template" <<'YAML'
securityContext:
  fsGroup: 65532
  fsGroupChangePolicy: OnRootMismatch
YAML

printf '[INFO] Promoting %s from candidate %s after main accepted the exact source tree\n' \
    "$package_file" "$candidate_run"
tkn pipeline start "$pipeline" \
    --context "$context" \
    --namespace "$namespace" \
    --serviceaccount "$service_account" \
    --param "repo-url=$repo_url" \
    --param "revision=$revision" \
    --param "authorized-branch=$authorized_branch" \
    --param "release-tag=$release_tag" \
    --param "candidate-commit=$candidate_commit" \
    --param "package-file=$package_file" \
    --param "package-sha256=$package_sha256" \
    --param "symbols-file=$symbols_file" \
    --param "sbom-sha256=$sbom_sha256" \
    --param "evidence-file=$evidence_file" \
    --workspace "name=source,claimName=$candidate_pvc" \
    --pod-template "$pod_template" \
    --showlog \
    --exit-with-pipelinerun-error
