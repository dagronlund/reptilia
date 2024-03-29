#!/usr/bin/env python3
"""
Builds the RTL with verilator
"""

from __future__ import annotations

import os
import subprocess
import time
import copy
import glob
from typing import Dict
from pathlib import Path
from filecmp import cmp as filecmp
from shutil import copy as filecopy

from util import info, error
from riscv import RiscvProgram, write_riscv_ninja_rules
from verilator import (
    VerilatorProgram,
    write_verilator_ninja_rules,
    write_verilator_compile_ninja_rules,
)


def get_includes_imports(path):
    """Parses special comments in the file to find dependencies"""
    with open(path, "r") as file:
        include_paths = []
        import_paths = []
        wrapper_path = None
        no_lint = False
        for line in file.readlines():
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

    def __init__(self, path) -> None:
        self.path = path
        self.includes, _, _, _ = get_includes_imports(path)


class SourceFile:
    """Describes dependencies of .sv files"""

    def __init__(self, path) -> None:
        self.path = path
        self.includes, self.imports, self.wrapper, self.no_lint = get_includes_imports(
            path
        )
        self.dependencies = None

    def _get_dependencies(
        self,
        source_files: Dict[str, SourceFile],
        source_files_used: Dict[str, SourceFile],
    ):
        dependencies = []
        # Add sub-dependencies to list
        for import_path in self.imports:
            if import_path in source_files:
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

    def get_dependencies(self, source_files=None):
        "Returns a list of all the SV dependencies listed in included order"
        if source_files is None and self.dependencies is None:
            error(
                f"{self.path} asked for dependencies without being given source files first!"
            )
        if self.dependencies is None:
            self.dependencies = self._get_dependencies(copy.deepcopy(source_files), {})
            if self.wrapper is not None:
                self.dependencies += [self.wrapper]
        return self.dependencies


def search_headers(path):
    header_files = {}
    for glob_path in glob.glob(os.path.join(path, "*.svh")):
        header_files[glob_path] = HeaderFile(glob_path)
    return header_files


def search_sources(path):
    source_files = {}
    for glob_path in glob.glob(os.path.join(path, "*.sv")):
        source_files[glob_path] = SourceFile(glob_path)
    return source_files


def main():
    """Main function"""
    rtl_folders = [
        "rtl/std",
        "rtl/xilinx",
        "rtl/asic",
        "rtl/mem",
        "rtl/stream",
        "rtl/riscv",
        "rtl/gecko",
        "rtl/gecko/cores",
    ]
    top_level = ["rtl/gecko/cores/gecko_nano.sv"]

    # Make sure bin/ folder(s) exists
    Path("bin/").mkdir(parents=True, exist_ok=True)
    Path("bin/obj_dir").mkdir(parents=True, exist_ok=True)
    Path("bin/riscv-tests/").mkdir(parents=True, exist_ok=True)
    Path("bin/verilator/").mkdir(parents=True, exist_ok=True)

    riscv_programs = {}

    info("Compiling RISCV programs...")
    riscv_programs["dhrystone"] = RiscvProgram(
        "dhrystone/dhrystone",
        [
            "tests/lib/crt0.s",
            "tests/lib/libmem.c",
            "tests/lib/libio.c",
            "tests/dhrystone/dhrystone.c",
            "tests/dhrystone/dhrystone_main.c",
            "tests/dhrystone/main.c",
        ],
        linker_script="tests/gecko_compiled.ld",
        opt="-O2",
    )
    riscv_programs["basic"] = RiscvProgram(
        "basic/basic",
        [
            "tests/lib/crt0.s",
            "tests/lib/libmem.c",
            "tests/lib/libio.c",
            "tests/basic/main.c",
        ],
        linker_script="tests/gecko_compiled.ld",
        opt="-O2",
    )

    for path in glob.glob("riscv-tests/isa/rv32ui/*.S"):
        name = Path(path).stem
        riscv_programs[name] = RiscvProgram(
            "riscv-tests/" + name + "/" + name,
            [path],
            linker_script="tests/gecko_assembled.ld",
            include_folders=["riscv-tests/isa/macros/scalar/", "tests/"],
        )

    with open("build_riscv.ninja", "w") as ninja_file:
        write_riscv_ninja_rules(ninja_file)
        for program in riscv_programs.values():
            program.write_ninja_build(ninja_file)

    subprocess.run(
        ["ninja", "-f", "build_riscv.ninja"], capture_output=False, check=True
    )

    for program in riscv_programs.values():
        program.get_program_stats()
        # program.print_info()

    info("Finding RTL dependencies...")
    header_files = {}
    source_files = {}
    for folder in rtl_folders:
        header_files = {**header_files, **search_headers(folder)}
        source_files = {**source_files, **search_sources(folder)}

    info("Verifying RTL dependencies...")
    for path, source_file in source_files.items():
        for include_path in source_file.includes:
            if include_path not in header_files.keys():
                raise RuntimeError(
                    f"""File {path} includes {include_path} which does not exist!
                        {header_files.keys()}"""
                )
        for import_path in source_file.imports:
            if import_path not in source_files.keys():
                raise RuntimeError(
                    f"""File {path} imports {import_path} which does not exist!
                        {source_files.keys()}"""
                )
    for _, source_file in source_files.items():
        source_file.get_dependencies(source_files=source_files)

    info("Verilating RTL...")
    verilated = []
    with open("build_verilator.ninja", "w") as ninja_file:
        write_verilator_ninja_rules(ninja_file)
        for path, source_file in source_files.items():
            lint_only = path not in top_level
            verilator_args = None
            if not lint_only and len(riscv_programs) > 0:
                _, program = next(iter(riscv_programs.items()))
                verilator_args = [f"-GMEMORY_ADDR_WIDTH={program.address_width}"]
            v = VerilatorProgram(source_file, lint_only=lint_only)
            v.write_ninja_build_verilate(ninja_file, verilator_args=verilator_args)
            if not lint_only:
                verilated.append(v)

    subprocess.run(
        ["ninja", "-f", "build_verilator.ninja"],
        capture_output=False,
        check=True,
    )

    info("Merging obj_dir...")
    for path in Path("obj_dir").rglob("*.*"):
        new_path = Path("bin") / path
        if not new_path.is_file() or not filecmp(str(path), str(new_path)):
            filecopy(str(path), str(new_path))

    info("Compiling RTL...")
    with open("build_verilator_compile.ninja", "w") as ninja_file:
        write_verilator_compile_ninja_rules(ninja_file)
        for v in verilated:
            v.write_ninja_build_verilate_compile(ninja_file)

    start = time.time()
    subprocess.run(
        ["ninja", "-f", "build_verilator_compile.ninja", "-v"],
        capture_output=False,
        check=True,
    )
    duration = time.time() - start
    print(f"Time: {duration:.3}s...")


if __name__ == "__main__":
    main()
