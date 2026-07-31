#!/usr/bin/env bash

set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
required_files=(
    "$root_dir/VERSION"
    "$root_dir/catalog/catalog.yaml"
    "$root_dir/catalog/profiles/packages/nuget/pipelines/continuous-integration.yaml"
    "$root_dir/templates/pipelines-as-code/packages/nuget/continuous-integration.yaml.template"
    "$root_dir/docs/architecture/EAC_PIPELINE_CATALOG.md"
    "$root_dir/docs/planning/PLAN_DE_IMPLEMENTACION.md"
)

for file in "${required_files[@]}"; do
    [[ -s "$file" ]] || {
        printf '[ERROR] Required catalog file is missing or empty: %s\n' \
            "${file#"$root_dir"/}" >&2
        exit 1
    }
done

task_count="$(find "$root_dir/catalog" -name 'task.yaml' -type f | wc -l | tr -d '[:space:]')"
pipeline_count="$(find "$root_dir/catalog/profiles" -path '*/pipelines/*.yaml' -type f | wc -l | tr -d '[:space:]')"
[[ "$task_count" -ge 1 && "$pipeline_count" -ge 1 ]] || {
    printf '[ERROR] The catalog must contain at least one Task and one Pipeline\n' >&2
    exit 1
}

printf '[OK] Catalog structure validated: %s Tasks, %s Pipelines\n' \
    "$task_count" \
    "$pipeline_count"
