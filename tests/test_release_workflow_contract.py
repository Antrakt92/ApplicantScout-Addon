from __future__ import annotations

import re
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]


def _workflow_source() -> str:
    return (REPO_ROOT / ".github" / "workflows" / "release.yml").read_text(
        encoding="utf-8"
    )


def _read_repo_text(path: str) -> str:
    return (REPO_ROOT / path).read_text(encoding="utf-8")


def test_release_preflight_runs_transport_contract_tests():
    workflow = _workflow_source()

    setup_idx = workflow.index("actions/setup-python")
    pytest_idx = workflow.index("python -m pytest -q tests/test_transport_contract.py")
    package_idx = workflow.index("Development package smoke")
    packager_idx = workflow.index("BigWigsMods/packager@v2")

    assert setup_idx < pytest_idx < package_idx < packager_idx
    assert "python-version: '3.13'" in workflow


def test_local_package_smoke_is_labeled_as_development_zip_only():
    workflow = _workflow_source()
    readme = (REPO_ROOT / "README.md").read_text(encoding="utf-8")
    package_script = (REPO_ROOT / "scripts" / "package-addon.ps1").read_text(
        encoding="utf-8"
    )

    assert "Development package smoke" in workflow
    assert "development-only addon ZIP" in readme
    assert "development-only addon ZIP" in package_script


def test_package_script_uses_zip_extension_for_temporary_archive():
    package_script = (REPO_ROOT / "scripts" / "package-addon.ps1").read_text(
        encoding="utf-8"
    )

    assert ".tmp.zip" in package_script
    assert ".zip.tmp" not in package_script


def test_package_script_normalizes_zip_entry_separators():
    package_script = (REPO_ROOT / "scripts" / "package-addon.ps1").read_text(
        encoding="utf-8"
    )

    assert "$_.FullName -replace '\\\\', '/'" in package_script


def test_pkgmeta_excludes_tests_and_dev_only_release_inputs_from_marketplace_zip():
    pkgmeta = _read_repo_text(".pkgmeta")

    for ignored in (
        ".github",
        "README.md",
        "scripts",
        "docs",
        "dist",
        "tests",
        "AGENTS.md",
        "AUDIT.md",
        "PLAN.md",
        "NOTES.md",
        "TODO.md",
    ):
        assert re.search(rf"(?m)^\s*-\s+{re.escape(ignored)}\s*$", pkgmeta)
    assert re.search(r'(?m)^\s*-\s+"?\*\.private\.md"?\s*$', pkgmeta)


def test_package_script_dirty_inputs_include_release_shaping_metadata():
    package_script = _read_repo_text("scripts/package-addon.ps1")

    release_inputs = re.search(
        r"\$ReleaseInputFiles\s*=\s*([^\n]+(?:\n\s+[^\n]+)*)",
        package_script,
    )

    assert release_inputs is not None
    release_input_block = release_inputs.group(0)
    assert ".pkgmeta" in release_input_block
    assert "CHANGELOG.md" in release_input_block


def test_package_script_keeps_runtime_install_contract_minimal():
    package_script = _read_repo_text("scripts/package-addon.ps1")

    required_block = package_script[
        package_script.index("$RequiredFiles = @(") : package_script.index(
            ")", package_script.index("$RequiredFiles = @(")
        )
    ]

    for required in (
        "ApplicantScout.toc",
        "ApplicantScout.lua",
        "LICENSE",
        "THIRD-PARTY-NOTICES.md",
        "media\\logo.png",
        "libs\\qrencode.lua",
    ):
        assert required in required_block

    assert "README.md" not in required_block
    assert "CHANGELOG.md" not in required_block


def test_toc_loads_qr_library_before_addon_runtime():
    toc = _read_repo_text("ApplicantScout.toc")

    assert toc.index("libs\\qrencode.lua") < toc.index("ApplicantScout.lua")
