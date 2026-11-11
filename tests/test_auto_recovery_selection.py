"""Execute the scheduled selector with a closed, read-only GitHub API fixture."""

import json
import subprocess
import sys
import textwrap
from datetime import datetime, timedelta, timezone
from pathlib import Path

import pytest

WORKFLOW = Path(__file__).resolve().parents[1] / ".github/workflows/auto-recover-preupload-release.yml"
RECOVERY_WORKFLOW = WORKFLOW.with_name("recover-preupload-release.yml")


def _run(run_id, *, status="completed", conclusion="failure", age=0):
    return {
        "id": run_id, "run_number": run_id, "name": "Package and release",
        "path": ".github/workflows/release.yml", "event": "push",
        "status": status, "conclusion": conclusion, "head_branch": f"v0.10.{run_id}",
        "head_sha": "a" * 40, "run_attempt": 1,
        "created_at": (datetime.now(timezone.utc) - timedelta(hours=age)).isoformat(),
    }


def _jobs(*, failed_step="Verify paired companion published release assets", writer="skipped"):
    required = [
        "Checkout addon", "Verify release tag is reachable from origin/main",
        "Check release version", "Wait for paired companion tag", "Checkout paired companion",
        "Validate paired companion metadata", "Set up Python", "Install Python dependencies",
        "Install Lua 5.1", "Install pinned LuaLS", "Check addon Lua diagnostics",
        "Check paired companion and addon contracts", "Development package smoke",
        "Verify paired companion published release assets",
    ]
    return {"jobs": [
        {"name": "preflight", "conclusion": "failure", "steps": [
            {"name": name, "conclusion": "failure" if name == failed_step else "success"}
            for name in required
        ]},
        {"name": "marketplace-package", "conclusion": "success"},
        *[{"name": name, "conclusion": writer} for name in
          ("release", "marketplace-release", "verify-curseforge", "verify-wago")],
    ]}


def _execute(tmp_path, runs, jobs=None, *, artifact_expired=False,
             release_error="release not found\n", release_exit=1, phase="discovery"):
    workflow, step = {
        "discovery": (WORKFLOW, "Find exact recoverable release run"),
        "dispatch": (WORKFLOW, "Revalidate candidate and dispatch guarded recovery"),
        "recovery": (RECOVERY_WORKFLOW, "Verify pre-upload timeout recovery identity"),
    }[phase]
    source = workflow.read_text(encoding="utf-8").split(f"      - name: {step}\n", 1)[1]
    selector = textwrap.dedent(source.split("        run: |\n", 1)[1].split("\n      - name:", 1)[0])
    fixture = {
        "runs": {"workflow_runs": runs}, "jobs": jobs or _jobs(),
        "python": sys.executable, "release_error": release_error, "release_exit": release_exit,
        "artifacts": {"artifacts": [{
            "name": "applicantscout-addon-release-" + "a" * 40,
            "expired": artifact_expired,
            "workflow_run": {"id": 1, "head_sha": "a" * 40, "head_branch": "v0.10.1"},
        }]},
    }
    (tmp_path / "api.json").write_text(json.dumps(fixture), encoding="utf-8")
    prelude = r'''
    $ErrorActionPreference = 'Stop'
    $Fixture = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'api.json') -Raw | ConvertFrom-Json
    $env:GITHUB_REPOSITORY = 'fixture/addon'
    $env:GITHUB_OUTPUT = Join-Path $PSScriptRoot 'output.txt'
    $env:SOURCE_RUN_ID = '1'
    $env:RELEASE_TAG = 'v0.10.1'
    $env:RELEASE_COMMIT = 'a' * 40
    function git {
      $global:LASTEXITCODE = 0
      if ($args[0] -ceq 'rev-parse') { 'a' * 40 }
      elseif ($args[0] -cnotin @('fetch', 'merge-base')) { throw "Unexpected git command: $args" }
    }
    function gh {
      $global:LASTEXITCODE = 0
      $Command = $args -join ' '
      Add-Content -LiteralPath (Join-Path $PSScriptRoot 'calls.txt') -Value $Command
      if ($Command -like 'api *actions/workflows/release.yml/runs?*') {
        $Fixture.runs | ConvertTo-Json -Depth 20
      } elseif ($Command -like 'api *actions/runs/1') {
        $Fixture.runs.workflow_runs | Where-Object id -eq 1 | ConvertTo-Json -Depth 20
      } elseif ($Command -like 'api *actions/workflows/recover-preupload-release.yml/runs?*') {
        '{"workflow_runs": []}'
      } elseif ($Command -like 'workflow run recover-preupload-release.yml *') {
        return
      } elseif ($Command -like 'release view *') {
        & $Fixture.python -c 'import sys; sys.stderr.write(sys.argv[1]); sys.exit(int(sys.argv[2]))' ([string]$Fixture.release_error) ([string]$Fixture.release_exit)
      } elseif ($Command -like 'api *attempts/1/jobs?*') {
        $Fixture.jobs | ConvertTo-Json -Depth 20
      } elseif ($Command -like 'api *artifacts?*') {
        $Fixture.artifacts | ConvertTo-Json -Depth 20
      } else { throw "Unexpected command: $Command" }
    }
    '''
    script = tmp_path / "selector.ps1"
    script.write_text(textwrap.dedent(prelude) + selector, encoding="utf-8")
    result = subprocess.run(
        ["pwsh", "-NoProfile", "-File", str(script)],
        capture_output=True, text=True, timeout=30, check=False,
    )
    output = tmp_path / "output.txt"
    return result, output.read_text(encoding="utf-8") if output.exists() else ""


@pytest.mark.parametrize("status,conclusion", [
    ("completed", "success"), ("in_progress", None), ("queued", None),
])
def test_newer_release_attempt_supersedes_failed_tag(tmp_path, status, conclusion):
    result, output = _execute(tmp_path, [
        _run(1, age=1), _run(2, status=status, conclusion=conclusion),
    ], _jobs(failed_step="Check paired companion and addon contracts"))
    assert result.returncode == 0, result.stdout + result.stderr
    assert output == ""
    # Superseded runs must not reach artifact inspection or recovery dispatch.
    assert len((tmp_path / "calls.txt").read_text().splitlines()) == 1


def test_unrecoverable_test_failure_is_quiet_without_dispatch(tmp_path):
    result, output = _execute(tmp_path, [_run(1)],
                              _jobs(failed_step="Check paired companion and addon contracts"))
    assert result.returncode == 0, result.stdout + result.stderr
    assert output == ""


def test_exclusive_paired_wait_failure_remains_recoverable(tmp_path):
    result, output = _execute(tmp_path, [_run(1)])
    assert result.returncode == 0, result.stdout + result.stderr
    assert "candidate=true\ntag=v0.10.1\nrun_id=1\n" in output


@pytest.mark.parametrize("error,exit_code", [
    ("", 1), ("Repository not found\n", 1), ("connection reset\n", 1), ("release not found\n", 2),
])
def test_release_absence_requires_exact_missing_release_result(tmp_path, error, exit_code):
    result, output = _execute(tmp_path, [_run(1)], release_error=error, release_exit=exit_code)
    assert result.returncode != 0
    assert "Could not prove that release" in result.stderr
    assert output == ""


def test_run_number_disambiguates_simultaneous_release_events(tmp_path):
    older, newer = _run(1), _run(2, status="queued", conclusion=None)
    newer["created_at"] = older["created_at"]
    result, output = _execute(tmp_path, [older, newer])
    assert result.returncode == 0, result.stdout + result.stderr
    assert output == ""


@pytest.mark.parametrize("phase", ["dispatch", "recovery"])
def test_later_phase_rejects_candidate_superseded_since_discovery(tmp_path, phase):
    older = _run(1, age=1)
    newer = _run(2, status="queued", conclusion=None)
    result, output = _execute(tmp_path, [older, newer], phase=phase)
    assert output == ""
    calls = (tmp_path / "calls.txt").read_text().splitlines()
    assert len(calls) == 1
    assert "workflows/release.yml/runs?" in calls[0]
    if phase == "dispatch":
        assert result.returncode == 0, result.stdout + result.stderr
        assert "no longer the latest" in result.stdout
    else:
        assert result.returncode != 0
        assert "latest failed exact-tag" in result.stderr


@pytest.mark.parametrize("phase", ["dispatch", "recovery"])
def test_later_phase_accepts_exact_current_failed_candidate(tmp_path, phase):
    result, output = _execute(tmp_path, [_run(1)], phase=phase)
    assert result.returncode == 0, result.stdout + result.stderr
    if phase == "dispatch":
        assert "Dispatched guarded recovery" in result.stdout
    else:
        assert "artifact_name=applicantscout-addon-release-" in output


@pytest.mark.parametrize("writer,expired", [("success", False), ("skipped", True)])
def test_candidate_still_rejects_started_writers_and_expired_artifacts(tmp_path, writer, expired):
    result, output = _execute(tmp_path, [_run(1)], _jobs(writer=writer), artifact_expired=expired)
    assert result.returncode != 0
    assert "was not skipped" in result.stderr or "missing, expired, or mismatched" in result.stderr
    assert output == ""


@pytest.mark.parametrize("runs", [[], [_run(1, age=24 * 7)]])
def test_no_recent_candidate_is_quiet(tmp_path, runs):
    result, output = _execute(tmp_path, runs)
    assert result.returncode == 0, result.stdout + result.stderr
    assert output == ""
