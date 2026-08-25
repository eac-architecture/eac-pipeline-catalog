#!/usr/bin/env python3

import hashlib
import json
import os
import pathlib
import subprocess
import sys
import tempfile
import uuid
import zipfile


ROOT = pathlib.Path(__file__).resolve().parents[1]
TASK = ROOT / "catalog/profiles/packages/nuget/tasks/release-candidate/task.yaml"
RULE_IDS = ("EAC-PC-CANDIDATE-001",)
EPOCH = "1700000000"
PACKAGE_ID = "EAC.Reproducibility.Sample"
PACKAGE_VERSION = "1.0.0-rc.1"
COMMIT = "0123456789abcdef0123456789abcdef01234567"
NAMESPACE_BASE = "https://github.com/eac-architecture/sbom"


def extract_normalizer(target: pathlib.Path) -> None:
    lines = TASK.read_text(encoding="utf-8").splitlines()
    begin = lines.index("        # EAC_REPRODUCIBILITY_NORMALIZER_BEGIN")
    heredoc = next(index for index in range(begin + 1, len(lines)) if "<<'CSHARP'" in lines[index])
    end = next(index for index in range(heredoc + 1, len(lines)) if lines[index].strip() == "CSHARP")
    source = "\n".join(line[8:] if line.startswith("        ") else line for line in lines[heredoc + 1 : end]) + "\n"
    target.write_text(source, encoding="utf-8", newline="\n")


def create_package(path: pathlib.Path, timestamp: tuple[int, int, int, int, int, int]) -> None:
    core_name = f"package/services/metadata/core-properties/{uuid.uuid4().hex}.psmdcp"
    relationships = (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\n'
        f'  <Relationship Type="http://schemas.microsoft.com/packaging/2010/07/manifest" Target="/{PACKAGE_ID}.nuspec" Id="R{uuid.uuid4().hex}" />\n'
        f'  <Relationship Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="/{core_name}" Id="R{uuid.uuid4().hex}" />\n'
        '</Relationships>\n'
    ).encode()
    entries = {
        "[Content_Types].xml": b"<Types />\n",
        "_rels/.rels": relationships,
        f"{PACKAGE_ID}.nuspec": b"<package><metadata><id>EAC.Reproducibility.Sample</id></metadata></package>\n",
        core_name: b"<coreProperties><version>1.0.0-rc.1</version></coreProperties>\n",
        "lib/net10.0/EAC.Reproducibility.Sample.dll": b"deterministic assembly bytes",
    }
    with zipfile.ZipFile(path, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for name, content in entries.items():
            info = zipfile.ZipInfo(name, timestamp)
            info.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(info, content)


def digest(path: pathlib.Path, algorithm: str = "sha256") -> str:
    hasher = hashlib.new(algorithm)
    hasher.update(path.read_bytes())
    return hasher.hexdigest()


def create_sbom(path: pathlib.Path, package_dir: pathlib.Path, reverse: bool) -> None:
    files = []
    for package in sorted(package_dir.iterdir()):
        sha256 = digest(package)
        sha1 = digest(package, "sha1")
        spdx_id = f"SPDXRef-File--{package.name}-{sha1.upper()}"
        files.append(
            {
                "fileName": f"./{package.name}",
                "SPDXID": spdx_id,
                "checksums": [
                    {"algorithm": "SHA256", "checksumValue": sha256},
                    {"algorithm": "SHA1", "checksumValue": sha1},
                ],
            }
        )
    has_files = sorted((entry["SPDXID"] for entry in files), reverse=reverse)
    document = {
        "files": files,
        "packages": [
            {
                "name": PACKAGE_ID,
                "SPDXID": "SPDXRef-RootPackage",
                "externalRefs": [
                    {
                        "referenceCategory": "PACKAGE-MANAGER",
                        "referenceType": "purl",
                        "referenceLocator": f"pkg:swid/eac/{PACKAGE_ID}@{PACKAGE_VERSION}?tag_id={uuid.uuid4()}",
                    }
                ],
                "hasFiles": has_files,
            }
        ],
        "spdxVersion": "SPDX-2.2",
        "SPDXID": "SPDXRef-DOCUMENT",
        "documentNamespace": f"{NAMESPACE_BASE}/{PACKAGE_ID}/{PACKAGE_VERSION}/{uuid.uuid4()}",
        "creationInfo": {"created": "2026-01-01T00:00:00Z", "creators": ["Tool: test"]},
    }
    path.write_text(json.dumps(document, indent=2) + "\n", encoding="utf-8", newline="\n")


def run_normalizer(source: pathlib.Path, arguments: list[str], environment: dict[str, str]) -> None:
    process = subprocess.run(
        ["dotnet", "run", "--file", str(source), *arguments],
        cwd=source.parent,
        env=environment,
        check=False,
        capture_output=True,
        text=True,
    )
    if process.returncode != 0:
        raise RuntimeError(process.stdout + process.stderr)


def main() -> None:
    if sys.argv[1:] == ["--list-rules"]:
        print("\n".join(RULE_IDS))
        return

    with tempfile.TemporaryDirectory(prefix="eac-reproducibility-") as temporary:
        root = pathlib.Path(temporary)
        normalizer = root / "normalize.cs"
        first = root / "first"
        second = root / "second"
        first.mkdir()
        second.mkdir()
        extract_normalizer(normalizer)

        filenames = (f"{PACKAGE_ID}.{PACKAGE_VERSION}.nupkg", f"{PACKAGE_ID}.{PACKAGE_VERSION}.snupkg")
        for filename in filenames:
            create_package(first / filename, (2025, 1, 1, 0, 0, 0))
            create_package(second / filename, (2026, 2, 2, 3, 4, 6))

        environment = os.environ.copy()
        environment.update(
            {
                "APPDATA": str(root / "profile"),
                "DOTNET_CLI_HOME": str(root / "dotnet-home"),
                "DOTNET_CLI_TELEMETRY_OPTOUT": "1",
                "DOTNET_NOLOGO": "1",
                "HOME": str(root / "profile"),
                "NUGET_PACKAGES": str(root / "packages"),
                "USERPROFILE": str(root / "profile"),
            }
        )
        nuget_config_dir = pathlib.Path(environment["APPDATA"]) / "NuGet"
        nuget_config_dir.mkdir(parents=True)
        (nuget_config_dir / "NuGet.Config").write_text(
            '<?xml version="1.0" encoding="utf-8"?>\n'
            '<configuration><packageSources><clear /></packageSources></configuration>\n',
            encoding="utf-8",
            newline="\n",
        )

        run_normalizer(normalizer, ["package", EPOCH, *(str(first / name) for name in filenames)], environment)
        run_normalizer(normalizer, ["package", EPOCH, *(str(second / name) for name in filenames)], environment)

        for filename in filenames:
            first_package = first / filename
            second_package = second / filename
            if digest(first_package) != digest(second_package):
                raise AssertionError(f"Package is not reproducible: {filename}")
            with zipfile.ZipFile(first_package) as archive:
                names = archive.namelist()
                if "package/services/metadata/core-properties/coreProperties.psmdcp" not in names:
                    raise AssertionError("Canonical core-properties entry is missing")
                relationships = archive.read("_rels/.rels").decode()
                if 'Id="RCoreProperties"' not in relationships or 'Id="RManifest"' not in relationships:
                    raise AssertionError("Package relationships were not canonicalized")

        first_sbom = first / "manifest.spdx.json"
        second_sbom = second / "manifest.spdx.json"
        create_sbom(first_sbom, first, reverse=False)
        create_sbom(second_sbom, second, reverse=True)
        sbom_arguments = [EPOCH, PACKAGE_ID, PACKAGE_VERSION, COMMIT, NAMESPACE_BASE]
        run_normalizer(normalizer, ["sbom", *sbom_arguments, str(first_sbom)], environment)
        run_normalizer(normalizer, ["sbom", *sbom_arguments, str(second_sbom)], environment)
        if first_sbom.read_bytes() != second_sbom.read_bytes():
            raise AssertionError("SPDX evidence is not reproducible")

    print("[OK] EAC-PC-CANDIDATE-001 reproducibility regression passed")


if __name__ == "__main__":
    main()
