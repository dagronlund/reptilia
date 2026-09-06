"""Capture individual test logs and report completed Ninja tests."""

from __future__ import annotations

import argparse
import json
import shlex
import subprocess
import sys
from pathlib import Path

from colorama import Fore, Style

RESULT_PREFIX = "REPTILIA_TEST_RESULT "


def test_command() -> str:
    """Command prefix shared by generated test rules."""
    return shlex.join([sys.executable, str(Path(__file__).resolve())])


def _print_log(log: Path) -> None:
    output = log.read_text(encoding="utf-8", errors="replace")
    print(output, end="" if output.endswith("\n") else "\n", flush=True)


def run_test_ninja(
    path: Path, *, output: bool = False, jobs: int | None = None
) -> None:
    """Report completions, then replay failures after every Ninja job finishes."""
    command = ["ninja", "-f", str(path), "-k", "0", "--quiet"]
    if jobs is not None:
        command.extend(["-j", str(jobs)])
    failures: list[tuple[str, Path]] = []
    diagnostics: list[str] = []
    with subprocess.Popen(
        command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True
    ) as process:
        assert process.stdout is not None
        for line in process.stdout:
            if not line.startswith(RESULT_PREFIX):
                diagnostics.append(line)
                continue
            result = json.loads(line.removeprefix(RESULT_PREFIX))
            name, log = result["name"], Path(result["log"])
            passed = result["passed"]
            color, status = (Fore.GREEN, "PASS") if passed else (Fore.RED, "FAIL")
            if output:
                _print_log(log)
            print(f"{color}{status}{Style.RESET_ALL}: {name}", flush=True)
            if not passed:
                failures.append((name, log))
        returncode = process.wait()

    for name, log in failures:
        print(f"\nFailed test output: {name}", flush=True)
        _print_log(log)
    # Preserve infrastructure errors, but omit Ninja's duplicate failure commands.
    if returncode and not failures:
        print("".join(diagnostics), end="", flush=True)
    if returncode or failures:
        raise subprocess.CalledProcessError(returncode or 1, command)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--name", required=True)
    parser.add_argument("--log", type=Path, required=True)
    parser.add_argument("--pass-pattern")
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command
    if command[:1] == ["--"]:
        command = command[1:]
    args.log.parent.mkdir(parents=True, exist_ok=True)
    with args.log.open("w", encoding="utf-8") as log:
        try:
            result = subprocess.run(
                command, stdout=log, stderr=subprocess.STDOUT, check=False
            )
            passed = result.returncode == 0
        except OSError as error:
            log.write(f"{error}\n")
            passed = False
    if passed and args.pass_pattern:
        passed = args.pass_pattern in args.log.read_text(
            encoding="utf-8", errors="replace"
        )
    print(
        RESULT_PREFIX
        + json.dumps(
            {
                "name": args.name,
                "log": str(args.log),
                "passed": passed,
            }
        ),
        flush=True,
    )
    sys.exit(0 if passed else 1)
