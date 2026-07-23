from __future__ import annotations

from collections import Counter
import json
import pytest
import re
import shutil
import subprocess
from pathlib import Path

from scripts.check_addon_archive import (
    FORBIDDEN_NAMES,
    FORBIDDEN_PARTS,
    REQUIRED_ENTRIES,
)


REPO_ROOT = Path(__file__).resolve().parents[1]
_ACTION_USES_RE = re.compile(r"(?m)^\s*uses:\s*([^\s#]+)\s*(?:#.*)?$")
_SHA_REF_RE = re.compile(r"^[0-9a-f]{40}$", re.I)
_CHOCO_INSTALL_LINE_RE = re.compile(
    r"(?im)^\s*(?:run:\s*)?choco\s+install\s+([A-Za-z0-9_.-]+)\b([^\r\n]*)"
)
_RELEASE_TOOL_PACKAGES = {
    "lua51": "5.1.5",
}
_SHARED_RELEASE_POLICY_FUNCTIONS = (
    "Assert-PublicInstallLinksUseLatest",
    "Compare-SemVer",
)
_SHARED_RELEASE_POLICY_ARRAYS = (
    "ProtectedCompanionAssetPatterns",
)


def _current_addon_version() -> str:
    toc = (REPO_ROOT / "ApplicantScout.toc").read_text(encoding="utf-8")
    match = re.search(r"(?m)^##\s+Version:\s*(\d+\.\d+\.\d+)\s*$", toc)
    assert match is not None, "ApplicantScout.toc is missing ## Version"
    return match.group(1)


def _current_paired_companion_version() -> str:
    changelog = (REPO_ROOT / "CHANGELOG.md").read_text(encoding="utf-8")
    top = re.search(
        r"(?ms)^##\s+\d+\.\d+\.\d+\s+-.*?(?=^##\s+\d+\.\d+\.\d+\s+-|\Z)",
        changelog,
    )
    assert top is not None, "CHANGELOG.md is missing a top versioned entry"
    versions = sorted(
        set(
            re.findall(
                r"(?i)(?:ApplicantScout\s+)?Companion\s+`?(\d+\.\d+\.\d+)`?",
                top.group(0),
            )
        )
    )
    assert len(versions) == 1, f"Expected one paired companion version, got {versions}"
    return versions[0]


def _next_patch_version(version: str) -> str:
    major, minor, patch = (int(part) for part in version.split("."))
    return f"{major}.{minor}.{patch + 1}"


def _previous_patch_version(version: str) -> str:
    major, minor, patch = (int(part) for part in version.split("."))
    if patch > 0:
        return f"{major}.{minor}.{patch - 1}"
    if minor > 0:
        return f"{major}.{minor - 1}.0"
    if major > 0:
        return f"{major - 1}.0.0"
    raise AssertionError("Cannot derive a prior stale version before 0.0.0")


CURRENT_ADDON_VERSION = _current_addon_version()
CURRENT_ADDON_TAG = f"v{CURRENT_ADDON_VERSION}"
CURRENT_COMPANION_VERSION = _current_paired_companion_version()
CURRENT_COMPANION_TAG = f"v{CURRENT_COMPANION_VERSION}"
CURRENT_CHECKOUT_COMMIT = subprocess.run(
    ["git", "rev-parse", "HEAD"],
    cwd=REPO_ROOT,
    check=True,
    capture_output=True,
    text=True,
).stdout.strip()
FAKE_COMPANION_COMMIT = "c" * 40


def _valid_paired_release_fixture() -> tuple[dict[str, object], dict[str, object]]:
    payload_names = [
        f"ApplicantScoutCompanionSetup-{CURRENT_COMPANION_VERSION}.exe",
        f"ApplicantScoutCompanionSetup-{CURRENT_COMPANION_VERSION}.exe.sha256",
        f"ApplicantScoutCompanion-{CURRENT_COMPANION_VERSION}-portable.zip",
    ]
    files = [
        {"name": name, "size": index + 10, "sha256": f"{index + 1:064x}"}
        for index, name in enumerate(payload_names)
    ]
    manifest_name = (
        f"ApplicantScoutCompanion-{CURRENT_COMPANION_VERSION}-release-manifest.json"
    )
    release = {
        "tagName": CURRENT_COMPANION_TAG,
        "isDraft": False,
        "isPrerelease": False,
        "isImmutable": True,
        "assets": [
            {
                "name": file["name"],
                "size": file["size"],
                "digest": f"sha256:{file['sha256']}",
                "apiUrl": (
                    "https://api.github.com/repos/Antrakt92/"
                    f"ApplicantScout-Companion/releases/assets/{index + 1}"
                ),
            }
            for index, file in enumerate(files)
        ]
        + [
            {
                "name": manifest_name,
                "size": 100,
                "digest": "sha256:" + "f" * 64,
                "apiUrl": (
                    "https://api.github.com/repos/Antrakt92/"
                    "ApplicantScout-Companion/releases/assets/99"
                ),
            }
        ],
    }
    manifest = {
        "schemaVersion": 2,
        "repository": "Antrakt92/ApplicantScout-Companion",
        "purpose": "Release",
        "tag": CURRENT_COMPANION_TAG,
        "commit": FAKE_COMPANION_COMMIT,
        "pairedAddonTag": CURRENT_ADDON_TAG,
        "pairedAddonCommit": CURRENT_CHECKOUT_COMMIT,
        "workflowRunId": "1",
        "workflowRunAttempt": 1,
        "files": files,
        "portableEntries": [],
        "releaseCopy": {},
    }
    return release, manifest


def _workflow_source() -> str:
    return (REPO_ROOT / ".github" / "workflows" / "release.yml").read_text(
        encoding="utf-8"
    )


def _recovery_workflow_source() -> str:
    return (
        REPO_ROOT / ".github" / "workflows" / "recover-preupload-release.yml"
    ).read_text(encoding="utf-8")


def _workflow_concurrency_contract(workflow: str) -> tuple[str, str, str]:
    match = re.search(
        r"(?m)^concurrency:\n"
        r"  group: (?P<group>[^\r\n]+)\n"
        r"  queue: (?P<queue>[^\r\n]+)\n"
        r"  cancel-in-progress: (?P<cancel>[^\r\n]+)\s*$",
        workflow,
    )
    assert match is not None, "Missing exact workflow concurrency contract"
    return match.group("group"), match.group("queue"), match.group("cancel")


def _read_repo_text(path: str) -> str:
    return (REPO_ROOT / path).read_text(encoding="utf-8")


def _powershell_function_block(source: str, name: str) -> str:
    match = re.search(
        rf"(?ms)^function\s+{re.escape(name)}\s*\{{.*?^\}}",
        source,
    )
    assert match is not None, f"Missing PowerShell function: {name}"
    return match.group(0).strip()


def _powershell_array_block(source: str, name: str) -> str:
    match = re.search(
        rf"(?ms)^\s*\${re.escape(name)}\s*=\s*@\(.*?^\s*\)",
        source,
    )
    assert match is not None, f"Missing PowerShell array: ${name}"
    assignment = match.group(0)
    return "\n".join(
        line.strip() for line in assignment[assignment.index("@(") :].splitlines()
    )


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


def _help_command_roots(lines: list[str]) -> set[str]:
    roots = {line.split()[1] for line in lines}
    if any(line.startswith("/apscout on | off") for line in lines):
        roots.add("off")
    return roots


def _handler_command_roots(source: str) -> set[str]:
    match = re.search(
        r"(?ms)^SlashCmdList\.APSCOUT = function\(msg\)\r?\n(?P<body>.*?)(?=^end\r?$)",
        source,
    )
    assert match is not None, "Missing SlashCmdList.APSCOUT handler"
    commands = re.findall(
        r'(?:msg|command)\s*==\s*"(?P<command>[^"]+)"',
        match.group("body"),
    )
    return {command.split()[0] for command in commands}


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
    expected_json: str = "tagName,isDraft,isPrerelease,isImmutable,assets",
    manifest_json: dict[str, object] | None = None,
    companion_commit: str = FAKE_COMPANION_COMMIT,
    addon_commit: str = CURRENT_CHECKOUT_COMMIT,
    default_immutable: bool = True,
    stderr: str = "",
) -> Path:
    script = tmp_path / "fake-gh.ps1"
    args_path = tmp_path / "fake-gh-args.txt"
    normalized_release = dict(release_json or {})
    if default_immutable:
        normalized_release.setdefault("isImmutable", True)
    stdout = stdout_text if stdout_text is not None else json.dumps(normalized_release)
    manifest_stdout = json.dumps(manifest_json) if manifest_json is not None else ""
    script.write_text(
        "\n".join(
            [
                f"Set-Content -LiteralPath {str(args_path)!r} -Value ($args -join \"`n\") -Encoding UTF8",
                "if ($args.Count -eq 4 -and $args[0] -eq 'api' -and $args[1] -eq '-H') {",
                "    if ($args[2] -ne 'Accept: application/octet-stream' -or $args[3] -notmatch '/releases/assets/[0-9]+$') { Write-Error 'unexpected manifest download'; exit 2 }",
                f"    if (-not {manifest_stdout!r}) {{ Write-Error 'manifest was not configured'; exit 2 }}",
                f"    Write-Output {manifest_stdout!r}",
                "    exit 0",
                "}",
                "if ($args.Count -eq 2 -and $args[0] -eq 'api' -and $args[1] -match '/git/ref/tags/') {",
                "    $repo = if ($args[1] -match 'ApplicantScout-Companion') { 'companion' } elseif ($args[1] -match 'ApplicantScout-Addon') { 'addon' } else { 'wrong' }",
                "    if ($repo -eq 'wrong') { Write-Error 'unexpected tag repo'; exit 2 }",
                f"    $sha = if ($repo -eq 'companion') {{ {companion_commit!r} }} else {{ {addon_commit!r} }}",
                "    $tag = ($args[1] -split '/git/ref/tags/', 2)[1]",
                "    Write-Output (@{ ref = \"refs/tags/$tag\"; object = @{ type = 'commit'; sha = $sha } } | ConvertTo-Json -Compress)",
                "    exit 0",
                "}",
                "if ($args.Count -ne 7 -or $args[0] -ne 'release' -or $args[1] -ne 'view') { Write-Error 'unexpected gh invocation'; exit 2 }",
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
    assert re.search(
        r"(?m)^    needs: \[preflight, marketplace-package\]\s*$",
        release,
    )
    assert re.search(r"(?m)^    runs-on: ubuntu-latest\s*$", release)
    assert re.search(
        r"(?m)^    permissions:\n      actions: read\n      contents: write\s*$",
        release,
    )

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
    assert "uses: BigWigsMods/packager@" not in release


def test_release_requires_verified_exact_tag_marketplace_package_before_upload():
    workflow = _workflow_source()
    marketplace = _job_block(workflow, "marketplace-package")
    release = _job_block(workflow, "release")
    marketplace_release = _job_block(workflow, "marketplace-release")

    assert "needs: [preflight, marketplace-package]" in release
    assert re.search(r"(?m)^    permissions:\n      contents: read\s*$", marketplace)
    assert "commit: ${{ steps.marketplace-identity.outputs.commit }}" in marketplace
    checkout = _step_block(
        marketplace,
        "Checkout addon for exact-tag marketplace package",
    )
    identity = _step_block(marketplace, "Record exact marketplace package commit")
    dry_run = _step_block(
        marketplace,
        "Build exact-tag marketplace package without uploading",
    )
    archive_check = _step_block(
        marketplace,
        "Validate exact-tag marketplace archive contract",
    )
    metadata = _step_block(marketplace, "Create exact-tag GitHub release metadata")
    artifact_upload = _step_block(
        marketplace, "Upload verified exact-tag release bundle"
    )
    artifact_download = _step_block(
        release, "Download verified exact-tag release bundle"
    )
    github_publish = _step_block(release, "Publish verified immutable GitHub release")
    upload = _step_block(marketplace_release, "Publish exact tag to marketplaces")
    release_identity = _step_block(
        release,
        "Verify release tag is reachable from origin/main",
    )

    assert "fetch-depth: 0" in checkout
    assert "git rev-parse HEAD" in identity
    assert '"$commit" != "$GITHUB_SHA"' in identity
    assert 'echo "commit=$commit" >> "$GITHUB_OUTPUT"' in identity
    assert (
        "uses: BigWigsMods/packager@6d50adb6e8517eefef63f4afb16a6518166a6b28"
        in dry_run
    )
    assert "args: -d" in dry_run
    assert "pandoc: false" in dry_run
    assert "python3 scripts/check_addon_archive.py --release-dir .release" in (
        archive_check
    )
    assert "secrets." not in marketplace
    assert "CF_API_KEY" not in marketplace
    assert "WAGO_API_TOKEN" not in marketplace
    assert 'marketplace_commit="${{ needs.marketplace-package.outputs.commit }}"' in (
        release_identity
    )
    assert '"$release_commit" != "$marketplace_commit"' in release_identity
    assert "scripts/create_release_metadata.py" in metadata
    assert "actions/upload-artifact@" in artifact_upload
    assert "include-hidden-files: true" in artifact_upload
    assert "actions/download-artifact@" in artifact_download
    assert "gh release create" in github_publish
    assert "--draft" in github_publish
    assert "gh release edit" in github_publish
    assert "immutable" in github_publish
    assert "CF_API_KEY: ${{ secrets.CF_API_KEY }}" in upload
    assert "WAGO_API_TOKEN: ${{ secrets.WAGO_API_TOKEN }}" in upload
    assert "GITHUB_OAUTH" not in marketplace_release
    assert "contents: read" in marketplace_release
    assert "pandoc: false" in upload
    _assert_order(
        marketplace,
        "Record exact marketplace package commit",
        "Build exact-tag marketplace package without uploading",
        "Validate exact-tag marketplace archive contract",
        "Create exact-tag GitHub release metadata",
        "Upload verified exact-tag release bundle",
    )
    _assert_order(
        release,
        "Verify release tag is reachable from origin/main",
        "Refuse existing release",
        "Revalidate paired immutable release identity",
        "Require intended marketplace credentials before publication",
        "Verify immutable release policy",
        "Download verified exact-tag release bundle",
        "Publish verified immutable GitHub release",
    )


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
        "Revalidate paired immutable release identity",
        "Require intended marketplace credentials before publication",
        "Verify immutable release policy",
        "Download verified exact-tag release bundle",
        "Publish verified immutable GitHub release",
    )


def test_release_workflow_requires_published_companion_assets_before_packaging():
    workflow = _workflow_source()
    preflight = _job_block(workflow, "preflight")
    release = _job_block(workflow, "release")
    revalidation = _step_block(
        release, "Revalidate paired immutable release identity"
    )

    assert "RequirePublishedPairedCompanionAssets" in preflight
    assert "ApplicantScoutCompanionSetup-" not in release
    assert "-RequirePublishedPairedCompanionAssets" in revalidation
    assert "-PublishedReleaseWaitSeconds 0" in revalidation
    assert "GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}" in revalidation
    assert release.index("Revalidate paired immutable release identity") < release.index(
        "Publish verified immutable GitHub release"
    )


def test_release_job_refuses_existing_release_without_failing_open_on_gh_errors():
    workflow = _workflow_source()
    release = _job_block(workflow, "release")
    guard = _step_block(release, "Refuse existing release")

    assert "--json tagName,isDraft,isPrerelease" in guard
    assert "$status" in guard
    assert "not found" in guard
    assert "Could not determine whether release" in guard
    assert guard.index("gh release view") < release.index(
        "Publish verified immutable GitHub release"
    )


def test_release_rejects_reruns_before_checkout_and_serializes_tags():
    workflow = _workflow_source()
    preflight = _job_block(workflow, "preflight")
    release = _job_block(workflow, "release")
    marketplace_release = _job_block(workflow, "marketplace-release")
    rerun_guard = _step_block(preflight, "Reject ambiguous release rerun")
    writer_rerun_guard = _step_block(
        release, "Reject ambiguous GitHub publication rerun"
    )
    marketplace_rerun_guard = _step_block(
        marketplace_release, "Reject ambiguous marketplace rerun"
    )

    assert "group: applicantscout-addon-release" in workflow
    assert "cancel-in-progress: false" in workflow
    assert "github.run_attempt != 1" in rerun_guard
    assert "github.run_attempt != 1" in writer_rerun_guard
    assert "github.run_attempt != 1" in marketplace_rerun_guard
    _assert_order(preflight, "Reject ambiguous release rerun", "Checkout addon")
    _assert_order(
        release, "Reject ambiguous GitHub publication rerun", "Checkout"
    )
    _assert_order(
        marketplace_release,
        "Reject ambiguous marketplace rerun",
        "Checkout exact immutable release tag",
    )


def test_release_and_recovery_share_max_non_cancelling_concurrency_queue():
    expected = ("applicantscout-addon-release", "max", "false")

    assert _workflow_concurrency_contract(_workflow_source()) == expected
    assert _workflow_concurrency_contract(_recovery_workflow_source()) == expected


def test_release_and_recovery_publish_only_generated_exact_version_notes():
    cases = (
        (_workflow_source(), "release", "$env:GITHUB_REF_NAME"),
        (_recovery_workflow_source(), "recover-github-release", "$env:RELEASE_TAG"),
    )

    for workflow, job_name, tag_expression in cases:
        publish = _step_block(
            _job_block(workflow, job_name),
            "Publish verified immutable GitHub release",
        )
        assert "$ReleaseNotesPath = Join-Path $env:RUNNER_TEMP" in publish
        assert "python3 scripts/create_release_notes.py" in publish
        assert "--changelog CHANGELOG.md" in publish
        assert "--output $ReleaseNotesPath" in publish
        assert f"--tag {tag_expression}" in publish
        assert "--notes-file $ReleaseNotesPath" in publish
        assert "--notes-file CHANGELOG.md" not in publish
        assert "--json tagName,name,body,isDraft,isPrerelease,assets" in publish
        assert f"[string]$Draft.name -cne {tag_expression}" in publish
        assert "$DraftBody -cne $ExpectedReleaseBody" in publish
        assert f"[string]$Published.name -ceq {tag_expression}" in publish
        assert "$PublishedBody -ceq $ExpectedReleaseBody" in publish
        publication = publish[publish.index("gh release edit") :]
        assert f"--title {tag_expression}" in publication
        assert "--notes-file $ReleaseNotesPath" in publication
        assert publish.index("scripts/create_release_notes.py") < publish.index(
            "gh release create"
        )


def test_preupload_recovery_is_manual_exact_run_only_and_serialized():
    workflow = _recovery_workflow_source()
    recovery = _job_block(workflow, "recover-github-release")
    checkout = _step_block(recovery, "Checkout exact release tag")

    assert re.search(r"(?m)^  workflow_dispatch:\s*$", workflow)
    assert re.search(r"(?m)^      tag:\s*$", workflow)
    assert re.search(r"(?m)^      source_run_id:\s*$", workflow)
    assert re.search(r"(?m)^      confirm_preupload_timeout:\s*$", workflow)
    assert "  push:" not in workflow
    assert "  pull_request:" not in workflow
    assert "group: applicantscout-addon-release" in workflow
    assert "cancel-in-progress: false" in workflow
    assert "if: ${{ inputs.confirm_preupload_timeout }}" in recovery
    assert "ref: ${{ inputs.tag }}" in checkout
    assert "fetch-depth: 0" in checkout
    assert "persist-credentials: false" in checkout
    assert re.search(
        r"(?m)^    permissions:\n      actions: read\n      contents: write\s*$",
        recovery,
    )


def test_preupload_recovery_proves_source_failed_before_all_writers():
    workflow = _recovery_workflow_source()
    recovery = _job_block(workflow, "recover-github-release")
    identity = _step_block(recovery, "Verify pre-upload timeout recovery identity")

    assert "Package and release" in identity
    assert "[string]$Run.path -cne '.github/workflows/release.yml'" in identity
    assert "[string]$Run.event -cne 'push'" in identity
    assert "[string]$Run.head_branch -cne $env:RELEASE_TAG" in identity
    assert "[string]$Run.head_sha -cne $ReleaseCommit" in identity
    assert "git merge-base --is-ancestor" in identity
    assert "attempts/1/jobs?per_page=100" in identity
    assert "Verify paired companion published release assets" in identity
    assert "[string]$Package.conclusion -cne 'success'" in identity
    for step_name in (
        "Checkout addon",
        "Verify release tag is reachable from origin/main",
        "Check release version",
        "Wait for paired companion tag",
        "Checkout paired companion",
        "Validate paired companion metadata",
        "Set up Python",
        "Install Python dependencies",
        "Install Lua 5.1",
        "Install pinned LuaLS",
        "Check addon Lua diagnostics",
        "Check paired companion and addon contracts",
        "Development package smoke",
    ):
        assert step_name in identity
    assert "[string]$RequiredStep.conclusion -cne 'success'" in identity
    assert "@('release', 'marketplace-release', 'verify-curseforge')" in identity
    assert "[string]$Writer.conclusion -cne 'skipped'" in identity
    assert "Reject ambiguous release rerun" in identity
    assert "applicantscout-addon-release-$ReleaseCommit" in identity
    assert "[bool]$Artifacts[0].expired" in identity
    assert "[long]$Artifacts[0].workflow_run.id" in identity
    assert "[string]$Artifacts[0].workflow_run.head_sha" in identity
    assert "Release $env:RELEASE_TAG already exists" in identity
    assert "Could not prove that release" in identity
    assert identity.rstrip().endswith("exit 0")


def test_preupload_recovery_revalidates_every_gate_before_publication():
    workflow = _recovery_workflow_source()
    recovery = _job_block(workflow, "recover-github-release")
    paired = _step_block(recovery, "Revalidate paired immutable companion release")
    credentials = _step_block(recovery, "Require intended publication credentials")
    policy = _step_block(recovery, "Verify immutable release policy")
    download = _step_block(recovery, "Download verified source-run bundle")
    publish = _step_block(recovery, "Publish verified immutable GitHub release")

    assert "-RequirePublishedPairedCompanionAssets" in paired
    assert "-PublishedReleaseWaitSeconds 0" in paired
    assert "CF_API_KEY" in credentials
    assert "WAGO_API_TOKEN" in credentials
    assert "IMMUTABLE_RELEASES_READ_TOKEN" in policy
    assert "immutable-releases" in policy
    assert download.count("\n        env:\n") == 1
    assert "gh run download $env:SOURCE_RUN_ID" in download
    assert "--name $env:ARTIFACT_NAME" in download
    assert "scripts/check_addon_archive.py" in publish
    assert "scripts/create_release_metadata.py" in publish
    assert "$OriginalMetadataHash -cne $RegeneratedMetadataHash" in publish
    assert "gh release create" in publish
    assert "--draft" in publish
    assert "gh release edit" in publish
    assert "$Published.immutable -is [bool]" in publish
    assert publish.count("-RequirePublishedPairedCompanionAssets") == 2
    _assert_order(
        recovery,
        "Verify pre-upload timeout recovery identity",
        "Revalidate paired immutable companion release",
        "Require intended publication credentials",
        "Verify immutable release policy",
        "Download verified source-run bundle",
        "Publish verified immutable GitHub release",
    )


def test_preupload_recovery_publishes_marketplaces_only_after_github():
    workflow = _recovery_workflow_source()
    marketplace = _job_block(workflow, "marketplace-release")
    verifier = _job_block(workflow, "verify-curseforge")
    checkout = _step_block(marketplace, "Checkout exact immutable release tag")
    revalidate = _step_block(
        marketplace, "Revalidate immutable GitHub and companion releases"
    )
    credentials = _step_block(marketplace, "Require intended marketplace credentials")
    upload = _step_block(marketplace, "Publish exact tag to marketplaces")
    verify = _step_block(verifier, "Verify CurseForge public release propagation")

    assert "needs: recover-github-release" in marketplace
    assert re.search(r"(?m)^    permissions:\n      contents: read\s*$", marketplace)
    assert "ref: ${{ inputs.tag }}" in checkout
    assert "persist-credentials: false" in checkout
    assert "-RequirePublishedPairedCompanionAssets" in revalidate
    assert "$Release.immutable -isnot [bool]" in revalidate
    assert "CF_API_KEY" in credentials
    assert "WAGO_API_TOKEN" in credentials
    assert (
        "uses: BigWigsMods/packager@6d50adb6e8517eefef63f4afb16a6518166a6b28"
        in upload
    )
    assert "GITHUB_OAUTH" not in marketplace
    assert "needs: marketplace-release" in verifier
    assert "contents: read" in verifier
    assert "--tag \"$RELEASE_TAG\"" in verify
    assert "--project-id 1541576" in verify
    assert "--toc ApplicantScout.toc" in verify
    assert "--game-version" not in verify
    assert "--wait-seconds 900" in verify


def test_preupload_recovery_pins_external_actions_to_commit_shas():
    action_refs = _workflow_action_refs(_recovery_workflow_source())

    assert Counter(action for action, _ in action_refs) == Counter(
        {
            "actions/checkout": 3,
            "actions/setup-python": 1,
            "BigWigsMods/packager": 1,
        }
    )
    for action, ref in action_refs:
        assert _SHA_REF_RE.fullmatch(ref), f"{action} must be pinned to a full commit SHA"


def test_release_requires_immutable_policy_before_draft_publication():
    workflow = _workflow_source()
    release = _job_block(workflow, "release")
    credentials = _step_block(
        release, "Require intended marketplace credentials before publication"
    )
    policy = _step_block(release, "Verify immutable release policy")
    publish = _step_block(release, "Publish verified immutable GitHub release")

    assert "IMMUTABLE_RELEASES_READ_TOKEN" in policy
    assert "CF_API_KEY" in credentials
    assert "WAGO_API_TOKEN" in credentials
    assert "immutable-releases" in policy
    assert ".enabled -isnot [bool]" in policy
    assert "releases/latest" in publish
    assert "must be newer than latest stable" in publish
    assert "--draft" in publish
    assert "@($Draft.assets).Count -ne $Expected.Count" in publish
    assert "$Published.immutable -is [bool]" in publish
    assert publish.count("-RequirePublishedPairedCompanionAssets") == 3
    assert "Exact release refs changed while GitHub publication" in publish
    _assert_order(
        release,
        "Require intended marketplace credentials before publication",
        "Verify immutable release policy",
        "Download verified exact-tag release bundle",
        "Publish verified immutable GitHub release",
    )


def test_third_party_packager_has_read_only_token_and_explicit_channels():
    workflow = _workflow_source()
    release = _job_block(workflow, "release")
    marketplace_release = _job_block(workflow, "marketplace-release")
    credentials = _step_block(
        marketplace_release, "Recheck intended marketplace credentials"
    )

    assert "BigWigsMods/packager@" not in release
    assert re.search(
        r"(?m)^    permissions:\n      contents: read\s*$", marketplace_release
    )
    assert "CF_API_KEY" in credentials
    assert "WAGO_API_TOKEN" in credentials
    assert "GITHUB_OAUTH" not in marketplace_release
    _assert_order(
        marketplace_release,
        "Recheck intended marketplace credentials",
        "Publish exact tag to marketplaces",
    )


def test_release_job_keeps_marketplace_publish_checkout_at_repo_root():
    workflow = _workflow_source()
    release = _job_block(workflow, "release")
    marketplace_release = _job_block(workflow, "marketplace-release")
    checkout = _step_block(release, "Checkout")
    marketplace_checkout = _step_block(
        marketplace_release, "Checkout exact immutable release tag"
    )

    assert "path:" not in checkout
    assert "path:" not in marketplace_checkout
    assert "persist-credentials: false" in checkout
    assert "persist-credentials: false" in marketplace_checkout
    assert "uses: BigWigsMods/packager@" not in release
    assert "uses: BigWigsMods/packager@" in marketplace_release


def test_curseforge_verifier_is_separate_read_only_post_release_job():
    workflow = _workflow_source()
    marketplace_release = _job_block(workflow, "marketplace-release")
    verifier = _job_block(workflow, "verify-curseforge")
    verify_step = _step_block(
        verifier, "Verify CurseForge public release propagation"
    )

    assert "needs: marketplace-release" in verifier
    assert "contents: read" in verifier
    assert "secrets." not in verifier
    assert "BigWigsMods/packager@" in marketplace_release
    assert "BigWigsMods/packager@" not in verifier
    assert "scripts/verify_curseforge_release.py" in verify_step
    assert "--tag \"$GITHUB_REF_NAME\"" in verify_step
    assert "--project-id 1541576" in verify_step
    assert "--toc ApplicantScout.toc" in verify_step
    assert "--game-version" not in verify_step
    assert "--wait-seconds 900" in verify_step


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
            CURRENT_ADDON_TAG,
            "-PairedCompanionRefOutputPath",
            str(output_path),
        ],
        cwd=REPO_ROOT,
        text=True,
        capture_output=True,
        check=False,
    )

    assert result.returncode == 0, result.stdout + result.stderr
    assert (
        output_path.read_text(encoding="utf-8")
        == f"companion_ref={CURRENT_COMPANION_TAG}\n"
    )


@pytest.mark.parametrize(
    "bad_install_copy",
    [
        "https://github.com/Antrakt92/ApplicantScout-Addon/releases/download/v0.4.5/ApplicantScout-v0.4.5.zip",
        "https://github.com/Antrakt92/ApplicantScout-Companion/releases/download/v0.8.2/ApplicantScoutCompanionSetup-0.8.2.exe",
        "https://github.com/Antrakt92/ApplicantScout-Addon/releases",
        "https://github.com/Antrakt92/ApplicantScout-Companion/releases",
        "https://github.com/Antrakt92/ApplicantScout-Addon/archive/refs/tags/v0.4.5.zip",
        "https://github.com/Antrakt92/ApplicantScout-Addon/zipball/v0.4.5",
        "https://github.com/Antrakt92/ApplicantScout-Companion/tarball/v0.8.2",
        "ApplicantScout WoW addon `0.4.5`",
        "ApplicantScout Companion `0.8.2`",
        "Install `ApplicantScout-0.4.5.zip` from GitHub.",
        "Install `ApplicantScoutCompanionSetup-0.8.2.exe` from GitHub.",
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

    result = _run_release_check_in(repo, "-Tag", CURRENT_ADDON_TAG)

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
                f"## {CURRENT_COMPANION_VERSION} - 30-May-2026",
                "",
                "### Release Assets",
                "",
                f"- Requires the ApplicantScout WoW addon `{CURRENT_ADDON_VERSION}`.",
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
            CURRENT_ADDON_TAG,
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
    newer_addon_version = _next_patch_version(CURRENT_ADDON_VERSION)
    companion = tmp_path / "ApplicantScout-Companion"
    companion.mkdir()
    (companion / "RELEASE_NOTES.md").write_text(
        "\n".join(
            [
                "# ApplicantScout Companion Release Notes",
                "",
                f"## {CURRENT_COMPANION_VERSION} - 30-May-2026",
                "",
                "### Release Assets",
                "",
                f"- Requires the ApplicantScout WoW addon `{newer_addon_version}`.",
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
            CURRENT_ADDON_TAG,
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
    assert f"requires addon {newer_addon_version}" in output
    assert f"current addon tag is {CURRENT_ADDON_VERSION}" in output


def test_release_version_script_does_not_invoke_companion_release_script():
    script = _read_repo_text("scripts/check-release-version.ps1")

    assert "ApplicantScout-Companion\\scripts\\check-release-version.ps1" not in script
    assert "ApplicantScout-Companion/scripts/check-release-version.ps1" not in script


def test_shared_paired_release_policy_stays_in_sync(pytestconfig):
    companion_root = pytestconfig.getoption("--companion-root")
    if not companion_root:
        pytest.skip("--companion-root is required for release-policy parity")

    addon_source = _read_repo_text("scripts/check-release-version.ps1")
    companion_script = Path(companion_root) / "scripts" / "check-release-version.ps1"
    assert companion_script.is_file(), (
        f"Missing paired companion release policy: {companion_script}"
    )
    companion_source = companion_script.read_text(encoding="utf-8")

    for name in _SHARED_RELEASE_POLICY_FUNCTIONS:
        assert _powershell_function_block(
            addon_source, name
        ) == _powershell_function_block(companion_source, name), (
            f"Shared release-policy function drifted: {name}"
        )
    for name in _SHARED_RELEASE_POLICY_ARRAYS:
        assert _powershell_array_block(addon_source, name) == _powershell_array_block(
            companion_source, name
        ), f"Shared release-policy array drifted: ${name}"


@pytest.mark.parametrize("addon_tag", [CURRENT_ADDON_TAG, CURRENT_ADDON_VERSION])
def test_release_version_check_accepts_published_paired_companion_assets(
    tmp_path: Path,
    addon_tag: str,
):
    release_json, manifest_json = _valid_paired_release_fixture()
    gh = _fake_gh_release_view(
        tmp_path,
        expected_tag=CURRENT_COMPANION_TAG,
        release_json=release_json,
        manifest_json=manifest_json,
    )

    result = _run_release_check(
        "-Tag",
        addon_tag,
        "-RequirePublishedPairedCompanionAssets",
        "-GitHubCliPath",
        str(gh),
        "-PublishedReleaseWaitSeconds",
        "0",
    )

    assert result.returncode == 0, result.stdout + result.stderr


@pytest.mark.parametrize("immutable", [False, None, "true", 1])
def test_release_version_check_rejects_mutable_paired_companion_release(
    tmp_path: Path,
    immutable: object,
):
    release_json, manifest_json = _valid_paired_release_fixture()
    release_json["isImmutable"] = immutable
    gh = _fake_gh_release_view(
        tmp_path,
        expected_tag=CURRENT_COMPANION_TAG,
        release_json=release_json,
        manifest_json=manifest_json,
    )

    result = _run_release_check(
        "-Tag",
        CURRENT_ADDON_TAG,
        "-RequirePublishedPairedCompanionAssets",
        "-GitHubCliPath",
        str(gh),
        "-PublishedReleaseWaitSeconds",
        "0",
    )

    assert result.returncode != 0
    assert "must be immutable" in (result.stdout + result.stderr)


def test_release_version_check_rejects_missing_immutable_state(tmp_path: Path):
    release_json, manifest_json = _valid_paired_release_fixture()
    del release_json["isImmutable"]
    gh = _fake_gh_release_view(
        tmp_path,
        expected_tag=CURRENT_COMPANION_TAG,
        release_json=release_json,
        manifest_json=manifest_json,
        default_immutable=False,
    )

    result = _run_release_check(
        "-Tag",
        CURRENT_ADDON_TAG,
        "-RequirePublishedPairedCompanionAssets",
        "-GitHubCliPath",
        str(gh),
        "-PublishedReleaseWaitSeconds",
        "0",
    )

    assert result.returncode != 0
    assert "must be immutable" in (result.stdout + result.stderr)


def test_release_version_check_rejects_moved_remote_addon_tag(tmp_path: Path):
    release_json, manifest_json = _valid_paired_release_fixture()
    gh = _fake_gh_release_view(
        tmp_path,
        expected_tag=CURRENT_COMPANION_TAG,
        release_json=release_json,
        manifest_json=manifest_json,
        addon_commit="a" * 40,
    )

    result = _run_release_check(
        "-Tag",
        CURRENT_ADDON_TAG,
        "-RequirePublishedPairedCompanionAssets",
        "-GitHubCliPath",
        str(gh),
        "-PublishedReleaseWaitSeconds",
        "0",
    )

    assert result.returncode != 0
    assert "moved away from the release checkout" in (result.stdout + result.stderr)


@pytest.mark.parametrize("field", ["pairedAddonTag", "pairedAddonCommit", "commit"])
def test_release_version_check_rejects_mismatched_paired_manifest_identity(
    tmp_path: Path,
    field: str,
):
    release_json, manifest_json = _valid_paired_release_fixture()
    manifest_json[field] = "wrong"
    gh = _fake_gh_release_view(
        tmp_path,
        expected_tag=CURRENT_COMPANION_TAG,
        release_json=release_json,
        manifest_json=manifest_json,
    )

    result = _run_release_check(
        "-Tag",
        CURRENT_ADDON_TAG,
        "-RequirePublishedPairedCompanionAssets",
        "-GitHubCliPath",
        str(gh),
        "-PublishedReleaseWaitSeconds",
        "0",
    )

    assert result.returncode != 0
    assert "manifest" in (result.stdout + result.stderr)


def test_release_version_check_rejects_manifest_asset_digest_mismatch(
    tmp_path: Path,
):
    release_json, manifest_json = _valid_paired_release_fixture()
    payload_asset = release_json["assets"][0]
    assert isinstance(payload_asset, dict)
    payload_asset["digest"] = "sha256:" + "0" * 64
    gh = _fake_gh_release_view(
        tmp_path,
        expected_tag=CURRENT_COMPANION_TAG,
        release_json=release_json,
        manifest_json=manifest_json,
    )

    result = _run_release_check(
        "-Tag",
        CURRENT_ADDON_TAG,
        "-RequirePublishedPairedCompanionAssets",
        "-GitHubCliPath",
        str(gh),
        "-PublishedReleaseWaitSeconds",
        "0",
    )

    assert result.returncode != 0
    assert "does not match its immutable manifest" in (result.stdout + result.stderr)


def test_release_version_check_rejects_unexpected_paired_companion_release_asset(
    tmp_path: Path,
):
    stale_version = _previous_patch_version(CURRENT_COMPANION_VERSION)
    gh = _fake_gh_release_view(
        tmp_path,
        expected_tag=CURRENT_COMPANION_TAG,
        release_json={
            "tagName": CURRENT_COMPANION_TAG,
            "isDraft": False,
            "isPrerelease": False,
            "assets": [
                {"name": f"ApplicantScoutCompanionSetup-{CURRENT_COMPANION_VERSION}.exe"},
                {
                    "name": (
                        f"ApplicantScoutCompanionSetup-{CURRENT_COMPANION_VERSION}"
                        ".exe.sha256"
                    )
                },
                {
                    "name": (
                        f"ApplicantScoutCompanion-{CURRENT_COMPANION_VERSION}"
                        "-portable.zip"
                    )
                },
                {
                    "name": (
                        f"ApplicantScoutCompanion-{CURRENT_COMPANION_VERSION}"
                        "-release-manifest.json"
                    )
                },
                {"name": f"ApplicantScoutCompanionSetup-{stale_version}.exe"},
            ],
        },
    )

    result = _run_release_check(
        "-Tag",
        CURRENT_ADDON_TAG,
        "-RequirePublishedPairedCompanionAssets",
        "-GitHubCliPath",
        str(gh),
        "-PublishedReleaseWaitSeconds",
        "0",
    )

    assert result.returncode != 0
    output = re.sub(r"\s+", "", result.stdout + result.stderr)
    assert (
        f"unexpectedasset:ApplicantScoutCompanionSetup-{stale_version}.exe" in output
    )


def test_release_version_check_rejects_missing_paired_companion_checksum(
    tmp_path: Path,
):
    gh = _fake_gh_release_view(
        tmp_path,
        expected_tag=CURRENT_COMPANION_TAG,
        release_json={
            "tagName": CURRENT_COMPANION_TAG,
            "isDraft": False,
            "isPrerelease": False,
            "assets": [
                {"name": f"ApplicantScoutCompanionSetup-{CURRENT_COMPANION_VERSION}.exe"},
                {
                    "name": (
                        f"ApplicantScoutCompanion-{CURRENT_COMPANION_VERSION}"
                        "-portable.zip"
                    )
                },
                {
                    "name": (
                        f"ApplicantScoutCompanion-{CURRENT_COMPANION_VERSION}"
                        "-release-manifest.json"
                    )
                },
            ],
        },
    )

    result = _run_release_check(
        "-Tag",
        CURRENT_ADDON_TAG,
        "-RequirePublishedPairedCompanionAssets",
        "-GitHubCliPath",
        str(gh),
        "-PublishedReleaseWaitSeconds",
        "0",
    )

    assert result.returncode != 0
    output = re.sub(r"\s+", "", result.stdout + result.stderr)
    assert (
        f"missingasset:ApplicantScoutCompanionSetup-{CURRENT_COMPANION_VERSION}"
        ".exe.sha256"
    ) in output


def test_release_version_check_rejects_missing_paired_companion_manifest(
    tmp_path: Path,
):
    gh = _fake_gh_release_view(
        tmp_path,
        expected_tag=CURRENT_COMPANION_TAG,
        release_json={
            "tagName": CURRENT_COMPANION_TAG,
            "isDraft": False,
            "isPrerelease": False,
            "assets": [
                {"name": f"ApplicantScoutCompanionSetup-{CURRENT_COMPANION_VERSION}.exe"},
                {
                    "name": (
                        f"ApplicantScoutCompanionSetup-{CURRENT_COMPANION_VERSION}"
                        ".exe.sha256"
                    )
                },
                {
                    "name": (
                        f"ApplicantScoutCompanion-{CURRENT_COMPANION_VERSION}"
                        "-portable.zip"
                    )
                },
            ],
        },
    )

    result = _run_release_check(
        "-Tag",
        CURRENT_ADDON_TAG,
        "-RequirePublishedPairedCompanionAssets",
        "-GitHubCliPath",
        str(gh),
        "-PublishedReleaseWaitSeconds",
        "0",
    )

    assert result.returncode != 0
    output = re.sub(r"\s+", "", result.stdout + result.stderr)
    assert (
        f"missingasset:ApplicantScoutCompanion-{CURRENT_COMPANION_VERSION}"
        "-release-manifest.json"
    ) in output


def test_release_version_check_rejects_draft_paired_companion_release(
    tmp_path: Path,
):
    gh = _fake_gh_release_view(
        tmp_path,
        expected_tag=CURRENT_COMPANION_TAG,
        release_json={
            "tagName": CURRENT_COMPANION_TAG,
            "isDraft": True,
            "isPrerelease": False,
            "assets": [
                {"name": f"ApplicantScoutCompanionSetup-{CURRENT_COMPANION_VERSION}.exe"},
                {
                    "name": (
                        f"ApplicantScoutCompanionSetup-{CURRENT_COMPANION_VERSION}"
                        ".exe.sha256"
                    )
                },
                {
                    "name": (
                        f"ApplicantScoutCompanion-{CURRENT_COMPANION_VERSION}"
                        "-portable.zip"
                    )
                },
                {
                    "name": (
                        f"ApplicantScoutCompanion-{CURRENT_COMPANION_VERSION}"
                        "-release-manifest.json"
                    )
                },
            ],
        },
    )

    result = _run_release_check(
        "-Tag",
        CURRENT_ADDON_TAG,
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
        expected_tag=CURRENT_COMPANION_TAG,
        stderr="network failed",
    )

    result = _run_release_check(
        "-Tag",
        CURRENT_ADDON_TAG,
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
        expected_tag=CURRENT_COMPANION_TAG,
        stdout_text="{bad json",
    )

    result = _run_release_check(
        "-Tag",
        CURRENT_ADDON_TAG,
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


def test_workflows_do_not_upgrade_bootstrap_pip():
    for workflow_path in (
        ".github/workflows/check.yml",
        ".github/workflows/release.yml",
    ):
        workflow = _read_repo_text(workflow_path)

        assert "--upgrade pip" not in workflow


def test_release_workflow_pins_external_actions_to_commit_shas():
    workflow = _workflow_source()
    action_refs = _workflow_action_refs(workflow)

    assert Counter(action for action, _ in action_refs) == Counter(
        {
            "actions/checkout": 6,
            "actions/setup-python": 2,
            "BigWigsMods/packager": 2,
            "actions/upload-artifact": 1,
            "actions/download-artifact": 1,
        }
    )
    for action, ref in action_refs:
        assert _SHA_REF_RE.fullmatch(ref), f"{action} must be pinned to a full commit SHA"


def test_check_workflow_runs_non_release_preflight_without_publishing():
    workflow = _read_repo_text(".github/workflows/check.yml")
    job = _job_block(workflow, "check")
    marketplace_job = _job_block(workflow, "marketplace-package")

    assert "push:" in workflow
    assert "pull_request:" in workflow
    assert "workflow_dispatch:" in workflow
    assert "paired_companion_ref:" in workflow
    assert "tags:" not in workflow
    assert re.search(r"(?m)^    runs-on: windows-2022\s*$", job)
    assert "contents: read" in workflow
    assert "contents: write" not in workflow
    assert "APPLICANT_SCOUT_VISUAL_BASELINE" not in workflow
    assert "python-version: '3.13'" in workflow
    assert "repository: Antrakt92/ApplicantScout-Companion" in workflow
    companion_checkout = _step_block(job, "Checkout companion")
    assert "ref: ${{ github.event.inputs.paired_companion_ref || 'main' }}" in (
        companion_checkout
    )
    assert "default: main" in workflow
    assert "type: string" in workflow
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
    assert "BigWigsMods/packager" not in job
    assert "CF_API_KEY" not in workflow
    assert "WAGO_API_TOKEN" not in workflow
    assert "gh release" not in workflow

    dry_run = _step_block(marketplace_job, "Build marketplace package without uploading")
    assert "uses: BigWigsMods/packager@6d50adb6e8517eefef63f4afb16a6518166a6b28" in dry_run
    assert "args: -d" in dry_run
    assert "pandoc: false" in dry_run
    archive_check = _step_block(marketplace_job, "Validate marketplace archive contract")
    assert "python3 scripts/check_addon_archive.py --release-dir .release" in (
        archive_check
    )
    required_entries = {str(entry) for entry in REQUIRED_ENTRIES}
    for required in (
        "ApplicantScout/ApplicantScout.toc",
        "ApplicantScout/ApplicantScout.lua",
        "ApplicantScout/LICENSE",
        "ApplicantScout/THIRD-PARTY-NOTICES.md",
        "ApplicantScout/media/logo.png",
        "ApplicantScout/libs/qrencode.lua",
    ):
        assert required in required_entries
    forbidden_contract = FORBIDDEN_NAMES | FORBIDDEN_PARTS
    for forbidden in (".pkgmeta", "AGENTS.md", "docs", "scripts", "tests"):
        assert forbidden.casefold() in forbidden_contract
    _assert_order(
        marketplace_job,
        "Checkout addon for marketplace package",
        "Build marketplace package without uploading",
        "Validate marketplace archive contract",
    )


def test_check_workflow_pins_external_actions_to_commit_shas():
    workflow = _read_repo_text(".github/workflows/check.yml")
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


def test_public_repo_does_not_track_developer_only_root_files():
    tracked = subprocess.run(
        ["git", "ls-files", "--"],
        cwd=REPO_ROOT,
        check=True,
        capture_output=True,
        text=True,
    ).stdout.splitlines()
    forbidden = {
        "AGENTS.md",
        "AUDIT.md",
        "PLAN.md",
        "NOTES.md",
        "TODO.md",
        "CLAUDE.md",
    }

    leaked = sorted(path for path in tracked if path in forbidden)

    assert leaked == []


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


def test_toc_and_readme_document_current_retail_interfaces():
    toc = _read_repo_text("ApplicantScout.toc")
    readme = _read_repo_text("README.md")
    match = re.search(r"(?m)^##\s+Interface:\s*(.+?)\s*$", toc)

    assert match is not None, "ApplicantScout.toc is missing ## Interface"
    interfaces = match.group(1)
    assert "120100" in [part.strip() for part in interfaces.split(",")]
    assert f"WoW Retail Midnight: Interface `{interfaces}`." in readme


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

    assert "Wire payload: compact v9" in readme
    assert "A v11 frame" in readme
    assert "v10 fragment" in readme
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


def test_readme_uses_local_anonymized_public_overlay_media():
    readme = _read_repo_text("README.md")

    assert "media.forgecdn.net" not in readme
    for image_name in (
        "applicantscout-curseforge-raid-party-overlay.jpg",
        "applicantscout-curseforge-mplus-overlay.jpg",
    ):
        assert f'src="docs/visual/{image_name}"' in readme
        assert (REPO_ROOT / "docs" / "visual" / image_name).read_bytes().startswith(
            b"\xff\xd8\xff"
        )
    assert (
        'alt="ApplicantScout raid applicant overlay with Warcraft Logs, RaiderIO, '
        'raid progress, and role context" width="45%"'
    ) in readme
    assert (
        'alt="ApplicantScout Mythic Plus applicant overlay with key fit, WCL '
        'percentiles, and RaiderIO score context" width="45%"'
    ) in readme


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
        "last-live-snapshot.json",
        "screenshot-manual-index-v2-*.json",
        "%LOCALAPPDATA%\\applicant-scout\\config\\",
        "%LOCALAPPDATA%\\applicant-scout\\cache\\",
        "do not attach either directory wholesale",
    ):
        _assert_copy_contains(readme, sensitive_surface)

    for private_detail in (
        "WCL Client ID/Secret",
        "OAuth access token",
        "character names",
        "realm names",
        "applicant/roster snapshots",
        "listing titles/comments",
        "screenshots folder paths",
        "absolute screenshot file paths",
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


def test_public_slash_help_and_handler_branches_are_symmetric():
    source = _read_repo_text("ApplicantScout.lua")
    help_roots = _help_command_roots(_lua_print_help_command_lines(source))
    handler_roots = _handler_command_roots(source)
    hidden_aliases = {"settings", "nocompetitive", "nodebug"}

    assert hidden_aliases <= handler_roots
    assert handler_roots - hidden_aliases == help_roots
