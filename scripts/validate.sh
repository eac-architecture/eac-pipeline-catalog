#!/usr/bin/env bash

set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
required_files=(
    "$root_dir/VERSION"
    "$root_dir/catalog/catalog.yaml"
    "$root_dir/catalog/shared/tasks/git-checkout/task.yaml"
    "$root_dir/catalog/profiles/packages/nuget/pipelines/continuous-integration.yaml"
    "$root_dir/catalog/profiles/packages/nuget/tasks/dotnet-test-kafka/task.yaml"
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

catalog_version="$(tr -d '[:space:]' < "$root_dir/VERSION")"
[[ "$catalog_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
    printf '[ERROR] Pipeline Catalog VERSION must be stable SemVer\n' >&2
    exit 1
}
grep -qF "version: $catalog_version" "$root_dir/catalog/catalog.yaml" || {
    printf '[ERROR] catalog/catalog.yaml must match VERSION %s\n' "$catalog_version" >&2
    exit 1
}
while IFS= read -r resource; do
    grep -qF "app.kubernetes.io/version: $catalog_version" "$resource" || {
        printf '[ERROR] Catalog resource metadata must match VERSION %s: %s\n' \
            "$catalog_version" "${resource#"$root_dir"/}" >&2
        exit 1
    }
done < <(find "$root_dir/catalog" -type f \( -name 'task.yaml' -o -path '*/pipelines/*.yaml' \))
if grep -R -nE 'eac-pipeline-catalog/v[0-9]+\.[0-9]+\.[0-9]+/' \
    "$root_dir/catalog/profiles" | grep -vF "eac-pipeline-catalog/v$catalog_version/"; then
    printf '[ERROR] Pipeline task references must match VERSION %s\n' "$catalog_version" >&2
    exit 1
fi
grep -qF 'label tasks,pipelines' "$root_dir/scripts/install.sh" || {
    printf '[ERROR] Catalog installer must label installed resources from VERSION\n' >&2
    exit 1
}

release_pipeline="$root_dir/catalog/profiles/packages/nuget/pipelines/release-candidate.yaml"
publication_pipeline="$root_dir/catalog/profiles/packages/nuget/pipelines/prerelease-publication.yaml"
stable_publication_pipeline="$root_dir/catalog/profiles/packages/nuget/pipelines/stable-publication.yaml"
ci_pipeline="$root_dir/catalog/profiles/packages/nuget/pipelines/continuous-integration.yaml"
kafka_test_task="$root_dir/catalog/profiles/packages/nuget/tasks/dotnet-test-kafka/task.yaml"
checkout_task="$root_dir/catalog/shared/tasks/git-checkout/task.yaml"
repository_validation_task="$root_dir/catalog/profiles/packages/nuget/tasks/repository-validate/task.yaml"
release_gate_task="$root_dir/catalog/profiles/packages/nuget/tasks/release-revision-gate/task.yaml"
if ! grep -A1 -qF 'name: HOME' "$checkout_task" ||
    ! grep -qF 'value: /tekton/home' "$checkout_task"; then
    printf '[ERROR] Git checkout must use the writable Tekton credential HOME\n' >&2
    exit 1
fi
if ! grep -qF 'secretName: eac-git-checkout' "$checkout_task" ||
    ! grep -qF 'optional: true' "$checkout_task" ||
    ! grep -qF 'mountPath: /var/run/eac/git-credentials' "$checkout_task"; then
    printf '[ERROR] Git checkout must mount the optional isolated credential Secret\n' >&2
    exit 1
fi
if ! grep -qF 'secretName: eac-git-checkout' "$release_gate_task" ||
    ! grep -qF 'optional: true' "$release_gate_task" ||
    ! grep -qF 'mountPath: /var/run/eac/git-credentials' "$release_gate_task" ||
    ! grep -qF 'value: /tekton/home' "$release_gate_task"; then
    printf '[ERROR] Release revision gate must mount the isolated Git credential Secret\n' >&2
    exit 1
fi
if [[ "$(grep -R -lF 'secretName: eac-git-checkout' "$root_dir/catalog" | wc -l | tr -d ' ')" != "2" ]]; then
    printf '[ERROR] Git credentials must be mounted only by checkout and release revision gate\n' >&2
    exit 1
fi
if grep -R -nE 'value: .*workspaces\.(source|artifacts)\.path.*/\.home$' \
    "$root_dir/catalog"; then
    printf '[ERROR] Task HOME must not copy Git credentials into a retained workspace\n' >&2
    exit 1
fi
if grep -Eq 'name: (token|password|username)' "$checkout_task"; then
    printf '[ERROR] Git checkout credentials must come from the isolated Secret, not Task parameters\n' >&2
    exit 1
fi
for pipeline in "$ci_pipeline" "$release_pipeline" "$publication_pipeline" "$stable_publication_pipeline"; do
    if grep -qF 'repository-script-contract' "$pipeline"; then
        printf '[ERROR] NuGet Pipeline cannot depend on repository scripts: %s\n' \
            "${pipeline#"$root_dir"/}" >&2
        exit 1
    fi
done
for declarative_input in VERSION global.json NuGet.Config .config/dotnet-tools.json IsPackable; do
    grep -qF "$declarative_input" "$repository_validation_task" || {
        printf '[ERROR] NuGet repository validation must require %s\n' "$declarative_input" >&2
        exit 1
    }
done
if grep -R -nE 'bash ./scripts/|scripts/(validate|build|test|pack|release-candidate)\.sh' \
    "$root_dir/catalog/profiles/packages/nuget"; then
    printf '[ERROR] NuGet catalog Tasks must execute native .NET operations instead of repository scripts\n' >&2
    exit 1
fi
grep -qF '$(tasks.validate.results.package-version)' "$release_pipeline" || {
    printf '[ERROR] Release candidate must resolve its version from repository validation\n' >&2
    exit 1
}
grep -qF '$(tasks.validate.results.package-version)' "$ci_pipeline" || {
    printf '[ERROR] NuGet CI must resolve its version from repository validation\n' >&2
    exit 1
}
grep -qF 'integration-profile=$integration_profile' "$root_dir/scripts/run-ci.sh" || {
    printf '[ERROR] Manual NuGet CI runner must forward integration-profile\n' >&2
    exit 1
}
for required in 'name: integration-profile' 'name: test-default' 'name: test-kafka' 'eac-dotnet-test-kafka'; do
    grep -qF "$required" "$ci_pipeline" || {
        printf '[ERROR] NuGet CI is missing optional integration routing: %s\n' "$required" >&2
        exit 1
    }
done
[[ "$(grep -cF 'input: $(params.integration-profile)' "$ci_pipeline")" -eq 2 ]] || {
    printf '[ERROR] NuGet CI must select exactly one test Task from integration-profile\n' >&2
    exit 1
}
if [[ -e "$root_dir/catalog/profiles/packages/nuget/pipelines/continuous-integration-kafka.yaml" ]] ||
    [[ -e "$root_dir/templates/pipelines-as-code/packages/nuget/continuous-integration-kafka.yaml.template" ]]; then
    printf '[ERROR] Kafka integration must not create a second NuGet Pipeline\n' >&2
    exit 1
fi
for required in 'confluentinc/cp-kafka:7.7.1' 'KAFKA_BOOTSTRAP_SERVERS' 'allowPrivilegeEscalation: false' 'runAsNonRoot: true'; do
    grep -qF "$required" "$kafka_test_task" || {
        printf '[ERROR] NuGet Kafka test Task is missing %s\n' "$required" >&2
        exit 1
    }
done
if grep -qF 'privileged: true' "$kafka_test_task"; then
    printf '[ERROR] NuGet Kafka test Task cannot require privileged containers\n' >&2
    exit 1
fi
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
    printf '[ERROR] Stable NuGet publication must support the Listed registry state\n' >&2
    exit 1
}
grep -qF "printf 'published'" \
    "$root_dir/catalog/profiles/packages/nuget/tasks/publish/task.yaml" || {
    printf '[ERROR] Prerelease NuGet publication must complete after registry acceptance\n' >&2
    exit 1
}
prerelease_publish_block="$(sed -n '/^    - name: publish$/,/^      workspaces:/p' "$publication_pipeline")"
stable_publish_block="$(sed -n '/^    - name: publish$/,/^      workspaces:/p' "$stable_publication_pipeline")"
all_non_publish_params="$(sed '/^    - name: publish$/,/^      workspaces:/d' "$publication_pipeline" "$stable_publication_pipeline")"
printf '%s\n' "$prerelease_publish_block" | grep -A1 -F 'name: wait-for-listing' | grep -qF 'value: "false"' || {
    printf '[ERROR] Prerelease publication must not wait for Listed registry state\n' >&2
    exit 1
}
printf '%s\n' "$stable_publish_block" | grep -A1 -F 'name: wait-for-listing' | grep -qF 'value: "true"' || {
    printf '[ERROR] Stable publication must wait for Listed registry state\n' >&2
    exit 1
}
if printf '%s\n' "$all_non_publish_params" | grep -qF 'name: wait-for-listing'; then
    printf '[ERROR] wait-for-listing belongs only to the NuGet publish Task\n' >&2
    exit 1
fi
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
