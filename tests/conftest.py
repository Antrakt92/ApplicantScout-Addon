from __future__ import annotations

from pathlib import Path


def pytest_addoption(parser):
    parser.addoption(
        "--companion-root",
        action="store",
        default=None,
        help="Path to the paired ApplicantScout-Companion checkout.",
    )
    parser.addoption(
        "--lua51",
        action="store",
        default=None,
        help="Path to a Lua 5.1 interpreter for Lua fixture generation.",
    )


def pytest_configure(config):
    config.addinivalue_line(
        "markers",
        "requires_companion: tests that compare addon output against companion fixtures",
    )


def pytest_report_header(config):
    companion_root = config.getoption("--companion-root")
    lua51 = config.getoption("--lua51")
    parts = []
    if companion_root:
        parts.append(f"companion-root={Path(companion_root)}")
    if lua51:
        parts.append(f"lua51={lua51}")
    if parts:
        return "ApplicantScout contract options: " + ", ".join(parts)
    return None
