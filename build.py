#!/usr/bin/env python3
"""
Builds the RTL with verilator
"""

from __future__ import annotations

import os
import copy
import glob
import subprocess
from typing import Dict
from pathlib import Path

from util import debug, info, warning, error
from riscv import RiscvProgram


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

    def get_dependencies(self, source_files):
        dependencies = self._get_dependencies(copy.deepcopy(source_files), {})
        if self.wrapper is not None:
            dependencies += [self.wrapper]
        return dependencies


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
        "rtl/mem",
        "rtl/stream",
        "rtl/riscv",
        "rtl/gecko",
        "rtl/gecko/cores",
    ]
    top_level = ["rtl/gecko/cores/gecko_nano.sv"]

    # Make sure bin/ folder exists
    Path("bin/").mkdir(parents=True, exist_ok=True)

    # Make sure bin/riscv-tests/ folder exists
    Path("bin/riscv-tests/").mkdir(parents=True, exist_ok=True)

    print("Compiling test programs...")
    compiled_programs = {}
    compiled_programs["dhrystone"] = RiscvProgram(
        "dhrystone",
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

    assembled_programs = []
    assembled_programs.append(
        RiscvProgram(
            "basic",
            [
                "tests/lib/crt0.s",
                "tests/lib/libmem.c",
                "tests/lib/libio.c",
                "tests/basic/main.c",
            ],
            linker_script="tests/gecko_compiled.ld",
            opt="-O2",
        )
    )

    for path in glob.glob("riscv-tests/isa/rv32ui/*.S"):
        name = Path(path).stem
        assembled_programs.append(
            RiscvProgram(
                "riscv-tests/" + name,
                [path],
                linker_script="tests/gecko_assembled.ld",
                include_folders=["riscv-tests/isa/macros/scalar/", "tests/"],
            )
        )

    print("Finding RTL dependencies...")
    header_files = {}
    source_files = {}
    for folder in rtl_folders:
        header_files = {**header_files, **search_headers(folder)}
        source_files = {**source_files, **search_sources(folder)}

    print("Verifying RTL dependencies...")
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

    print("Running verilator...")
    for path, source_file in source_files.items():
        info(f"{path}...")
        sources = source_file.get_dependencies(source_files)

        module_name = path.split("/")[-1].split(".sv")[0]
        if source_file.no_lint:
            warning("Skipping linting due to //!no_lint...")
            continue
        # Run verilator
        try:
            param_args = []
            if path in top_level and len(compiled_programs) > 0:
                _, compiled_program = next(iter(compiled_programs.items()))
                param_args.append(
                    f"-GMEMORY_ADDR_WIDTH={compiled_program.address_width}"
                )
                param_args.append(
                    f'-GSTARTUP_PROGRAM="bin/{compiled_program.name}.mem"'
                )
                debug(f"Using param args: {param_args}")

            subprocess.run(
                [
                    os.path.expandvars("$VERILATOR_ROOT/bin/verilator"),
                    "--cc" if path in top_level else "-lint-only",
                    "--trace" if path in top_level else "",
                    "--trace-structs",
                    # "--trace-max-array",
                    # "1000000",
                    # "--trace-max-width",
                    # "1000000",
                    "--prefix",
                    "V" + module_name,
                    "-Irtl/",
                    '+define+__SYNTH_ONLY__=1"',
                ]
                + param_args
                + sources,
                capture_output=True,
                check=True,
            )
        except subprocess.CalledProcessError as process_error:
            error(f"Verilator failed to build file {path}!")
            for source in sources:
                print(f"\t{source}")
            print(process_error.output.decode("utf-8"))
            print(process_error.stderr.decode("utf-8"))
            raise process_error
        # Compile verilator output
        if path in top_level:
            cpp_file = "tb_cpp/" + path.split("rtl/")[-1].split(".sv")[0] + "_tb.cpp"
            try:
                subprocess.run(
                    [
                        "g++-11",
                        # os.path.expandvars("$LLVM_ROOT/bin/clang"),
                        "-Iobj_dir/",
                        os.path.expandvars("-I$VERILATOR_ROOT/include"),
                        cpp_file,
                        os.path.expandvars(
                            "$VERILATOR_ROOT/include/verilated_vcd_c.cpp"
                        ),
                        os.path.expandvars("$VERILATOR_ROOT/include/verilated.cpp"),
                        "obj_dir/V" + module_name + "__ALL.cpp",
                        # "-O2",
                        "-o",
                        "bin/" + module_name + "_simulator",
                    ],
                    capture_output=True,
                    check=True,
                )
            except subprocess.CalledProcessError as process_error:
                error(f"g++ failed to build file {cpp_file} (from {path})!")
                print(process_error.output.decode("utf-8"))
                print(process_error.stderr.decode("utf-8"))
                raise process_error


if __name__ == "__main__":
    main()
