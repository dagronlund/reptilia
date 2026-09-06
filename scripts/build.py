"""
Lints the RTL and runs selected RustDV regressions
"""

from __future__ import annotations

import copy
import glob
import os
import subprocess
from pathlib import Path
from typing import cast

from .rustdv import (
    WaveFormat,
    build_rustdv_targets,
    discover_targets,
    run_rustdv_tests,
    select_targets,
)
from .util import error, info
from .verilator import VerilatorLint, write_verilator_ninja_rules

DependencyInfo = tuple[list[str], list[str], str | None, bool]


def get_includes_imports(path: str) -> DependencyInfo:
    """Parses special comments in the file to find dependencies"""
    with open(path, "r", encoding="utf-8") as file:
        include_paths: list[str] = []
        import_paths: list[str] = []
        wrapper_path: str | None = None
        no_lint = False
        for line in file:
            if line.startswith("//!import "):
                import_paths.append("rtl/" + line[len("//!import") :].strip())
            elif line.startswith("//!include "):
                include_paths.append("rtl/" + line[len("//!include") :].strip())
            elif line.startswith("//!wrapper "):
                wrapper_path = "wrappers/" + line[len("//!wrapper") :].strip()
            elif line.startswith("//!no_lint"):
                no_lint = True
            elif line == "":
                pass
            else:
                break
        return include_paths, import_paths, wrapper_path, no_lint


class HeaderFile:
    """Describes dependencies of .svh files"""

    def __init__(self, path: str) -> None:
        self.path = path
        self.includes, _, _, _ = get_includes_imports(path)


class SourceFile:
    """Describes dependencies of .sv files"""

    def __init__(self, path: str) -> None:
        self.path = path
        self.includes, self.imports, self.wrapper, self.no_lint = get_includes_imports(
            path
        )
        self.dependencies: list[str] | None = None

    def _get_dependencies(
        self,
        source_files: dict[str, SourceFile],
        source_files_used: dict[str, SourceFile],
    ) -> list[str]:
        dependencies: list[str] = []
        # Add sub-dependencies to list
        for import_path in self.imports:
            if import_path in source_files:
                # pylint: disable-next=protected-access
                dependencies += source_files[import_path]._get_dependencies(
                    source_files, source_files_used
                )
            elif import_path in source_files_used:
                pass
            else:
                raise RuntimeError(f"File {import_path} not found!")
        # Add dependencies to list and indicate as used
        for import_path in self.imports:
            if import_path in source_files:
                source_files_used[import_path] = source_files[import_path]
                del source_files[import_path]
                dependencies += [import_path]
        # Add this file to the list and indicate as used
        if self.path in source_files:
            source_files_used[self.path] = source_files[self.path]
            del source_files[self.path]
            dependencies += [self.path]
        else:
            raise RuntimeError(
                f"File {self.path} already imported, likely circular dependency!"
            )
        return dependencies

    def get_dependencies(
        self, source_files: dict[str, SourceFile] | None = None
    ) -> list[str]:
        "Returns a list of all the SV dependencies listed in included order"
        if source_files is None and self.dependencies is None:
            error(
                f"{self.path} asked for dependencies without being given source files first!"
            )
        if self.dependencies is None:
            source_files_copy = cast(dict[str, SourceFile], copy.deepcopy(source_files))
            self.dependencies = self._get_dependencies(source_files_copy, {})
            if self.wrapper is not None:
                self.dependencies += [self.wrapper]
        return self.dependencies


def search_headers(path: str) -> dict[str, HeaderFile]:
    header_files: dict[str, HeaderFile] = {}
    for glob_path in glob.glob(os.path.join(path, "*.svh")):
        header_files[glob_path] = HeaderFile(glob_path)
    return header_files


def search_sources(path: str) -> dict[str, SourceFile]:
    source_files: dict[str, SourceFile] = {}
    for glob_path in glob.glob(os.path.join(path, "*.sv")):
        source_files[glob_path] = SourceFile(glob_path)
    return source_files


def build(
    run_tests: bool = False,
    wave: WaveFormat | None = None,
    wave_dir: Path = Path("build/waves"),
    rustdv_targets: tuple[str, ...] | None = None,
    output: bool = False,
) -> None:
    """Main function"""
    targets = select_targets(discover_targets(), rustdv_targets)
    rtl_folders: list[str] = [
        "rtl/std",
        "rtl/xilinx",
        "rtl/asic",
        "rtl/mem",
        "rtl/stream",
        "rtl/riscv",
        "rtl/gecko",
        "rtl/gecko/cores",
    ]
    build_path = Path("build")
    build_path.mkdir(parents=True, exist_ok=True)

    info("Finding RTL dependencies...")
    header_files: dict[str, HeaderFile] = {}
    source_files: dict[str, SourceFile] = {}
    for folder in rtl_folders:
        header_files = {**header_files, **search_headers(folder)}
        source_files = {**source_files, **search_sources(folder)}

    info("Verifying RTL dependencies...")
    for path, source_file in source_files.items():
        for include_path in source_file.includes:
            if include_path not in header_files:
                raise RuntimeError(
                    f"""File {path} includes {include_path} which does not exist!
                        {header_files.keys()}"""
                )
        for import_path in source_file.imports:
            if import_path not in source_files:
                raise RuntimeError(
                    f"""File {path} imports {import_path} which does not exist!
                        {source_files.keys()}"""
                )
    for source_file in source_files.values():
        source_file.get_dependencies(source_files=source_files)

    info("Linting RTL...")
    verilator_ninja_path = build_path / "verilator.ninja"
    with open(verilator_ninja_path, "w", encoding="utf-8") as ninja_file:
        write_verilator_ninja_rules(cast(str, ninja_file))
        for source_file in source_files.values():
            VerilatorLint(source_file).write_ninja_build(cast(str, ninja_file))

    subprocess.run(["ninja", "--quiet", "-f", str(verilator_ninja_path)], check=True)

    info("Building RustDV targets...")
    simulators = build_rustdv_targets(source_files, targets=targets, wave=wave)
    if run_tests:
        info("Running RustDV regressions...")
        run_rustdv_tests(
            targets=targets,
            simulators=simulators,
            output=output,
            wave=wave,
            wave_dir=wave_dir,
        )
