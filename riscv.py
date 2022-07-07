#!/usr/bin/env python3
"Helper class for compiling RISCV programs"

import os
import subprocess

from util import debug, error, calculate_address_width, convert_hex_file


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
        self._compile()

    def _get_include_args(self):
        args = []
        if self.include_folders is not None:
            for folder in self.include_folders:
                args.append("-I" + folder)
        return args

    def _compile(self):
        try:
            subprocess.run(
                [
                    os.path.expandvars("$LLVM_ROOT/bin/clang"),
                    "--target=riscv32",
                    "-march=rv32i",
                    os.path.expandvars("--sysroot=$RISCV_GNU_ROOT/riscv64-unknown-elf"),
                    os.path.expandvars("--gcc-toolchain=$RISCV_GNU_ROOT"),
                ]
                + (["-T", self.linker_script] if self.linker_script is not None else [])
                + ([self.opt] if self.opt is not None else [])
                + [
                    "-nostartfiles",
                    "-o",
                    "bin/" + self.name + ".o",
                ]
                + self.get_build_files()
                + self._get_include_args(),
                capture_output=True,
                check=True,
            )
            subprocess.run(
                [
                    os.path.expandvars("$LLVM_ROOT/bin/llvm-objcopy"),
                    "-O",
                    "binary",
                    "bin/" + self.name + ".o",
                    "bin/" + self.name + ".bin",
                ],
                capture_output=True,
                check=True,
            )
            with open("bin/" + self.name + ".s", "w") as file:
                subprocess.run(
                    [
                        os.path.expandvars("$LLVM_ROOT/bin/llvm-objdump"),
                        "-d",
                        "bin/" + self.name + ".o",
                    ],
                    stdout=file,
                    check=True,
                )
            symbols = str(
                subprocess.check_output(
                    [
                        os.path.expandvars("$LLVM_ROOT/bin/llvm-objdump"),
                        "-t",
                        "bin/" + self.name + ".o",
                    ],
                    universal_newlines=True,
                )
            )
            for symbol_line in symbols.split("\n"):
                if "__stack" in symbol_line:
                    self.memory_size = int(symbol_line.split(" ")[0], 16)
                    self.address_width = calculate_address_width(self.memory_size)

        except subprocess.CalledProcessError as process_error:
            error(f"Clang failed to compile program {self.name}!")
            print(process_error.output.decode("utf-8"))
            print(process_error.stderr.decode("utf-8"))
            raise process_error

        self.program_size = convert_hex_file(
            "bin/" + self.name + ".bin", "bin/" + self.name + ".mem"
        )
        debug(
            f"""Compiled {self.name}:
                \t{self.program_size} bytes (Binary),
                \t{self.memory_size} bytes (Memory),
                \t{self.address_width} bits (Memory Address)"""
        )

    def get_build_files(self):
        "Returns the build files"
        return self.build_files

    def get_linker_script(self):
        "Returns the linker script"
        return self.linker_script
