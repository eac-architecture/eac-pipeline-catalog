#!/usr/bin/env python3
"""Executable rule evidence for the implemented NuGet Pipeline Catalog."""

from __future__ import annotations

import argparse
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def rule(rule_id: str):
    def decorate(test):
        test.__eac_rule__ = rule_id
        return test
    return decorate


class PipelineCatalogContractTests(unittest.TestCase):
    @rule("EAC-PC-CATALOG-001")
    def test_consumer_template_resolves_the_versioned_catalog_pipeline(self) -> None:
        version = (ROOT / "VERSION").read_text(encoding="utf-8").strip()
        template = (ROOT / "templates/pipelines-as-code/packages/nuget/continuous-integration.yaml.template").read_text(encoding="utf-8")
        self.assertIn(f"eac-pipeline-catalog/v{version}/catalog/profiles/packages/nuget/pipelines/continuous-integration.yaml", template)

    @rule("EAC-PC-VERSION-001")
    def test_catalog_resources_and_remote_references_use_the_stable_catalog_version(self) -> None:
        version = (ROOT / "VERSION").read_text(encoding="utf-8").strip()
        self.assertRegex(version, r"^\d+\.\d+\.\d+$")
        for resource in list(ROOT.glob("catalog/**/task.yaml")) + list(ROOT.glob("catalog/**/pipelines/*.yaml")):
            content = resource.read_text(encoding="utf-8")
            self.assertIn(f"app.kubernetes.io/version: {version}", content, resource)
            self.assertNotRegex(content, r"eac-pipeline-catalog/v(?!" + re.escape(version) + r"/)")
        for template in ROOT.glob("templates/pipelines-as-code/**/*.yaml.template"):
            content = template.read_text(encoding="utf-8")
            self.assertIn(f"eac-pipeline-catalog/v{version}/", content, template)
            self.assertNotRegex(content, r"eac-pipeline-catalog/v(?!" + re.escape(version) + r"/)")

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
        self.assertIn("$(tasks.verify-and-pack.results.package-file)", pipeline)
        self.assertIn("eac-release-revision-gate", pipeline)
        self.assertNotIn("NPM_TOKEN", pipeline)

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
        self.assertNotIn("dotnet publish", publish)
        self.assertIn("$(tasks.verify-and-archive.results.image-archive)", pipeline)
        self.assertIn("eac-release-revision-gate", pipeline)

    @rule("EAC-PC-DEPLOY-001")
    def test_deployment_profile_accepts_only_digest_and_never_builds(self) -> None:
        task = (ROOT / "catalog/profiles/deployments/tasks/promote-by-digest/task.yaml").read_text(encoding="utf-8")
        for contract in ("@sha256:[0-9a-f]{64}", "oc --namespace", "set image", "rollout status", "secretName: eac-deployment-target"):
            self.assertIn(contract, task)
        for forbidden in ("dotnet build", "npm run build", "docker build", "buildah bud"):
            self.assertNotIn(forbidden, task)

    @rule("EAC-PC-STARTER-001")
    def test_service_starter_binding_generates_only_versioned_pipeline_runs(self) -> None:
        binding = (ROOT / "templates/service-starter/bindings.yaml").read_text(encoding="utf-8")
        version = (ROOT / "VERSION").read_text(encoding="utf-8").strip()
        self.assertIn(f"catalogVersion: {version}", binding)
        self.assertIn(".tekton/continuous-integration.yaml", binding)
        self.assertIn(".tekton/deployment.yaml", binding)
        self.assertIn("forbiddenGeneratedKinds:\n    - Task\n    - Pipeline", binding)
        for template in ("templates/pipelines-as-code/services/dotnet/continuous-integration.yaml.template", "templates/pipelines-as-code/deployments/promotion.yaml.template"):
            content = (ROOT / template).read_text(encoding="utf-8")
            self.assertIn(f"eac-pipeline-catalog/v{version}/", content)
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
