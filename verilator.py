#!/usr/bin/env python3
"Helper class for compiling Verilator programs"

import os
import subprocess
from pathlib import Path
import multiprocessing
import time

from util import debug, info, warning, error


def _split_makefile_variable(line, global_file=False):
    variables = []
    line = line.split("+=")[1].strip()
    for variable in line.split(" "):
        if len(variable) == 0:
            continue
        variable = variable.strip()
        if global_file:
            variable = os.path.expandvars(f"$VERILATOR_ROOT/include/{variable}.cpp")
        else:
            variable = f"obj_dir/{variable}.cpp"
        variables.append(variable)
    return variables


def _wait_builds(builds, pending_builds=0):
    while len(builds) > pending_builds:
        for build_name, build_process in builds.items():
            if build_process.poll() is not None:
                if build_process.returncode != 0:
                    stdout, stderr = build_process.communicate()
                    stdout, stderr = stdout.decode("utf-8"), stderr.decode("utf-8")
                    error(f"g++ error compiling {build_name}!\n{stdout}\n{stderr}")
                    raise RuntimeError("Compiler error!")
                debug(f"{build_name}...")
                del builds[build_name]
                break
        time.sleep(0.01)


class VerilatorProgram:
    "Compiles Verilator testbenches from SystemVerilog sources"

    def __init__(self, source_file, lint_only=False, program=None) -> None:
        self.path = source_file.path
        self.module_name = self.path.split("/")[-1].split(".sv")[0]
        self.cpp_file = (
            "tb_cpp/" + self.path.split("rtl/")[-1].split(".sv")[0] + "_tb.cpp"
        )
        self.source_file = source_file
        self.lint_only = lint_only
        self.program = program
        self._verilate()
        if not self.lint_only:
            self._compile()

    def _verilate(self):
        # Run verilator
        if self.source_file.no_lint:
            warning("Skipping linting due to //!no_lint...")
            return

        try:
            param_args = []
            if self.program is not None:
                param_args.append(f"-GMEMORY_ADDR_WIDTH={self.program.address_width}")
                param_args.append(f'-GSTARTUP_PROGRAM="bin/{self.program.name}.mem"')
                debug(f"\tUsing param args: {param_args}")

            subprocess.run(
                [
                    os.path.expandvars("$VERILATOR_ROOT/bin/verilator"),
                    "--cc" if not self.lint_only else "-lint-only",
                    "--trace" if not self.lint_only else "",
                    "--trace-structs",
                    # "--trace-max-array",
                    # "1000000",
                    # "--trace-max-width",
                    # "1000000",
                    "--prefix",
                    "V" + self.module_name,
                    "-Irtl/",
                    '+define+__SYNTH_ONLY__=1"',
                ]
                + param_args
                + self.source_file.get_dependencies(),
                capture_output=True,
                check=True,
            )
        except subprocess.CalledProcessError as process_error:
            error(f"Verilator failed to build file {self.path}!")
            for source in self.source_file.get_dependencies():
                print(f"\t{source}")
            print(process_error.output.decode("utf-8"))
            print(process_error.stderr.decode("utf-8"))
            raise process_error

    def _compile(self):
        cpp_dependencies = self._parse_makefile()
        object_builds = {}
        object_paths = []
        objects_fast = ["classes_fast", "support_fast", "global_fast"]
        objects_slow = ["classes_slow", "support_slow", "global_slow"]
        max_builds = multiprocessing.cpu_count() // 2
        info(f"Building with {max_builds} processes...")

        # Build verilator object files
        for object_group in objects_fast + objects_slow:
            for source_path in cpp_dependencies[object_group]:
                source_name = Path(source_path).stem
                object_path = f"bin/{source_name}.o"
                object_builds[object_path] = subprocess.Popen(
                    [
                        "g++-11",
                        "-c",
                        "-Iobj_dir/",
                        os.path.expandvars("-I$VERILATOR_ROOT/include"),
                        source_path,
                        "-o",
                        object_path,
                    ]
                    + (["-O2"] if object_group in objects_fast else []),
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                )
                object_paths.append(object_path)
                _wait_builds(object_builds, pending_builds=max_builds - 1)
        _wait_builds(object_builds)

        # Compile verilator output
        try:
            subprocess.run(
                [
                    "g++-11",
                    # os.path.expandvars("$LLVM_ROOT/bin/clang"),
                    "-Iobj_dir/",
                    os.path.expandvars("-I$VERILATOR_ROOT/include"),
                    self.cpp_file,
                    "-O2",
                    "-o",
                    "bin/" + self.module_name + "_simulator",
                ]
                + object_paths,
                capture_output=True,
                check=True,
            )
        except subprocess.CalledProcessError as process_error:
            error(f"g++ failed to build file {self.cpp_file} (from {self.path})!")
            print(process_error.output.decode("utf-8"))
            print(process_error.stderr.decode("utf-8"))
            raise process_error

    def _parse_makefile(self):
        lines = []
        last_partial = False
        with open("obj_dir/V" + self.module_name + "_classes.mk", "r") as file:
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
            if line.startswith("VM_CLASSES_FAST"):
                files["classes_fast"] = _split_makefile_variable(line)
            elif line.startswith("VM_CLASSES_SLOW"):
                files["classes_slow"] = _split_makefile_variable(line)
            elif line.startswith("VM_SUPPORT_FAST"):
                files["support_fast"] = _split_makefile_variable(line)
            elif line.startswith("VM_SUPPORT_SLOW"):
                files["support_slow"] = _split_makefile_variable(line)
            elif line.startswith("VM_GLOBAL_FAST"):
                files["global_fast"] = _split_makefile_variable(line, global_file=True)
            elif line.startswith("VM_GLOBAL_SLOW"):
                files["global_slow"] = _split_makefile_variable(line, global_file=True)
        return files
