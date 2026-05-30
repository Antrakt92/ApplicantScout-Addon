from __future__ import annotations

from collections import Counter
import json
import pytest
import re
import shutil
import subprocess
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


def _job_block(workflow: str, job_name: str) -> str:
    match = re.search(
        rf"(?ms)^  {re.escape(job_name)}:\n(?P<body>.*?)(?=^  [A-Za-z0-9_-]+:\n|\Z)",
        workflow,
    )
    assert match is not None, f"Missing workflow job: {job_name}"
    return match.group(0)


def _step_block(container: str, step_name: str) -> str:
    match = re.search(
        rf"(?ms)^      - name: {re.escape(step_name)}\n(?P<body>.*?)(?=^      - name:|\Z)",
        container,
    )
    assert match is not None, f"Missing workflow step: {step_name}"
    return match.group(0)


def _assert_order(container: str, *needles: str) -> None:
    positions = [container.index(needle) for needle in needles]
    assert positions == sorted(positions), f"Workflow order is wrong for {needles}"


def _lua_print_help_command_lines(source: str) -> list[str]:
    match = re.search(
        r"(?ms)^local function PrintHelp\(\)\r?\n(?P<body>.*?)(?=^end\r?$)",
        source,
    )
    assert match is not None, "Missing ApplicantScout.lua::PrintHelp"
    lines = re.findall(r'print\("  (?P<line>/apscout[^"]+)"\)', match.group("body"))
    assert lines, "PrintHelp did not expose any /apscout command lines"
    return [line.rstrip() for line in lines]


def _markdown_section(markdown: str, heading: str) -> str:
    match = re.search(
        rf"(?ms)^##\s+{re.escape(heading)}\s*\r?\n(?P<body>.*?)(?=^##\s+|\Z)",
        markdown,
    )
    assert match is not None, f"Missing README section: {heading}"
    return match.group("body")


def _markdown_text_fence_lines(markdown: str, heading: str) -> list[str]:
    section = _markdown_section(markdown, heading)
    match = re.search(r"(?ms)```text\r?\n(?P<body>.*?)\r?\n```", section)
    assert match is not None, f"Missing text code fence in README section: {heading}"
    return [line.rstrip() for line in match.group("body").splitlines() if line.strip()]


def _assert_copy_contains(text: str, phrase: str) -> None:
    normalized_text = re.sub(r"\s+", " ", text)
    normalized_phrase = re.sub(r"\s+", " ", phrase)
    assert normalized_phrase in normalized_text


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


def _run_release_check_in(repo: Path, *args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [
            "powershell",
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            str(repo / "scripts" / "check-release-version.ps1"),
            *args,
        ],
        cwd=repo,
        check=False,
        text=True,
        capture_output=True,
    )


def _run_release_check(*args: str) -> subprocess.CompletedProcess[str]:
    return _run_release_check_in(REPO_ROOT, *args)


def _copy_release_check_fixture(tmp_path: Path) -> Path:
    repo = tmp_path / "repo"
    (repo / "scripts").mkdir(parents=True)
    for path in (
        "scripts/check-release-version.ps1",
        "ApplicantScout.toc",
        "CHANGELOG.md",
        "README.md",
    ):
        source = REPO_ROOT / path
        target = repo / path
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
    return repo


def _fake_gh_release_view(
    tmp_path: Path,
    *,
    release_json: dict[str, object] | None = None,
    stdout_text: str | None = None,
    exit_code: int = 0,
    expected_repo: str = "Antrakt92/ApplicantScout-Companion",
    expected_tag: str | None = None,
    expected_json: str = "tagName,isDraft,isPrerelease,assets",
    stderr: str = "",
) -> Path:
    script = tmp_path / "fake-gh.ps1"
    args_path = tmp_path / "fake-gh-args.txt"
    stdout = stdout_text if stdout_text is not None else json.dumps(release_json or {})
    script.write_text(
        "\n".join(
            [
                f"Set-Content -LiteralPath {str(args_path)!r} -Value ($args -join \"`n\") -Encoding UTF8",
                "if ($args.Count -ne 7 -or $args[0] -ne 'release' -or $args[1] -ne 'view') {",
                "    Write-Error 'unexpected gh invocation'",
                "    exit 2",
                "}",
                f"if ($args[3] -ne '--repo' -or $args[4] -ne {expected_repo!r}) {{",
                "    Write-Error 'unexpected gh repo'",
                "    exit 2",
                "}",
                f"if ($args[5] -ne '--json' -or $args[6] -ne {expected_json!r}) {{",
                "    Write-Error 'unexpected gh json fields'",
                "    exit 2",
                "}",
                (
                    f"if ($args[2] -ne {expected_tag!r}) {{ Write-Error 'unexpected gh tag'; exit 2 }}"
                    if expected_tag is not None
                    else ""
                ),
                f"if ({exit_code} -ne 0) {{",
                f"    [Console]::Error.WriteLine({stderr!r})",
                f"    exit {exit_code}",
                "}",
                f"Write-Output {stdout!r}",
                "exit 0",
            ]
        ),
        encoding="utf-8",
    )
    return script


def test_release_preflight_checks_paired_companion_ref_before_packaging():
    workflow = _workflow_source()
    preflight = _job_block(workflow, "preflight")
    release = _job_block(workflow, "release")

    assert "APPLICANT_SCOUT_VISUAL_BASELINE" not in workflow
    assert re.search(r"(?m)^    runs-on: windows-2022\s*$", preflight)
    assert re.search(r"(?m)^    permissions:\n      contents: read\s*$", preflight)
    assert re.search(r"(?m)^    needs: preflight\s*$", release)
    assert re.search(r"(?m)^    runs-on: ubuntu-latest\s*$", release)
    assert re.search(r"(?m)^    permissions:\n      contents: write\s*$", release)

    version_step = _step_block(preflight, "Check release version")
    companion_checkout = _step_block(preflight, "Checkout paired companion")
    tag_wait_step = _step_block(preflight, "Wait for paired companion tag")
    paired_metadata_step = _step_block(preflight, "Validate paired companion metadata")
    dependency_step = _step_block(preflight, "Install Python dependencies")
    contract_step = _step_block(preflight, "Check paired companion and addon contracts")
    package_step = _step_block(preflight, "Development package smoke")
    published_companion_step = _step_block(
        preflight, "Verify paired companion published release assets"
    )

    assert "id: version" in version_step
    assert "-PairedCompanionRefOutputPath $env:GITHUB_OUTPUT" in version_step
    assert "Antrakt92/ApplicantScout-Companion" in tag_wait_step
    assert "steps.version.outputs.companion_ref" in tag_wait_step
    assert 'git/ref/tags/$Ref' in tag_wait_step
    assert "$Deadline" in tag_wait_step
    assert "while ($true)" in tag_wait_step
    assert "repository: Antrakt92/ApplicantScout-Companion" in companion_checkout
    assert "ref: ${{ steps.version.outputs.companion_ref }}" in companion_checkout
    assert "path: ApplicantScout-Companion" in companion_checkout
    assert "working-directory: ApplicantScout-Addon" in paired_metadata_step
    assert "-PairedCompanionRoot ..\\ApplicantScout-Companion" in paired_metadata_step
    assert "working-directory: ApplicantScout-Companion" in dependency_step
    assert ".\\.venv\\Scripts\\python -m pip install -r constraints-release.txt" in dependency_step
    assert ".\\.venv\\Scripts\\python -m pip install -e '.[dev]' -c constraints-release.txt" in dependency_step
    assert "python -m pip install pytest" not in preflight
    assert "working-directory: ApplicantScout-Companion" in contract_step
    assert (
        ".\\scripts\\check.ps1 -AddonRoot ..\\ApplicantScout-Addon -VisualMode Smoke"
        in contract_step
    )
    assert "working-directory: ApplicantScout-Addon" in package_step
    assert ".\\scripts\\package-addon.ps1 -OutputDir" in package_step
    assert "working-directory: ApplicantScout-Addon" in published_companion_step
    assert "GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}" in published_companion_step
    assert "-RequirePublishedPairedCompanionAssets" in published_companion_step
    assert "-PublishedReleaseWaitSeconds 180" in published_companion_step

    _assert_order(
        preflight,
        "Check release version",
        "Wait for paired companion tag",
        "Checkout paired companion",
        "Validate paired companion metadata",
        "Install Python dependencies",
        "Check paired companion and addon contracts",
        "Development package smoke",
        "Verify paired companion published release assets",
    )
    assert "CF_API_KEY" not in preflight
    assert "WAGO_API_TOKEN" not in preflight
    assert "GITHUB_OAUTH" not in preflight
    assert "uses: BigWigsMods/packager@" not in preflight
    assert "uses: BigWigsMods/packager@" in release


def test_release_preflight_requires_tag_commit_reachable_from_origin_main():
    workflow = _workflow_source()
    preflight = _job_block(workflow, "preflight")
    gate = _step_block(preflight, "Verify release tag is reachable from origin/main")

    assert "working-directory: ApplicantScout-Addon" in gate
    assert "git fetch --no-tags --prune origin +refs/heads/main:refs/remotes/origin/main" in gate
    assert "git rev-parse HEAD" in gate
    assert "git rev-parse refs/remotes/origin/main" in gate
    assert "git merge-base --is-ancestor" in gate
    assert "$LASTEXITCODE" in gate
    assert "not reachable from origin/main" in gate
    assert "Could not verify release tag ancestry" in gate
    _assert_order(
        preflight,
        "Checkout addon",
        "Verify release tag is reachable from origin/main",
        "Check release version",
        "Wait for paired companion tag",
    )


def test_release_job_requires_tag_commit_reachable_from_origin_main():
    workflow = _workflow_source()
    release = _job_block(workflow, "release")
    gate = _step_block(release, "Verify release tag is reachable from origin/main")

    assert "git fetch --no-tags --prune origin +refs/heads/main:refs/remotes/origin/main" in gate
    assert "release_commit=$(git rev-parse HEAD)" in gate
    assert "main_commit=$(git rev-parse refs/remotes/origin/main)" in gate
    assert "git merge-base --is-ancestor" in gate
    assert "$status" in gate
    assert "not reachable from origin/main" in gate
    assert "Could not verify release tag ancestry" in gate
    _assert_order(
        release,
        "Checkout",
        "Verify release tag is reachable from origin/main",
        "Refuse existing release",
        "Package and release",
    )


def test_release_workflow_requires_published_companion_assets_before_packaging():
    workflow = _workflow_source()
    preflight = _job_block(workflow, "preflight")
    release = _job_block(workflow, "release")

    assert "RequirePublishedPairedCompanionAssets" in preflight
    assert "ApplicantScoutCompanionSetup-" not in release
    assert "gh release view" in release
    assert release.index("gh release view") < release.index("BigWigsMods/packager")


def test_release_job_refuses_existing_release_without_failing_open_on_gh_errors():
    workflow = _workflow_source()
    release = _job_block(workflow, "release")
    guard = _step_block(release, "Refuse existing release")

    assert "--json tagName,isDraft,isPrerelease" in guard
    assert "$status" in guard
    assert "not found" in guard
    assert "Could not determine whether release" in guard
    assert guard.index("gh release view") < release.index("BigWigsMods/packager")


def test_release_job_keeps_marketplace_publish_checkout_at_repo_root():
    workflow = _workflow_source()
    release = _job_block(workflow, "release")
    checkout = _step_block(release, "Checkout")

    assert "path:" not in checkout
    assert "uses: BigWigsMods/packager@" in release


def test_release_version_script_outputs_paired_companion_ref(tmp_path: Path):
    output_path = tmp_path / "github-output.txt"

    result = subprocess.run(
        [
            "powershell",
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            str(REPO_ROOT / "scripts" / "check-release-version.ps1"),
            "-Tag",
            "v0.4.3",
            "-PairedCompanionRefOutputPath",
            str(output_path),
        ],
        cwd=REPO_ROOT,
        text=True,
        capture_output=True,
        check=False,
    )

    assert result.returncode == 0, result.stdout + result.stderr
    assert output_path.read_text(encoding="utf-8") == "companion_ref=v0.8.0\n"


@pytest.mark.parametrize(
    "bad_install_copy",
    [
        "https://github.com/Antrakt92/ApplicantScout-Addon/releases/download/v0.4.3/ApplicantScout-v0.4.3.zip",
        "https://github.com/Antrakt92/ApplicantScout-Companion/releases/download/v0.8.0/ApplicantScoutCompanionSetup-0.8.0.exe",
        "https://github.com/Antrakt92/ApplicantScout-Addon/releases",
        "https://github.com/Antrakt92/ApplicantScout-Companion/releases",
        "https://github.com/Antrakt92/ApplicantScout-Addon/archive/refs/tags/v0.4.3.zip",
        "https://github.com/Antrakt92/ApplicantScout-Addon/zipball/v0.4.3",
        "https://github.com/Antrakt92/ApplicantScout-Companion/tarball/v0.8.0",
        "ApplicantScout WoW addon `0.4.3`",
        "ApplicantScout Companion `0.8.0`",
        "Install `ApplicantScout-0.4.3.zip` from GitHub.",
        "Install `ApplicantScoutCompanionSetup-0.8.0.exe` from GitHub.",
    ],
)
def test_release_version_script_rejects_pinned_readme_install_links(
    tmp_path: Path,
    bad_install_copy: str,
):
    repo = _copy_release_check_fixture(tmp_path)
    readme_path = repo / "README.md"
    readme_path.write_text(
        readme_path.read_text(encoding="utf-8") + f"\n{bad_install_copy}\n",
        encoding="utf-8",
    )

    result = _run_release_check_in(repo, "-Tag", "v0.4.3")

    assert result.returncode != 0
    assert "use releases/latest" in (result.stdout + result.stderr)


def test_release_version_script_validates_paired_companion_minimum_addon(
    tmp_path: Path,
):
    companion = tmp_path / "ApplicantScout-Companion"
    companion.mkdir()
    (companion / "RELEASE_NOTES.md").write_text(
        "\n".join(
            [
                "# ApplicantScout Companion Release Notes",
                "",
                "## 0.8.0 - 28-May-2026",
                "",
                "### Release Assets",
                "",
                "- Requires the ApplicantScout WoW addon `0.4.3`.",
                "",
            ]
        ),
        encoding="utf-8",
    )

    result = subprocess.run(
        [
            "powershell",
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            str(REPO_ROOT / "scripts" / "check-release-version.ps1"),
            "-Tag",
            "v0.4.3",
            "-PairedCompanionRoot",
            str(companion),
        ],
        cwd=REPO_ROOT,
        text=True,
        capture_output=True,
        check=False,
    )

    assert result.returncode == 0, result.stdout + result.stderr


def test_release_version_script_rejects_companion_requiring_newer_addon(
    tmp_path: Path,
):
    companion = tmp_path / "ApplicantScout-Companion"
    companion.mkdir()
    (companion / "RELEASE_NOTES.md").write_text(
        "\n".join(
            [
                "# ApplicantScout Companion Release Notes",
                "",
                "## 0.8.0 - 28-May-2026",
                "",
                "### Release Assets",
                "",
                "- Requires the ApplicantScout WoW addon `0.4.4`.",
                "",
            ]
        ),
        encoding="utf-8",
    )

    result = subprocess.run(
        [
            "powershell",
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            str(REPO_ROOT / "scripts" / "check-release-version.ps1"),
            "-Tag",
            "v0.4.3",
            "-PairedCompanionRoot",
            str(companion),
        ],
        cwd=REPO_ROOT,
        text=True,
        capture_output=True,
        check=False,
    )

    assert result.returncode != 0
    output = result.stdout + result.stderr
    assert "requires addon 0.4.4" in output
    assert "current addon tag is 0.4.3" in output


def test_release_version_script_does_not_invoke_companion_release_script():
    script = _read_repo_text("scripts/check-release-version.ps1")

    assert "ApplicantScout-Companion\\scripts\\check-release-version.ps1" not in script
    assert "ApplicantScout-Companion/scripts/check-release-version.ps1" not in script


def test_release_version_check_accepts_published_paired_companion_assets(
    tmp_path: Path,
):
    gh = _fake_gh_release_view(
        tmp_path,
        expected_tag="v0.8.0",
        release_json={
            "tagName": "v0.8.0",
            "isDraft": False,
            "isPrerelease": False,
            "assets": [
                {"name": "ApplicantScoutCompanionSetup-0.8.0.exe"},
                {"name": "ApplicantScoutCompanionSetup-0.8.0.exe.sha256"},
                {"name": "ApplicantScoutCompanion-0.8.0-portable.zip"},
            ],
        },
    )

    result = _run_release_check(
        "-Tag",
        "v0.4.3",
        "-RequirePublishedPairedCompanionAssets",
        "-GitHubCliPath",
        str(gh),
        "-PublishedReleaseWaitSeconds",
        "0",
    )

    assert result.returncode == 0, result.stdout + result.stderr


def test_release_version_check_rejects_missing_paired_companion_checksum(
    tmp_path: Path,
):
    gh = _fake_gh_release_view(
        tmp_path,
        expected_tag="v0.8.0",
        release_json={
            "tagName": "v0.8.0",
            "isDraft": False,
            "isPrerelease": False,
            "assets": [
                {"name": "ApplicantScoutCompanionSetup-0.8.0.exe"},
                {"name": "ApplicantScoutCompanion-0.8.0-portable.zip"},
            ],
        },
    )

    result = _run_release_check(
        "-Tag",
        "v0.4.3",
        "-RequirePublishedPairedCompanionAssets",
        "-GitHubCliPath",
        str(gh),
        "-PublishedReleaseWaitSeconds",
        "0",
    )

    assert result.returncode != 0
    output = re.sub(r"\s+", "", result.stdout + result.stderr)
    assert "missingasset:ApplicantScoutCompanionSetup-0.8.0.exe.sha256" in output


def test_release_version_check_rejects_draft_paired_companion_release(
    tmp_path: Path,
):
    gh = _fake_gh_release_view(
        tmp_path,
        expected_tag="v0.8.0",
        release_json={
            "tagName": "v0.8.0",
            "isDraft": True,
            "isPrerelease": False,
            "assets": [
                {"name": "ApplicantScoutCompanionSetup-0.8.0.exe"},
                {"name": "ApplicantScoutCompanionSetup-0.8.0.exe.sha256"},
                {"name": "ApplicantScoutCompanion-0.8.0-portable.zip"},
            ],
        },
    )

    result = _run_release_check(
        "-Tag",
        "v0.4.3",
        "-RequirePublishedPairedCompanionAssets",
        "-GitHubCliPath",
        str(gh),
        "-PublishedReleaseWaitSeconds",
        "0",
    )

    assert result.returncode != 0
    assert "is still draft" in (result.stdout + result.stderr)


def test_release_version_check_reports_paired_companion_gh_failure(tmp_path: Path):
    gh = _fake_gh_release_view(
        tmp_path,
        exit_code=7,
        expected_tag="v0.8.0",
        stderr="network failed",
    )

    result = _run_release_check(
        "-Tag",
        "v0.4.3",
        "-RequirePublishedPairedCompanionAssets",
        "-GitHubCliPath",
        str(gh),
        "-PublishedReleaseWaitSeconds",
        "0",
    )

    assert result.returncode != 0
    output = result.stdout + result.stderr
    assert "gh release view failed for Antrakt92/ApplicantScout-Companion" in output
    assert "network failed" in output


def test_release_version_check_rejects_malformed_paired_companion_release_json(
    tmp_path: Path,
):
    gh = _fake_gh_release_view(
        tmp_path,
        expected_tag="v0.8.0",
        stdout_text="{bad json",
    )

    result = _run_release_check(
        "-Tag",
        "v0.4.3",
        "-RequirePublishedPairedCompanionAssets",
        "-GitHubCliPath",
        str(gh),
        "-PublishedReleaseWaitSeconds",
        "0",
    )

    assert result.returncode != 0
    assert "malformed JSON" in (result.stdout + result.stderr)


def test_release_preflight_runs_python_through_companion_constraints():
    workflow = _workflow_source()

    assert "python-version: '3.13'" in workflow
    assert "constraints-release.txt" in workflow
    assert "python -m pip install pytest" not in workflow


def test_release_workflow_pins_external_actions_to_commit_shas():
    workflow = _workflow_source()
    action_refs = _workflow_action_refs(workflow)

    assert Counter(action for action, _ in action_refs) == Counter(
        {
            "actions/checkout": 3,
            "actions/setup-python": 1,
            "BigWigsMods/packager": 1,
        }
    )
    for action, ref in action_refs:
        assert _SHA_REF_RE.fullmatch(ref), f"{action} must be pinned to a full commit SHA"


def test_check_workflow_runs_non_release_preflight_without_publishing():
    workflow = _read_repo_text(".github/workflows/check.yml")
    job = _job_block(workflow, "check")

    assert "push:" in workflow
    assert "pull_request:" in workflow
    assert "tags:" not in workflow
    assert re.search(r"(?m)^    runs-on: windows-2022\s*$", job)
    assert "contents: read" in workflow
    assert "contents: write" not in workflow
    assert "APPLICANT_SCOUT_VISUAL_BASELINE" not in workflow
    assert "python-version: '3.13'" in workflow
    assert "repository: Antrakt92/ApplicantScout-Companion" in workflow
    assert "path: ApplicantScout-Addon" in workflow
    assert "path: ApplicantScout-Companion" in workflow
    assert "python -m pip install pytest" not in workflow
    assert ".\\.venv\\Scripts\\python -m pip install -r constraints-release.txt" in workflow
    assert ".\\.venv\\Scripts\\python -m pip install -e '.[dev]' -c constraints-release.txt" in workflow
    assert "choco install lua51 --version=5.1.5" in workflow
    assert (
        ".\\scripts\\check.ps1 -AddonRoot ..\\ApplicantScout-Addon -VisualMode Smoke"
        in workflow
    )
    assert ".\\scripts\\package-addon.ps1 -OutputDir" in workflow
    _assert_order(
        job,
        "Checkout addon",
        "Checkout companion",
        "Install Python dependencies",
        "Check companion and addon contracts",
        "Development package smoke",
    )
    assert "BigWigsMods/packager" not in workflow
    assert "CF_API_KEY" not in workflow
    assert "WAGO_API_TOKEN" not in workflow
    assert "gh release" not in workflow


def test_check_workflow_pins_external_actions_to_commit_shas():
    workflow = _read_repo_text(".github/workflows/check.yml")
    action_refs = _workflow_action_refs(workflow)

    assert Counter(action for action, _ in action_refs) == Counter(
        {
            "actions/checkout": 2,
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


def test_toc_orders_optional_key_providers_before_applicantscout():
    toc = _read_repo_text("ApplicantScout.toc")

    optional_deps_line = next(
        line for line in toc.splitlines() if line.startswith("## OptionalDeps:")
    )

    assert "RaiderIO" in optional_deps_line
    assert "LibKeystone" in optional_deps_line
    assert "DBM-Core" in optional_deps_line
    assert "BigWigs" in optional_deps_line


def test_package_script_rejects_private_directories_and_legacy_claude_docs():
    package_script = _read_repo_text("scripts/package-addon.ps1")

    assert "(^|/)[^/]+\\.private(/|$)" in package_script
    assert "(^|/)CLAUDE\\.md$" in package_script


def test_readme_documents_current_wire_version_and_transient_qr_visibility():
    readme = _read_repo_text("README.md")

    assert "Wire payload: compact v8" in readme
    assert "Wire payload: compact v5" not in readme
    assert "stays visible during an\nactive capture session" not in readme
    assert "screenshot capture window" in readme


def test_runtime_comments_do_not_claim_qr_visible_for_full_session():
    source = _read_repo_text("ApplicantScout.lua")

    assert "always-visible during active session" not in source
    assert "short visibility lease" in source


def test_readme_discloses_companion_local_data_and_checksum_limits():
    readme = _read_repo_text("README.md")

    _assert_copy_contains(readme, "_retail_\\Interface\\AddOns\\RaiderIO\\db")
    _assert_copy_contains(readme, "%LOCALAPPDATA%\\applicant-scout\\cache\\raiderio-local")
    _assert_copy_contains(readme, ".sha256")
    _assert_copy_contains(readme, "file integrity, not publisher identity")


def test_readme_documents_support_output_redaction():
    readme = _read_repo_text("README.md")

    for sensitive_surface in (
        "/apscout status",
        "/apscout taintcheck",
        "companion logs",
        "QR screenshots",
        "manual decode output",
        "config.env",
        "token.json",
        "character-cache.json",
    ):
        _assert_copy_contains(readme, sensitive_surface)

    for private_detail in (
        "WCL Client ID/Secret",
        "OAuth access token",
        "character names",
        "realm names",
        "listing titles/comments",
        "screenshots folder paths",
    ):
        _assert_copy_contains(readme, private_detail)


def test_readme_documents_residual_qr_screenshot_cleanup_risk():
    readme = _read_repo_text("README.md")

    for phrase in (
        "QR screenshots may remain",
        "companion is absent, interrupted",
        "synced/shared before cleanup",
    ):
        _assert_copy_contains(readme, phrase)


def test_readme_slash_command_blocks_match_lua_help_and_companion_readme(
    pytestconfig,
):
    expected_lines = _lua_print_help_command_lines(_read_repo_text("ApplicantScout.lua"))
    assert len(expected_lines) == 13
    assert "/apscout toggle         flip enabled state" in expected_lines
    assert "/apscout taintcheck     probe C_LFGList field secret-tagging" in expected_lines

    assert _markdown_text_fence_lines(
        _read_repo_text("README.md"),
        "Handy Slash Commands",
    ) == expected_lines

    companion_root = pytestconfig.getoption("--companion-root")
    if not companion_root:
        pytest.skip("--companion-root is required for cross-repo README sync")
    companion_readme = Path(companion_root) / "README.md"
    assert companion_readme.is_file(), f"Missing paired companion README: {companion_readme}"
    assert _markdown_text_fence_lines(
        companion_readme.read_text(encoding="utf-8"),
        "In-Game Commands",
    ) == expected_lines
