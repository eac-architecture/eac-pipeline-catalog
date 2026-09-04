#!/usr/bin/env python3
"""Executable rule evidence for the implemented EAC Pipeline Catalog."""

from __future__ import annotations

import argparse
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CATALOG_RELEASE_PLACEHOLDER = "__CATALOG_RELEASE_VERSION__"


def npm_publisher_is_hardened(content: str) -> bool:
    script = content.split("script: |", 1)[-1]
    required = (
        'NPM_CONFIG_IGNORE_SCRIPTS, value: "true"',
        "name: package-digest",
        "EAC_PACKAGE_DIGEST",
        'actual_digest="$(sha256sum -- "$package"',
        '[[ "$actual_digest" == "$EAC_PACKAGE_DIGEST" ]]',
        "npm publish \"$package\" --access public --ignore-scripts",
    )
    return all(contract in content for contract in required) and "$(params." not in script


def deployment_contract_is_hardened(task: str, pipeline: str) -> bool:
    scripts = "\n".join(task.split("script: |")[1:])
    required = (
        "secretName: eac-deployment-target",
        "name: eac-deployment-policy",
        "/etc/eac/deployment-policy/api-url",
        "/etc/eac/deployment-policy/namespace",
        "/etc/eac/deployment-policy/allowed-image-repositories",
        "/etc/eac/deployment-policy/allowed-workloads",
        '[[ "$image_repository" == "$allowed_repository" ]]',
        '[[ "$EAC_WORKLOAD/$EAC_CONTAINER" == "$allowed_workload" ]]',
    )
    forbidden_params = ("name: target-api", "name: target-namespace", "name: smoke-url")
    return (
        all(contract in task for contract in required)
        and not any(param in task or param in pipeline for param in forbidden_params)
        and "$(params." not in scripts
    )


def rule(rule_id: str):
    def decorate(test):
        test.__eac_rule__ = rule_id
        return test
    return decorate


class PipelineCatalogContractTests(unittest.TestCase):
    @rule("EAC-PC-CATALOG-001")
    def test_consumer_template_resolves_the_versioned_catalog_pipeline(self) -> None:
        template = (ROOT / "templates/pipelines-as-code/packages/nuget/continuous-integration.yaml.template").read_text(encoding="utf-8")
        self.assertIn(f"eac-pipeline-catalog/v{CATALOG_RELEASE_PLACEHOLDER}/catalog/profiles/packages/nuget/pipelines/continuous-integration.yaml", template)
        self.assertNotIn("/main/", template)
        self.assertNotIn("/develop/", template)

    @rule("EAC-PC-VERSION-001")
    def test_unreleased_catalog_uses_an_explicit_release_placeholder(self) -> None:
        version = (ROOT / "VERSION").read_text(encoding="utf-8").strip()
        self.assertRegex(version, r"^\d+\.\d+\.\d+$")
        catalog = (ROOT / "catalog/catalog.yaml").read_text(encoding="utf-8")
        self.assertIn("status: unreleased", catalog)
        self.assertIn(f"remoteReference: {CATALOG_RELEASE_PLACEHOLDER}", catalog)
        self.assertEqual(5, catalog.count("status: implemented-unreleased"))
        for resource in list(ROOT.glob("catalog/**/task.yaml")) + list(ROOT.glob("catalog/**/pipelines/*.yaml")):
            content = resource.read_text(encoding="utf-8")
            self.assertIn(f"app.kubernetes.io/version: {version}", content, resource)
            self.assertNotIn(f"eac-pipeline-catalog/v{version}/", content, resource)
        for pipeline in ROOT.glob("catalog/**/pipelines/*.yaml"):
            content = pipeline.read_text(encoding="utf-8")
            if "raw.githubusercontent.com/eac-architecture/eac-pipeline-catalog/" in content:
                self.assertIn(f"/v{CATALOG_RELEASE_PLACEHOLDER}/", content, pipeline)
        for template in ROOT.glob("templates/pipelines-as-code/**/*.yaml.template"):
            content = template.read_text(encoding="utf-8")
            self.assertIn(f"eac-pipeline-catalog/v{CATALOG_RELEASE_PLACEHOLDER}/", content, template)
            self.assertNotIn(f"eac-pipeline-catalog/v{version}/", content, template)

    @rule("EAC-PC-CI-001")
    def test_ci_runs_validation_build_and_one_selected_test_without_publication(self) -> None:
        pipeline = (ROOT / "catalog/profiles/packages/nuget/pipelines/continuous-integration.yaml").read_text(encoding="utf-8")
        for task in ("name: validate", "name: build", "name: test-default", "name: test-kafka", "name: test-postgresql", "name: test-mongodb", "name: test-elasticsearch"):
            self.assertIn(task, pipeline)
        self.assertNotIn("eac-nuget-publish", pipeline)
        self.assertIn("name: commit-sha", pipeline)
        self.assertIn("name: test-status", pipeline)

    @rule("EAC-PC-ELASTICSEARCH-001")
    def test_elasticsearch_profile_reuses_the_nuget_pipelines_with_a_safe_real_node(self) -> None:
        task = (ROOT / "catalog/profiles/packages/nuget/tasks/dotnet-test-elasticsearch/task.yaml").read_text(encoding="utf-8")
        self.assertIn("docker.elastic.co/elasticsearch/elasticsearch:9.3.4", task)
        self.assertIn("EAC_ELASTICSEARCH_ENDPOINT", task)
        self.assertIn("allowPrivilegeEscalation: false", task)
        self.assertIn("runAsNonRoot: true", task)
        for pipeline_name in ("continuous-integration.yaml", "release-candidate.yaml", "prerelease-publication.yaml"):
            pipeline = (ROOT / "catalog/profiles/packages/nuget/pipelines" / pipeline_name).read_text(encoding="utf-8")
            self.assertIn("name: test-elasticsearch", pipeline)
            self.assertIn("eac-dotnet-test-elasticsearch", pipeline)

    @rule("EAC-PC-PRERELEASE-001")
    def test_prerelease_requires_release_revision_and_immutable_tag(self) -> None:
        pipeline = (ROOT / "catalog/profiles/packages/nuget/pipelines/prerelease-publication.yaml").read_text(encoding="utf-8")
        self.assertIn("eac-release-revision-gate", pipeline)
        self.assertIn("name: release-tag", pipeline)
        self.assertIn("name: publication-channel", pipeline)
        self.assertIn('value: "false"', pipeline)

    @rule("EAC-PC-STABLE-001")
    def test_stable_promotes_retained_candidate_without_rebuilding(self) -> None:
        pipeline = (ROOT / "catalog/profiles/packages/nuget/pipelines/stable-publication.yaml").read_text(encoding="utf-8")
        self.assertIn("eac-nuget-stable-candidate-gate", pipeline)
        self.assertIn("eac-nuget-publish", pipeline)
        self.assertIn('value: "true"', pipeline)
        self.assertNotIn("eac-dotnet-build", pipeline)
        self.assertNotIn("eac-dotnet-release-candidate", pipeline)

    @rule("EAC-PC-CRED-001")
    def test_credentials_are_isolated_to_checkout_release_gate_and_publisher(self) -> None:
        resources = list((ROOT / "catalog").glob("**/task.yaml"))
        git_secret_resources = [path for path in resources if "secretName: eac-git-checkout" in path.read_text(encoding="utf-8")]
        self.assertEqual(2, len(git_secret_resources))
        for path in git_secret_resources:
            self.assertIn("optional: true", path.read_text(encoding="utf-8"))
        publish = (ROOT / "catalog/profiles/packages/nuget/tasks/publish/task.yaml").read_text(encoding="utf-8")
        self.assertIn("secretKeyRef:", publish)

    @rule("EAC-PC-VALIDATE-001")
    def test_validation_gate_checks_scripts_catalog_and_reproducibility_contract(self) -> None:
        validation = (ROOT / "scripts/validate.sh").read_text(encoding="utf-8")
        for contract in ("bash -n", "task_count", "pipeline_count", "test-reproducibility.py", "test-catalog-contracts.py"):
            self.assertIn(contract, validation)

    @rule("EAC-PC-NPM-001")
    def test_npm_profile_verifies_retains_and_publishes_the_exact_package(self) -> None:
        verify = (ROOT / "catalog/profiles/packages/npm/tasks/verify-and-pack/task.yaml").read_text(encoding="utf-8")
        publish = (ROOT / "catalog/profiles/packages/npm/tasks/publish/task.yaml").read_text(encoding="utf-8")
        pipeline = (ROOT / "catalog/profiles/packages/npm/pipelines/publication.yaml").read_text(encoding="utf-8")
        for contract in ("npm ci --ignore-scripts", "npm test --if-present", "npm pack --ignore-scripts --json", "@eac-architecture/*", "sha256sum"):
            self.assertIn(contract, verify)
        self.assertIn("secretKeyRef:", publish)
        self.assertIn("name: eac-release-publishing", publish)
        self.assertIn("key: npm-token", publish)
        self.assertTrue(npm_publisher_is_hardened(publish))
        self.assertIn("$(tasks.verify-and-pack.results.package-file)", pipeline)
        self.assertIn("$(tasks.verify-and-pack.results.package-digest)", pipeline)
        self.assertIn("eac-release-revision-gate", pipeline)
        self.assertNotIn("NPM_TOKEN", pipeline)
        unsafe_mutations = (
            publish.replace('NPM_CONFIG_IGNORE_SCRIPTS, value: "true"', 'NPM_CONFIG_IGNORE_SCRIPTS, value: "false"'),
            publish.replace(" --ignore-scripts", "", 1),
            publish.replace('[[ "$actual_digest" == "$EAC_PACKAGE_DIGEST" ]]', '[[ -n "$actual_digest" ]]'),
        )
        for unsafe_contract in unsafe_mutations:
            with self.subTest(unsafe_contract=unsafe_contract):
                self.assertFalse(npm_publisher_is_hardened(unsafe_contract))

    @rule("EAC-PC-ANGULAR-001")
    def test_angular_profile_rejects_non_reproducible_production_bundles(self) -> None:
        task = (ROOT / "catalog/profiles/applications/angular/tasks/build-reproducible/task.yaml").read_text(encoding="utf-8")
        for contract in ("npm ci --ignore-scripts", "--configuration production", "--sort=name", "--mtime='@0'", "gzip -n", "cmp /tmp/angular-first.tar.gz /tmp/angular-second.tar.gz"):
            self.assertIn(contract, task)

    @rule("EAC-PC-OCI-001")
    def test_dotnet_service_profile_builds_once_and_publishes_retained_image_by_digest(self) -> None:
        archive = (ROOT / "catalog/profiles/services/dotnet/tasks/verify-and-archive/task.yaml").read_text(encoding="utf-8")
        publish = (ROOT / "catalog/profiles/services/dotnet/tasks/publish-image/task.yaml").read_text(encoding="utf-8")
        pipeline = (ROOT / "catalog/profiles/services/dotnet/pipelines/publication.yaml").read_text(encoding="utf-8")
        self.assertIn("/t:PublishContainer", archive)
        self.assertIn("ContainerArchiveOutputPath", archive)
        self.assertIn("skopeo copy", publish)
        self.assertIn("--digestfile", publish)
        self.assertIn('actual_digest="$(sha256sum -- "$archive"', publish)
        self.assertIn('[[ "$actual_digest" == "$EAC_ARCHIVE_DIGEST" ]]', publish)
        self.assertNotIn("dotnet publish", publish)
        self.assertIn("$(tasks.verify-and-archive.results.image-archive)", pipeline)
        self.assertIn("$(tasks.verify-and-archive.results.archive-digest)", pipeline)
        self.assertIn("eac-release-revision-gate", pipeline)
        self.assertLess(publish.index('[[ "$actual_digest" == "$EAC_ARCHIVE_DIGEST" ]]'), publish.index("skopeo copy"))

    @rule("EAC-PC-DEPLOY-001")
    def test_deployment_profile_accepts_only_digest_and_never_builds(self) -> None:
        task = (ROOT / "catalog/profiles/deployments/tasks/promote-by-digest/task.yaml").read_text(encoding="utf-8")
        pipeline = (ROOT / "catalog/profiles/deployments/pipelines/promotion.yaml").read_text(encoding="utf-8")
        for contract in ("@sha256:[0-9a-f]{64}", "oc --namespace", "set image", "rollout status", "secretName: eac-deployment-target", "name: eac-deployment-policy"):
            self.assertIn(contract, task)
        self.assertTrue(deployment_contract_is_hardened(task, pipeline))
        for forbidden in ("dotnet build", "npm run build", "docker build", "buildah bud", "oc apply"):
            self.assertNotIn(forbidden, task)
        unsafe_mutations = (
            pipeline.replace("spec:\n  params:", "spec:\n  params:\n    - {name: target-api, type: string}"),
            task.replace('image="$EAC_IMAGE_REFERENCE"', "image='$(params.image-reference)'"),
            task.replace('/etc/eac/deployment-policy/allowed-image-repositories', '/tmp/untrusted-allowlist'),
        )
        for unsafe_contract in unsafe_mutations:
            with self.subTest(unsafe_contract=unsafe_contract):
                if unsafe_contract.startswith("apiVersion: tekton.dev/v1\nkind: Pipeline"):
                    self.assertFalse(deployment_contract_is_hardened(task, unsafe_contract))
                else:
                    self.assertFalse(deployment_contract_is_hardened(unsafe_contract, pipeline))

    @rule("EAC-PC-IMAGE-001")
    def test_catalog_execution_images_are_pinned_by_verified_digest(self) -> None:
        tasks = {
            "catalog/profiles/packages/npm/tasks/verify-and-pack/task.yaml": "node:22.14.0-bookworm-slim@sha256:1c18d9ab3af4585870b92e4dbc5cac5a0dc77dd13df1a5905cea89fc720eb05b",
            "catalog/profiles/packages/npm/tasks/publish/task.yaml": "node:22.14.0-bookworm-slim@sha256:1c18d9ab3af4585870b92e4dbc5cac5a0dc77dd13df1a5905cea89fc720eb05b",
            "catalog/profiles/applications/angular/tasks/build-reproducible/task.yaml": "node:22.14.0-bookworm-slim@sha256:1c18d9ab3af4585870b92e4dbc5cac5a0dc77dd13df1a5905cea89fc720eb05b",
            "catalog/profiles/services/dotnet/tasks/verify-and-archive/task.yaml": "mcr.microsoft.com/dotnet/sdk:10.0.201@sha256:127d7d4d601ae26b8e04c54efb37e9ce8766931bded0ee59fcd799afd21d6850",
            "catalog/profiles/services/dotnet/tasks/publish-image/task.yaml": "quay.io/skopeo/stable:v1.18.0@sha256:c4c8a9d6fc95e331fa92fc31de3f6c9b5fe4761c82f0acb99669eef067fb7c33",
            "catalog/profiles/deployments/tasks/promote-by-digest/task.yaml": "quay.io/openshift/origin-cli:4.18@sha256:4c1b64a79727e392c11cf337936f9edb792e436075d4bdad5f554b79652d16dd",
        }
        image_pattern = re.compile(r"^\s+image: [^\s]+@sha256:[0-9a-f]{64}$", re.MULTILINE)
        for relative_path, expected_image in tasks.items():
            content = (ROOT / relative_path).read_text(encoding="utf-8")
            image_lines = [line for line in content.splitlines() if line.lstrip().startswith("image:")]
            self.assertGreater(len(image_lines), 0, relative_path)
            self.assertIn(f"image: {expected_image}", content, relative_path)
            for image_line in image_lines:
                self.assertRegex(image_line, image_pattern, relative_path)
        deployment = (ROOT / "catalog/profiles/deployments/tasks/promote-by-digest/task.yaml").read_text(encoding="utf-8")
        self.assertIn("image: curlimages/curl:8.12.1@sha256:94e9e444bcba979c2ea12e27ae39bee4cd10bc7041a472c4727a558e213744e6", deployment)
        expected_images = set(tasks.values()) | {
            "curlimages/curl:8.12.1@sha256:94e9e444bcba979c2ea12e27ae39bee4cd10bc7041a472c4727a558e213744e6",
            "alpine/git:2.49.1@sha256:c0280cf9572316299b08544065d3bf35db65043d5e3963982ec50647d2746e26",
            "docker.elastic.co/elasticsearch/elasticsearch:9.3.4@sha256:5111553c2a04b2a1782c7881248c6b6cceabbcf34758e778ee387f5843745e58",
            "python:3.11.9-alpine3.20@sha256:f9ce6fe33d9a5499e35c976df16d24ae80f6ef0a28be5433140236c2ca482686",
            "confluentinc/cp-kafka:7.7.1@sha256:653f49c51cfebcf8301938d01044efead6afbd8dd60acd2bcf1605d7c6494d3b",
            "mongo:8.0.16@sha256:4b58ebcb1dc7a7b4e84cd8ce9098d48764ae4478876898ff9551acf2ac4a6a6d",
            "postgres:17.6-alpine3.22@sha256:ef257d85f76e48da1c64832459b59fcaba1a4dac97bf5d7450c77753542eee94",
        }
        actual_images = set()
        for task in ROOT.glob("catalog/**/task.yaml"):
            content = task.read_text(encoding="utf-8")
            for image_line in (line for line in content.splitlines() if line.lstrip().startswith("image:")):
                self.assertRegex(image_line, image_pattern, task)
                actual_images.add(image_line.split("image:", 1)[1].strip())
        self.assertEqual(expected_images, actual_images)
        design = (ROOT / "docs/architecture/EAC_PIPELINE_CATALOG.md").read_text(encoding="utf-8")
        for image in expected_images:
            tag, digest = image.split("@", 1)
            self.assertIn(f"`{tag}`", design)
            self.assertIn(f"`{digest}`", design)

    @rule("EAC-PC-STARTER-001")
    def test_service_starter_binding_generates_only_versioned_pipeline_runs(self) -> None:
        binding = (ROOT / "templates/service-starter/bindings.yaml").read_text(encoding="utf-8")
        version = (ROOT / "VERSION").read_text(encoding="utf-8").strip()
        self.assertIn(f"plannedCatalogVersion: {version}", binding)
        self.assertIn(f"catalogVersion: {CATALOG_RELEASE_PLACEHOLDER}", binding)
        self.assertIn("releaseStatus: unreleased", binding)
        self.assertIn(".tekton/continuous-integration.yaml", binding)
        self.assertIn(".tekton/deployment.yaml", binding)
        self.assertIn("forbiddenGeneratedKinds:\n    - Task\n    - Pipeline", binding)
        for template in ("templates/pipelines-as-code/services/dotnet/continuous-integration.yaml.template", "templates/pipelines-as-code/deployments/promotion.yaml.template"):
            content = (ROOT / template).read_text(encoding="utf-8")
            self.assertIn(f"eac-pipeline-catalog/v{CATALOG_RELEASE_PLACEHOLDER}/", content)
            self.assertIn("kind: PipelineRun", content)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--list-rules", action="store_true")
    args = parser.parse_args()
    if args.list_rules:
        for name in dir(PipelineCatalogContractTests):
            rule_id = getattr(getattr(PipelineCatalogContractTests, name), "__eac_rule__", None)
            if rule_id:
                print(rule_id)
        return 0
    result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(PipelineCatalogContractTests))
    return 0 if result.wasSuccessful() else 1


if __name__ == "__main__":
    raise SystemExit(main())
