#!/usr/bin/env python3
"Helper class for compiling RISCV programs"

import os
from pathlib import Path

from ninja.misc.ninja_syntax import Writer as NinjaWriter

from util import debug, calculate_address_width, convert_hex_file


def write_riscv_ninja_rules(writer):
    ninja_writer = NinjaWriter(writer)
    ninja_writer.comment("Rules for RISCV compilation")

    clang_path = os.path.expandvars("$LLVM_ROOT/bin")
    riscv_gnu_path = os.path.expandvars("$RISCV_GNU_ROOT")
    command = f"{clang_path}/clang --target=riscv32 -march=rv32i"
    command += f" --sysroot={riscv_gnu_path}/riscv64-unknown-elf"
    command += f" --gcc-toolchain={riscv_gnu_path}"
    command += " $opt"
    command += " $includes"

    # Create rule for assembling RISCV object files
    ninja_writer.rule(
        name="riscv_assemble",
        command=f"{command} -o $out -c $in -Wno-unused-command-line-argument",
    )

    # Create rule for compiling RISCV object files
    ninja_writer.rule(
        name="riscv_compile",
        command=f"{command} -o $out -c $in -Wno-unused-command-line-argument -MMD -MF $out.d",
        depfile="$out.d",
    )

    # Create rule for linking RISCV object files together
    ninja_writer.rule(
        name="riscv_link",
        command=f"{command} -T $linker -nostartfiles -o $out $in",
    )

    # Create rule for converting object files to raw binaries
    ninja_writer.rule(
        name="riscv_objcopy",
        command=f"{clang_path}/llvm-objcopy -O binary $in $out",
    )

    # Create rule for dissassembling object files
    ninja_writer.rule(
        name="riscv_objdump",
        command=f"{clang_path}/llvm-objdump -d $in > $out",
    )

    # Create rule for extracting symbols from object files
    ninja_writer.rule(
        name="riscv_objdump_symbols",
        command=f"{clang_path}/llvm-objdump -t $in > $out",
    )

    ninja_writer.newline()


class RiscvProgram:
    "Compiles RISCV programs using clang"

    def __init__(
        self, name, build_files, linker_script=None, include_folders=None, opt=None
    ) -> None:
        self.name = name
        self.build_files = build_files
        self.linker_script = linker_script
        self.include_folders = include_folders
        self.opt = opt
        self.program_size = None
        self.memory_size = None
        self.address_width = None

    def _get_include_args(self):
        args = []
        if self.include_folders is not None:
            for folder in self.include_folders:
                args.append("-I" + folder)
        return args

    def print_info(self):
        debug(
            f"""{self.name}:
                \t{self.program_size} bytes (Binary),
                \t{self.memory_size} bytes (Memory),
                \t{self.address_width} bits (Memory Address)"""
        )

    def get_program_stats(self):
        with open(f"bin/{self.name}.symbols", "r") as file:
            for line in file.readlines():
                if "__stack" in line:
                    self.memory_size = int(line.split(" ")[0], 16)
                    self.address_width = calculate_address_width(self.memory_size)

        self.program_size = convert_hex_file(
            "bin/" + self.name + ".bin", "bin/" + self.name + ".mem"
        )

    def get_build_files(self):
        "Returns the build files"
        return self.build_files

    def get_linker_script(self):
        "Returns the linker script"
        return self.linker_script

    def write_ninja_build(self, writer):
        "Writes the ninja rules for building this program"
        ninja_writer = NinjaWriter(writer)
        ninja_writer.comment(f"Build steps for {self.name}")

        object_files = []
        for build_file in self.build_files:
            object_file = Path(f"bin/{self.name}/{build_file}").with_suffix(".o")
            ninja_writer.build(
                outputs=str(object_file),
                rule="riscv_assemble"
                if Path(f"{build_file}").suffix in [".s", ".S"]
                else "riscv_compile",
                inputs=build_file,
                variables={
                    "opt": self.opt,
                    "includes": " ".join(self._get_include_args()),
                },
            )
            object_files.append(str(object_file))

        ninja_writer.build(
            outputs=f"bin/{self.name}.o",
            rule="riscv_link",
            inputs=object_files,
            variables={"linker": f"{self.linker_script}", "opt": self.opt},
            implicit=[f"{self.linker_script}"],
        )
        ninja_writer.build(
            outputs=f"bin/{self.name}.bin",
            rule="riscv_objcopy",
            inputs=f"bin/{self.name}.o",
        )
        ninja_writer.build(
            outputs=f"bin/{self.name}.s",
            rule="riscv_objdump",
            inputs=f"bin/{self.name}.o",
        )
        ninja_writer.build(
            outputs=f"bin/{self.name}.symbols",
            rule="riscv_objdump_symbols",
            inputs=f"bin/{self.name}.o",
        )

        ninja_writer.newline()
