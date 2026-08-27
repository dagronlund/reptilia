"""Helper class for compiling Verilator programs"""

from __future__ import annotations

import platform
import shlex
import subprocess
from collections.abc import Sequence
from dataclasses import dataclass
from pathlib import Path
from typing import Protocol, cast

from ninja.ninja_syntax import Writer as NinjaWriter

from .environment import discover_verilator, get_verilator_root


class _SourceFile(Protocol):
    path: str
    no_lint: bool

    def get_dependencies(self) -> list[str]: ...


MakefileSources = dict[str, tuple[bool, list[str]]]

_FAST_CATEGORIES = (
    "VM_CLASSES_FAST",
    "VM_SUPPORT_FAST",
    "VM_GLOBAL_FAST",
)
_SLOW_CATEGORIES = (
    "VM_CLASSES_SLOW",
    "VM_SUPPORT_SLOW",
    "VM_GLOBAL_SLOW",
)
_GLOBAL_CATEGORIES = {
    "VM_GLOBAL_FAST",
    "VM_GLOBAL_SLOW",
}
_MODEL_SWITCHES = (
    "VM_COVERAGE",
    "VM_TIMING",
    "VM_TRACE",
    "VM_TRACE_FST",
    "VM_TRACE_SAIF",
    "VM_TRACE_VCD",
    "VM_VPI",
)


def _split_makefile_variable(line: str, source_directory: Path) -> list[str]:
    variables: list[str] = []
    line = line.split("+=")[1].strip()
    for variable in line.split(" "):
        if len(variable) == 0:
            continue
        variable = variable.strip()
        variables.append(str(source_directory / f"{variable}.cpp"))
    return variables


def _read_classes_makefile(
    model_directory: Path, prefix: str
) -> tuple[MakefileSources, dict[str, int]]:
    include_path = get_verilator_root(discover_verilator()) / "include"
    lines: list[str] = []
    last_partial = False
    with (model_directory / f"{prefix}_classes.mk").open(
        "r", encoding="utf-8"
    ) as makefile:
        for raw_line in makefile:
            line = raw_line.strip()
            if line.startswith("#"):
                continue
            if last_partial:
                line = lines.pop() + " " + line
            last_partial = line.endswith("\\")
            if last_partial:
                line = line[:-1]
            lines.append(line.strip())

    files: MakefileSources = {}
    switches: dict[str, int] = {}
    for line in lines:
        for category in _FAST_CATEGORIES + _SLOW_CATEGORIES:
            if line.startswith(f"{category} +="):
                is_global = category in _GLOBAL_CATEGORIES
                directory = include_path if is_global else model_directory
                files[category] = (
                    is_global,
                    _split_makefile_variable(line, directory),
                )
        for switch in _MODEL_SWITCHES:
            if line.startswith(f"{switch} ="):
                switches[switch] = int(line.split("=", maxsplit=1)[1].strip())

    for category in _FAST_CATEGORIES + _SLOW_CATEGORIES:
        files.setdefault(category, (category in _GLOBAL_CATEGORIES, []))
    for switch in _MODEL_SWITCHES:
        switches.setdefault(switch, 0)
    return files, switches


def write_verilator_ninja_rules(writer: str) -> None:
    ninja_writer = NinjaWriter(writer)
    ninja_writer.comment("Rules for Verilator verilation")

    verilator = shlex.quote(str(discover_verilator()))

    flags = "--prefix V$name -Irtl/ +define+__SYNTH_ONLY__=1"
    trace = "--trace --trace-structs --output-split 10000 --trace-max-array 1000000"
    # " --trace-max-width 1000000"

    # Create rule for linting SystemVerilog modules
    ninja_writer.rule(
        name="verilator_lint",
        command=f"{verilator} -lint-only {flags} $in > $out",
    )

    # Create rule for verilating SystemVerilog modules
    ninja_writer.rule(
        name="verilator_verilate",
        command=(
            f"{verilator} --cc --Mdir build/obj_dir {trace} "
            f"{flags} $args $in > $out"
        ),
    )

    ninja_writer.newline()


def write_verilator_compile_ninja_rules(writer: str) -> None:
    ninja_writer = NinjaWriter(writer)
    ninja_writer.comment("Rules for Verilator compilation")

    flags = ""
    flags += " -Wno-bool-operation"
    flags += " -Wno-parentheses-equality"
    flags += " -Wno-tautological-bitwise-compare"
    flags += " -Wno-sign-compare"
    flags += " -Wno-uninitialized"
    flags += " -Wno-unused-parameter"
    flags += " -Wno-unused-variable"
    flags += " -Wno-shadow"
    flags += " -Wc++11-extensions"

    # Create rule for compiling verilated source code
    ninja_writer.rule(
        name="verilator_compile",
        command=(
            f"g++ $includes $defines $standard {flags} $args "
            "-c $in -o $out -MMD -MF $out.d"
        ),
        depfile="$out.d",
    )

    # Create rule for linking verilated source code
    ninja_writer.rule(
        name="verilator_link",
        command="g++ $in -o $out $args",
    )

    ninja_writer.newline()


@dataclass(frozen=True)
class VerilatorModel:
    """Verilate, manually compile, and link one C++ model executable."""

    prefix: str
    model_directory: Path
    executable: Path
    cpp_files: tuple[Path, ...]
    compile_flags: tuple[str, ...] = ()
    link_flags: tuple[str, ...] = ()

    def verilate(
        self, sources: Sequence[str], verilator_args: Sequence[str] = ()
    ) -> None:
        self.model_directory.mkdir(parents=True, exist_ok=True)
        subprocess.run(
            [
                str(discover_verilator()),
                "--cc",
                "--prefix",
                self.prefix,
                "--Mdir",
                str(self.model_directory),
                *verilator_args,
                *sources,
            ],
            check=True,
        )

    def write_ninja_build_compile(self, writer: str) -> None:
        ninja_writer = NinjaWriter(writer)
        ninja_writer.comment(f"Compile and link {self.prefix}")
        sources, switches = _read_classes_makefile(self.model_directory, self.prefix)
        include_path = get_verilator_root(discover_verilator()) / "include"
        includes = " ".join(
            shlex.quote(f"-I{path}")
            for path in (self.model_directory, include_path, include_path / "vltstd")
        )
        definitions = {
            "VM_SC": 0,
            **switches,
        }
        defines = " ".join(f"-D{name}={value}" for name, value in definitions.items())
        standard = "-std=c++20" if switches["VM_TIMING"] else "-std=c++17"
        compile_flags = " ".join(shlex.quote(flag) for flag in self.compile_flags)

        object_paths: list[str] = []
        for category in _FAST_CATEGORIES + _SLOW_CATEGORIES:
            _, source_paths = sources[category]
            for source_path_string in source_paths:
                source_path = Path(source_path_string)
                object_path = self.model_directory / f"{source_path.stem}.o"
                optimization = "-O2" if category in _FAST_CATEGORIES else ""
                ninja_writer.build(
                    outputs=[str(object_path)],
                    rule="verilator_compile",
                    inputs=[str(source_path)],
                    variables={
                        "includes": includes,
                        "defines": defines,
                        "standard": standard,
                        "args": " ".join(
                            flag for flag in (optimization, compile_flags) if flag
                        ),
                    },
                )
                object_paths.append(str(object_path))

        for index, cpp_file in enumerate(self.cpp_files):
            object_path = self.model_directory / f"user_{index}_{cpp_file.stem}.o"
            ninja_writer.build(
                outputs=[str(object_path)],
                rule="verilator_compile",
                inputs=[str(cpp_file)],
                variables={
                    "includes": includes,
                    "defines": defines,
                    "standard": standard,
                    "args": compile_flags,
                },
            )
            object_paths.append(str(object_path))

        linker_flags = list(self.link_flags)

        def add_link_flags(*flags: str) -> None:
            for flag in flags:
                if flag not in linker_flags:
                    linker_flags.append(flag)

        add_link_flags("-pthread", "-lpthread")
        if platform.system() == "Darwin":
            add_link_flags(
                "-Wl,-U,__Z15vl_time_stamp64v,-U,__Z13sc_time_stampv,-U,_vlog_startup_routines"
            )
        if switches["VM_VPI"]:
            add_link_flags("-rdynamic", "-ldl")
        if switches["VM_TRACE_FST"]:
            add_link_flags("-llz4", "-lz")
        ninja_writer.build(
            outputs=[str(self.executable)],
            rule="verilator_link",
            inputs=object_paths,
            variables={"args": " ".join(shlex.quote(flag) for flag in linker_flags)},
        )
        ninja_writer.newline()

    def build(self) -> None:
        ninja_path = self.model_directory / f"{self.prefix}_compile.ninja"
        with ninja_path.open("w", encoding="utf-8") as ninja_file:
            write_verilator_compile_ninja_rules(cast(str, ninja_file))
            self.write_ninja_build_compile(cast(str, ninja_file))
        subprocess.run(["ninja", "-f", str(ninja_path)], check=True)


class VerilatorProgram:
    "Compiles Verilator testbenches from SystemVerilog sources"

    def __init__(self, source_file: _SourceFile, lint_only: bool = False) -> None:
        self.path = source_file.path
        self.module_name = self.path.split("/")[-1].split(".sv")[0]
        self.cpp_file = f"cpp/{Path(self.path).stem}_tb.cpp"
        self.source_file = source_file
        self.lint_only = lint_only

    def write_ninja_build_verilate(
        self, writer: str, verilator_args: Sequence[str] | None = None
    ) -> None:
        "Writes the ninja rules for verilating this module"
        if self.source_file.no_lint:
            return

        ninja_writer = NinjaWriter(writer)
        ninja_writer.comment(f"Build steps for {self.module_name}")

        if verilator_args is None:
            verilator_args = []

        log_path = Path(f"build/lint/{self.path}").with_suffix(".log")
        log_path.parent.mkdir(parents=True, exist_ok=True)
        ninja_writer.build(
            outputs=[str(log_path)],
            rule="verilator_lint" if self.lint_only else "verilator_verilate",
            inputs=self.source_file.get_dependencies(),
            variables={"name": self.module_name, "args": " ".join(verilator_args)},
        )

        ninja_writer.newline()

    def write_ninja_build_verilate_compile(self, writer: str) -> None:
        "Writes the ninja rules for compiling a verilated model"
        VerilatorModel(
            prefix=f"V{self.module_name}",
            model_directory=Path("build/obj_dir"),
            executable=Path(f"build/{self.module_name}_simulator"),
            cpp_files=(Path(self.cpp_file),),
        ).write_ninja_build_compile(writer)
