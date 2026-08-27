"""
Builds the RTL with verilator
"""

from __future__ import annotations

import copy
import glob
import os
import subprocess
import time
from pathlib import Path
from typing import cast

from .riscv import (
    RiscvProgram,
    write_riscv_ninja_rules,
    write_riscv_test_ninja,
)
from .rustdv import WaveFormat
from .rustdv import run_rustdv_tests as run_rustdv_regression
from .util import error, info
from .verilator import (
    VerilatorProgram,
    write_verilator_compile_ninja_rules,
    write_verilator_ninja_rules,
)

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


def main(
    run_riscv_tests: bool = False,
    run_dhrystone: bool = False,
    run_rustdv_tests: bool = False,
    wave: WaveFormat | None = None,
    wave_dir: Path = Path("build/waves"),
) -> None:
    """Main function"""
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
    top_level: list[str] = ["rtl/gecko/cores/gecko_nano.sv"]

    # Make sure the build folder exists
    build_path = Path("build")
    build_path.mkdir(parents=True, exist_ok=True)
    (build_path / "obj_dir").mkdir(parents=True, exist_ok=True)

    riscv_programs: dict[str, RiscvProgram] = {}

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

    riscv_ninja_path = build_path / "riscv.ninja"
    with open(riscv_ninja_path, "w", encoding="utf-8") as ninja_file:
        write_riscv_ninja_rules(cast(str, ninja_file))
        for program in riscv_programs.values():
            program.write_ninja_build(cast(str, ninja_file))

    subprocess.run(
        ["ninja", "-f", str(riscv_ninja_path)], capture_output=False, check=True
    )

    for program in riscv_programs.values():
        program.get_program_stats()
        # program.print_info()

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

    info("Verilating RTL...")
    verilated: list[VerilatorProgram] = []
    verilator_ninja_path = build_path / "verilator.ninja"
    with open(verilator_ninja_path, "w", encoding="utf-8") as ninja_file:
        write_verilator_ninja_rules(cast(str, ninja_file))
        for path, source_file in source_files.items():
            lint_only = path not in top_level
            verilator_args: list[str] | None = None
            if not lint_only and len(riscv_programs) > 0:
                _, program = next(iter(riscv_programs.items()))
                verilator_args = [f"-GMEMORY_ADDR_WIDTH={program.address_width}"]
            v = VerilatorProgram(source_file, lint_only=lint_only)
            v.write_ninja_build_verilate(
                cast(str, ninja_file), verilator_args=verilator_args
            )
            if not lint_only:
                verilated.append(v)

    subprocess.run(
        ["ninja", "-f", str(verilator_ninja_path)],
        capture_output=False,
        check=True,
    )

    info("Compiling RTL...")
    verilator_compile_ninja_path = build_path / "verilator_compile.ninja"
    with open(verilator_compile_ninja_path, "w", encoding="utf-8") as ninja_file:
        write_verilator_compile_ninja_rules(cast(str, ninja_file))
        for v in verilated:
            v.write_ninja_build_verilate_compile(cast(str, ninja_file))

    start = time.time()
    subprocess.run(
        ["ninja", "-f", str(verilator_compile_ninja_path), "-v"],
        capture_output=False,
        check=True,
    )
    duration = time.time() - start
    print(f"Time: {duration:.3}s...")

    if run_riscv_tests or run_dhrystone:
        info("Running programs against the Gecko simulator...")
        riscv_test_ninja_path = build_path / "riscv_test.ninja"
        simulator = "build/gecko_nano_simulator"
        # Gecko does not implement FENCE.I or misaligned data accesses.
        skipped_isa_tests = {"fence_i", "ma_data"}
        test_programs: list[RiscvProgram] = []
        if run_riscv_tests:
            test_programs.extend(
                program
                for name, program in riscv_programs.items()
                if name not in {"basic", "dhrystone"} | skipped_isa_tests
            )
        if run_dhrystone:
            test_programs.append(riscv_programs["dhrystone"])
        with open(riscv_test_ninja_path, "w", encoding="utf-8") as ninja_file:
            write_riscv_test_ninja(cast(str, ninja_file), test_programs, simulator)
        subprocess.run(
            ["ninja", "-f", str(riscv_test_ninja_path), "-k", "0"],
            capture_output=False,
            check=True,
        )

    if run_rustdv_tests:
        info("Running rustdv memory/stream regressions...")
        run_rustdv_regression(
            source_files,
            wave=wave,
            wave_dir=wave_dir,
        )


if __name__ == "__main__":
    main()
