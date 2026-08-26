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

    @rule("EAC-PC-CI-001")
    def test_ci_runs_validation_build_and_one_selected_test_without_publication(self) -> None:
        pipeline = (ROOT / "catalog/profiles/packages/nuget/pipelines/continuous-integration.yaml").read_text(encoding="utf-8")
        for task in ("name: validate", "name: build", "name: test-default", "name: test-kafka", "name: test-postgresql", "name: test-mongodb"):
            self.assertIn(task, pipeline)
        self.assertNotIn("eac-nuget-publish", pipeline)
        self.assertIn("name: commit-sha", pipeline)
        self.assertIn("name: test-status", pipeline)

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
