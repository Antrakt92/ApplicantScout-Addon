from __future__ import annotations

from collections import Counter
import re
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
_ACTION_USES_RE = re.compile(r"(?m)^\s*uses:\s*([^\s#]+)\s*(?:#.*)?$")
_SHA_REF_RE = re.compile(r"^[0-9a-f]{40}$", re.I)
_CHOCO_INSTALL_LINE_RE = re.compile(
    r"(?im)^\s*(?:run:\s*)?choco\s+install\s+([A-Za-z0-9_.-]+)\b([^\r\n]*)"
)
_RELEASE_TOOL_PACKAGES = {
    "lua51": "5.1.5",
}


def _workflow_source() -> str:
    return (REPO_ROOT / ".github" / "workflows" / "release.yml").read_text(
        encoding="utf-8"
    )


def _read_repo_text(path: str) -> str:
    return (REPO_ROOT / path).read_text(encoding="utf-8")


def _workflow_action_refs(workflow: str) -> list[tuple[str, str]]:
    refs: list[tuple[str, str]] = []
    for uses_target in _ACTION_USES_RE.findall(workflow):
        if uses_target.startswith("./"):
            continue
        action, separator, ref = uses_target.rpartition("@")
        assert separator, f"External action is missing an explicit ref: {uses_target}"
        refs.append((action, ref))
    return refs


def _release_tool_install_args(workflow: str) -> dict[str, list[str]]:
    install_args: dict[str, list[str]] = {}
    for package, args in _CHOCO_INSTALL_LINE_RE.findall(workflow):
        package_name = package.lower()
        extra_release_tools = [
            tool
            for tool in _RELEASE_TOOL_PACKAGES
            if tool != package_name
            and re.search(rf"(?<![-\w]){re.escape(tool)}(?![-\w])", args, re.I)
        ]
        assert not extra_release_tools, (
            "Install release-critical Chocolatey packages in separate commands "
            f"so each package has its own version pin: {package} {args}"
        )
        if package_name in _RELEASE_TOOL_PACKAGES:
            install_args.setdefault(package_name, []).append(args)
    return install_args


def test_release_preflight_runs_transport_contract_tests():
    workflow = _workflow_source()

    setup_idx = workflow.index("Set up Python")
    pytest_idx = workflow.index("python -m pytest -q tests")
    package_idx = workflow.index("Development package smoke")
    packager_idx = workflow.index("uses: BigWigsMods/packager@")

    assert setup_idx < pytest_idx < package_idx < packager_idx
    assert "python-version: '3.13'" in workflow
    assert "tests/test_transport_contract.py" not in workflow


def test_release_workflow_pins_external_actions_to_commit_shas():
    workflow = _workflow_source()
    action_refs = _workflow_action_refs(workflow)

    assert Counter(action for action, _ in action_refs) == Counter(
        {
            "actions/checkout": 2,
            "actions/setup-python": 1,
            "BigWigsMods/packager": 1,
        }
    )
    for action, ref in action_refs:
        assert _SHA_REF_RE.fullmatch(ref), f"{action} must be pinned to a full commit SHA"


def test_check_workflow_runs_non_release_preflight_without_publishing():
    workflow = _read_repo_text(".github/workflows/check.yml")

    assert "push:" in workflow
    assert "pull_request:" in workflow
    assert "tags:" not in workflow
    assert "windows-latest" in workflow
    assert "contents: read" in workflow
    assert "contents: write" not in workflow
    assert "python-version: '3.13'" in workflow
    assert "python -m pytest -q tests" in workflow
    assert "choco install lua51 --version=5.1.5" in workflow
    assert "& $luac -p ApplicantScout.lua libs\\qrencode.lua" in workflow
    assert ".\\scripts\\package-addon.ps1" in workflow
    assert "BigWigsMods/packager" not in workflow
    assert "CF_API_KEY" not in workflow
    assert "WAGO_API_TOKEN" not in workflow
    assert "gh release" not in workflow


def test_check_workflow_pins_external_actions_to_commit_shas():
    workflow = _read_repo_text(".github/workflows/check.yml")
    action_refs = _workflow_action_refs(workflow)

    assert Counter(action for action, _ in action_refs) == Counter(
        {
            "actions/checkout": 1,
            "actions/setup-python": 1,
        }
    )
    for action, ref in action_refs:
        assert _SHA_REF_RE.fullmatch(ref), f"{action} must be pinned to a full commit SHA"


def test_check_workflow_pins_lua_build_tool_version():
    workflow = _read_repo_text(".github/workflows/check.yml")
    install_args = _release_tool_install_args(workflow)

    assert set(install_args) == set(_RELEASE_TOOL_PACKAGES)
    assert len(install_args["lua51"]) == 1
    assert re.search(
        r"(?i)(?:^|\s)--version(?:=|\s+)5\.1\.5(?:\s|$)",
        install_args["lua51"][0],
    )


def test_release_preflight_pins_lua_build_tool_version():
    workflow = _workflow_source()
    install_args = _release_tool_install_args(workflow)

    assert set(install_args) == set(_RELEASE_TOOL_PACKAGES)
    assert len(install_args["lua51"]) == 1
    assert re.search(
        r"(?i)(?:^|\s)--version(?:=|\s+)5\.1\.5(?:\s|$)",
        install_args["lua51"][0],
    )


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
        "CLAUDE.md",
    ):
        assert re.search(rf"(?m)^\s*-\s+{re.escape(ignored)}\s*$", pkgmeta)
    assert re.search(r'(?m)^\s*-\s+"?\*\.private\.md"?\s*$', pkgmeta)
    assert re.search(r'(?m)^\s*-\s+"?\*\.private/"?\s*$', pkgmeta)


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


def test_package_script_rejects_private_directories_and_legacy_claude_docs():
    package_script = _read_repo_text("scripts/package-addon.ps1")

    assert "(^|/)[^/]+\\.private(/|$)" in package_script
    assert "(^|/)CLAUDE\\.md$" in package_script


def test_readme_documents_current_wire_version_and_transient_qr_visibility():
    readme = _read_repo_text("README.md")

    assert "Wire payload: compact v6" in readme
    assert "Wire payload: compact v5" not in readme
    assert "stays visible during an\nactive capture session" not in readme
    assert "screenshot capture window" in readme


def test_runtime_comments_do_not_claim_qr_visible_for_full_session():
    source = _read_repo_text("ApplicantScout.lua")

    assert "always-visible during active session" not in source
    assert "short visibility lease" in source
