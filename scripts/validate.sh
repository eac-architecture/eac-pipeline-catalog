#!/usr/bin/env bash

set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
required_files=(
    "$root_dir/VERSION"
    "$root_dir/catalog/catalog.yaml"
    "$root_dir/catalog/profiles/packages/nuget/pipelines/continuous-integration.yaml"
    "$root_dir/catalog/profiles/packages/nuget/pipelines/release-candidate.yaml"
    "$root_dir/catalog/profiles/packages/nuget/pipelines/prerelease-publication.yaml"
    "$root_dir/catalog/profiles/packages/nuget/pipelines/stable-publication.yaml"
    "$root_dir/catalog/profiles/packages/nuget/tasks/stable-candidate-gate/task.yaml"
    "$root_dir/templates/pipelines-as-code/packages/nuget/continuous-integration.yaml.template"
    "$root_dir/docs/architecture/EAC_PIPELINE_CATALOG.md"
    "$root_dir/docs/planning/PLAN_DE_IMPLEMENTACION.md"
    "$root_dir/scripts/install.sh"
    "$root_dir/scripts/run-ci.sh"
    "$root_dir/scripts/run-release-candidate.sh"
    "$root_dir/scripts/run-prerelease-publication.sh"
    "$root_dir/scripts/run-stable-publication.sh"
    "$root_dir/scripts/clean.sh"
)

for file in "${required_files[@]}"; do
    [[ -s "$file" ]] || {
        printf '[ERROR] Required catalog file is missing or empty: %s\n' \
            "${file#"$root_dir"/}" >&2
        exit 1
    }
done

for script in "$root_dir"/scripts/*.sh; do
    bash -n "$script"
done

task_count="$(find "$root_dir/catalog" -name 'task.yaml' -type f | wc -l | tr -d '[:space:]')"
pipeline_count="$(find "$root_dir/catalog/profiles" -path '*/pipelines/*.yaml' -type f | wc -l | tr -d '[:space:]')"
[[ "$task_count" -ge 1 && "$pipeline_count" -ge 1 ]] || {
    printf '[ERROR] The catalog must contain at least one Task and one Pipeline\n' >&2
    exit 1
}

release_pipeline="$root_dir/catalog/profiles/packages/nuget/pipelines/release-candidate.yaml"
publication_pipeline="$root_dir/catalog/profiles/packages/nuget/pipelines/prerelease-publication.yaml"
stable_publication_pipeline="$root_dir/catalog/profiles/packages/nuget/pipelines/stable-publication.yaml"
ci_pipeline="$root_dir/catalog/profiles/packages/nuget/pipelines/continuous-integration.yaml"
grep -qF '$(tasks.validate.results.package-version)' "$release_pipeline" || {
    printf '[ERROR] Release candidate must resolve its version from repository validation\n' >&2
    exit 1
}
grep -qF '$(tasks.validate.results.package-version)' "$ci_pipeline" || {
    printf '[ERROR] NuGet CI must resolve its version from repository validation\n' >&2
    exit 1
}
if grep -qF '$(params.version)' "$release_pipeline" ||
    grep -q -- '--param "version=' "$root_dir/scripts/run-release-candidate.sh"; then
    printf '[ERROR] Release candidate cannot accept a free version parameter\n' >&2
    exit 1
fi
grep -qF 'eac-release-revision-gate' "$publication_pipeline" || {
    printf '[ERROR] Prerelease publication must verify its release branch and immutable tag\n' >&2
    exit 1
}
grep -qF 'release-tag' "$publication_pipeline" || {
    printf '[ERROR] Prerelease publication must require an immutable release tag\n' >&2
    exit 1
}
grep -qF 'publication-channel' "$publication_pipeline" || {
    printf '[ERROR] Prerelease publication must declare its publication channel\n' >&2
    exit 1
}
grep -qF 'value: stable' "$stable_publication_pipeline" || {
    printf '[ERROR] Stable publication must use the stable publication gate\n' >&2
    exit 1
}
grep -qF 'eac-nuget-publish' "$stable_publication_pipeline" || {
    printf '[ERROR] Stable publication must use the dedicated publish Task\n' >&2
    exit 1
}
grep -qF 'eac-nuget-stable-candidate-gate' "$stable_publication_pipeline" || {
    printf '[ERROR] Stable publication must promote a previously verified candidate\n' >&2
    exit 1
}
if grep -qF 'eac-dotnet-build' "$stable_publication_pipeline" ||
    grep -qF 'eac-dotnet-release-candidate' "$stable_publication_pipeline"; then
    printf '[ERROR] Stable publication must not rebuild the verified candidate\n' >&2
    exit 1
fi
grep -qF 'claimName=' "$root_dir/scripts/run-stable-publication.sh" || {
    printf '[ERROR] Stable publication must reuse the retained candidate workspace\n' >&2
    exit 1
}
grep -qF 'subPath: artifacts' "$stable_publication_pipeline" || {
    printf '[ERROR] Stable publication must isolate artifacts through a workspace subPath\n' >&2
    exit 1
}
grep -qF 'eac-nuget-publish' "$publication_pipeline" || {
    printf '[ERROR] Prerelease publication must use the dedicated publish Task\n' >&2
    exit 1
}
if grep -q -- '--workspace "name=artifacts,' \
    "$root_dir/scripts/run-release-candidate.sh" \
    "$root_dir/scripts/run-prerelease-publication.sh"; then
    printf '[ERROR] NuGet release profiles must use one persistent workspace\n' >&2
    exit 1
fi
grep -qF 'subPath: artifacts' "$publication_pipeline" || {
    printf '[ERROR] NuGet publication must isolate artifacts through a workspace subPath\n' >&2
    exit 1
}
if grep -qF '$(workspaces.artifacts.path)' \
    "$root_dir/catalog/profiles/packages/nuget/tasks/release-candidate/task.yaml"; then
    printf '[ERROR] Release candidate must write artifacts inside the source workspace\n' >&2
    exit 1
fi
grep -qF 'secretKeyRef:' "$root_dir/catalog/profiles/packages/nuget/tasks/publish/task.yaml" || {
    printf '[ERROR] NuGet publication credential must come from a Kubernetes Secret\n' >&2
    exit 1
}
grep -qF 'RegistrationsBaseUrl/3.6.0' \
    "$root_dir/catalog/profiles/packages/nuget/tasks/publish/task.yaml" || {
    printf '[ERROR] NuGet publication must discover the registration resource\n' >&2
    exit 1
}
grep -qF 'result.write("listed")' \
    "$root_dir/catalog/profiles/packages/nuget/tasks/publish/task.yaml" || {
    printf '[ERROR] NuGet publication must confirm the Listed registry state\n' >&2
    exit 1
}
grep -qF '$(tasks.validate.results.package-version)' "$publication_pipeline" || {
    printf '[ERROR] NuGet publication must verify the exact declared package version\n' >&2
    exit 1
}
for maturity in 'alpha.N' 'beta.N' 'rc.N'; do
    grep -qF "$maturity" "$root_dir/docs/architecture/EAC_PIPELINE_CATALOG.md" || {
        printf '[ERROR] NuGet candidate documentation must cover %s maturity\n' \
            "$maturity" >&2
        exit 1
    }
done

printf '[OK] Catalog structure and scripts validated: %s Tasks, %s Pipelines\n' \
    "$task_count" \
    "$pipeline_count"
