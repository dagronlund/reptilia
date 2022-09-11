#!/usr/bin/env python3
"Helper class for compiling Verilator programs"

import os
from pathlib import Path

from ninja.misc.ninja_syntax import Writer as NinjaWriter


def _split_makefile_variable(line, global_file=False):
    variables = []
    line = line.split("+=")[1].strip()
    for variable in line.split(" "):
        if len(variable) == 0:
            continue
        variable = variable.strip()
        if global_file:
            variable = os.path.expandvars(f"verilator/include/{variable}.cpp")
        else:
            variable = f"obj_dir/{variable}.cpp"
        variables.append(variable)
    return variables


def write_verilator_ninja_rules(writer):
    ninja_writer = NinjaWriter(writer)
    ninja_writer.comment("Rules for Verilator verilation")

    # Set environment variable that verilator uses
    verilator = "VERILATOR_ROOT=verilator/ verilator/bin/verilator"

    flags = "--prefix V$name -Irtl/ +define+__SYNTH_ONLY__=1"
    trace = "--trace --trace-structs --output-split 10000"
    # "--trace-max-array 1000000 --trace-max-width 1000000"

    # Create rule for linting SystemVerilog modules
    ninja_writer.rule(
        name="verilator_lint",
        command=f"{verilator} -lint-only {flags} $in > $out",
    )

    # Create rule for verilating SystemVerilog modules
    ninja_writer.rule(
        name="verilator_verilate",
        command=f"{verilator} --cc {trace} {flags} $args $in > $out",
    )

    ninja_writer.newline()


def write_verilator_compile_ninja_rules(writer):
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

    includes = "-Ibin/obj_dir/ -Iverilator/include -Iverilator/include/vltstd"

    # Create rule for compiling verilated source code
    ninja_writer.rule(
        name="verilator_compile",
        command=f"g++-11 {includes} {flags} $args -c $in -o $out -MMD -MF $out.d",
        depfile="$out.d",
    )

    # Create rule for linking verilated source code
    ninja_writer.rule(
        name="verilator_link",
        command=f"g++-11 {includes} $args $in -o $out",
    )

    ninja_writer.newline()


class VerilatorProgram:
    "Compiles Verilator testbenches from SystemVerilog sources"

    def __init__(self, source_file, lint_only=False) -> None:
        self.path = source_file.path
        self.module_name = self.path.split("/")[-1].split(".sv")[0]
        self.cpp_file = (
            "tb_cpp/" + self.path.split("rtl/")[-1].split(".sv")[0] + "_tb.cpp"
        )
        self.source_file = source_file
        self.lint_only = lint_only

    def _parse_makefile(self):
        lines = []
        last_partial = False
        with open(f"obj_dir/V{self.module_name}_classes.mk", "r") as file:
            for line in file.readlines():
                line = line.strip()
                if len(line) > 0 and line[0] == "#":
                    continue
                if last_partial:
                    line = lines.pop() + " " + line
                last_partial = line.endswith("\\")
                if last_partial:
                    line = line.split("\\")[0]
                lines.append(line.strip())
        files = {}
        for line in lines:
            categories = [
                "VM_CLASSES_FAST",
                "VM_CLASSES_SLOW",
                "VM_SUPPORT_FAST",
                "VM_SUPPORT_SLOW",
            ]
            global_categories = ["VM_GLOBAL_FAST", "VM_GLOBAL_SLOW"]
            for category in categories:
                if line.startswith(category):
                    files[category] = (False, _split_makefile_variable(line))
            for category in global_categories:
                if line.startswith(category):
                    files[category] = (
                        True,
                        _split_makefile_variable(line, global_file=True),
                    )
        return files

    def write_ninja_build_verilate(self, writer, verilator_args=None):
        "Writes the ninja rules for verilating this module"
        if self.source_file.no_lint:
            return

        ninja_writer = NinjaWriter(writer)
        ninja_writer.comment(f"Build steps for {self.module_name}")

        if verilator_args is None:
            verilator_args = []

        log_path = Path(f"bin/lint/{self.path}").with_suffix(".log")
        ninja_writer.build(
            outputs=str(log_path),
            rule="verilator_lint" if self.lint_only else "verilator_verilate",
            inputs=self.source_file.get_dependencies(),
            variables={"name": self.module_name, "args": " ".join(verilator_args)},
        )

        ninja_writer.newline()

    def write_ninja_build_verilate_compile(self, writer):
        "Writes the ninja rules for compiling a verilated model"

        ninja_writer = NinjaWriter(writer)
        ninja_writer.comment(f"Build steps for {self.module_name}")

        cpp_dependencies = self._parse_makefile()
        categories_fast = ["VM_CLASSES_FAST", "VM_SUPPORT_FAST", "VM_GLOBAL_FAST"]
        categories_slow = ["VM_CLASSES_SLOW", "VM_SUPPORT_SLOW", "VM_GLOBAL_SLOW"]

        object_paths = []
        for object_group in categories_fast + categories_slow:
            is_global, source_paths = cpp_dependencies[object_group]
            for source_path in source_paths:
                # Determine where the source file is and where the destination object file is
                if is_global:
                    source_path = Path(source_path)
                    object_path = Path(f"bin/obj_dir/{source_path.stem}.o")
                else:
                    source_path = Path("bin") / Path(source_path)
                    object_path = Path(source_path).with_suffix(".o")

                ninja_writer.build(
                    outputs=str(object_path),
                    rule="verilator_compile",
                    inputs=str(source_path),
                    variables={
                        "args": "-O2" if object_group in categories_fast else ""
                    },
                )
                object_paths.append(str(object_path))

        ninja_writer.build(
            outputs=f"bin/{self.module_name}_simulator",
            rule="verilator_link",
            inputs=object_paths + [self.cpp_file],
            variables={"args": "-O2"},
        )

        ninja_writer.newline()
