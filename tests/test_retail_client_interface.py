import subprocess
from pathlib import Path

import pytest


REPO_ROOT = Path(__file__).resolve().parents[1]


def _check(tmp_path, *args, toc="## Interface: 120100\n", readme=None):
    toc_path = tmp_path / "ApplicantScout.toc"
    toc_path.write_text(toc, encoding="utf-8")
    readme_path = tmp_path / "README.md"
    readme_path.write_text(
        readme or "- WoW Retail Midnight: Interface `120100`.\n",
        encoding="utf-8",
    )
    return subprocess.run(
        [
            "powershell",
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            str(REPO_ROOT / "scripts/check-retail-client-interface.ps1"),
            "-TocPath",
            str(toc_path),
            "-ReadmePath",
            str(readme_path),
            *args,
        ],
        capture_output=True,
        text=True,
        timeout=15,
        check=False,
    )


@pytest.mark.parametrize("version", ["12.1.0", "12.1.0.69273", "Version 12.1.0.69273"])
def test_retail_client_interface_accepts_matching_metadata(tmp_path, version):
    result = _check(tmp_path, "-ClientVersion", version)
    assert result.returncode == 0, result.stderr
    assert (
        "Retail 12.1.0 matches supported Interface 120100" in result.stdout
    )


@pytest.mark.parametrize("extra_interface", ["120100", "120007", ""])
def test_retail_client_interface_rejects_duplicate_headers(tmp_path, extra_interface):
    result = _check(
        tmp_path,
        "-ClientVersion",
        "12.1.0",
        toc=f"## Interface: 120100\n## Interface: {extra_interface}\n",
    )
    assert result.returncode != 0
    assert "exactly one ## Interface:" in result.stderr


@pytest.mark.parametrize(
    "args", [(), ("-ClientVersion", "12.1.0", "-WowExecutablePath", "unused.exe")]
)
def test_retail_client_interface_requires_exactly_one_version_source(tmp_path, args):
    result = _check(tmp_path, *args)
    assert result.returncode != 0
    assert "Specify exactly one version source" in result.stderr


@pytest.mark.parametrize(
    "kwargs, message",
    [
        ({"toc": "## Title: Example\n"}, "exactly one ## Interface:"),
        ({"toc": "## Interface: 120007\n"}, "TOC Interface must include 120100"),
        ({"toc": "## Interface: 120105\n"}, "TOC Interface must include 120100"),
        ({"toc": "## Interface: 120100, 120105\n"}, "README compatibility line"),
        (
            {"readme": "- WoW Retail Midnight: Interface `120007`.\n"},
            "README compatibility line",
        ),
    ],
)
def test_retail_client_interface_rejects_inconsistent_metadata(
    tmp_path, kwargs, message
):
    result = _check(tmp_path, "-ClientVersion", "12.1.0", **kwargs)
    assert result.returncode != 0
    assert message in result.stderr


@pytest.mark.parametrize("version", ["12.1", "12.1.0.invalid", "9.2.0", "12.100.0"])
def test_retail_client_interface_rejects_malformed_client_version(tmp_path, version):
    result = _check(tmp_path, "-ClientVersion", version)
    assert result.returncode != 0
    assert "Retail client version" in result.stderr


@pytest.mark.parametrize("version", ["12.1.0", "12.1.5", "12.1.5.69952"])
def test_retail_client_interface_accepts_documented_retail_and_ptr(tmp_path, version):
    result = _check(
        tmp_path,
        "-ClientVersion",
        version,
        toc="## Interface: 120100, 120105\n",
        readme="- WoW Retail Midnight: Interfaces `120100, 120105`.\n",
    )
    assert result.returncode == 0, result.stderr
    assert "declared: 120100, 120105" in result.stdout


@pytest.mark.parametrize(
    "interfaces",
    [
        "120100, 120100",
        "120100, 120105, 120105",
        "120100,",
        ",120100",
        "120100,,120105",
        "120100, invalid",
        "120100, 012105",
        "120100 120105",
        "",
    ],
)
def test_retail_client_interface_rejects_malformed_or_duplicate_list(tmp_path, interfaces):
    result = _check(
        tmp_path,
        "-ClientVersion",
        "12.1.0",
        toc=f"## Interface: {interfaces}\n",
        readme=f"- WoW Retail Midnight: Interfaces `{interfaces}`.\n",
    )
    assert result.returncode != 0
    assert "TOC Interface must" in result.stderr


def test_retail_client_interface_rejects_undeclared_ptr(tmp_path):
    result = _check(tmp_path, "-ClientVersion", "12.1.5")
    assert result.returncode != 0
    assert "TOC Interface must include 120105" in result.stderr
