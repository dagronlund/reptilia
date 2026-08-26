"""Helper class for compiling RISCV programs"""

from __future__ import annotations

from collections.abc import Sequence
from pathlib import Path

from ninja.ninja_syntax import Writer as NinjaWriter

from .environment import (
    discover_riscv_gcc,
    discover_riscv_objcopy,
    discover_riscv_objdump,
)
from .util import calculate_address_width, convert_hex_file, debug


def write_riscv_ninja_rules(writer: str) -> None:
    ninja_writer = NinjaWriter(writer)
    ninja_writer.comment("Rules for RISCV compilation")

    gcc_path = discover_riscv_gcc()
    objcopy_path = discover_riscv_objcopy()
    objdump_path = discover_riscv_objdump()
    command = f"{gcc_path} -march=rv32i -mabi=ilp32 -misa-spec=2.2"
    command += " $opt"
    command += " $includes"

    # Create rule for assembling RISCV object files
    ninja_writer.rule(
        name="riscv_assemble",
        command=f"{command} -o $out -c $in",
    )

    # Create rule for compiling RISCV object files
    ninja_writer.rule(
        name="riscv_compile",
        command=f"{command} -o $out -c $in -MMD -MF $out.d",
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
        command=f"{objcopy_path} -O binary $in $out",
    )

    # Create rule for dissassembling object files
    ninja_writer.rule(
        name="riscv_objdump",
        command=f"{objdump_path} -d $in > $out",
    )

    # Create rule for extracting symbols from object files
    ninja_writer.rule(
        name="riscv_objdump_symbols",
        command=f"{objdump_path} -t $in > $out",
    )

    ninja_writer.newline()


class RiscvProgram:
    "Compiles RISCV programs using the GNU toolchain"

    def __init__(
        self,
        name: str,
        build_files: Sequence[str],
        linker_script: str | None = None,
        include_folders: Sequence[str] | None = None,
        opt: str | None = None,
    ) -> None:
        self.name = name
        self.build_files = build_files
        self.linker_script = linker_script
        self.include_folders = include_folders
        self.opt = opt
        self.program_size: int | None = None
        self.memory_size: int | None = None
        self.address_width: int | None = None

    def _get_include_args(self) -> list[str]:
        args: list[str] = []
        if self.include_folders is not None:
            for folder in self.include_folders:
                args.append("-I" + folder)
        return args

    def print_info(self) -> None:
        debug(f"""{self.name}:
                \t{self.program_size} bytes (Binary),
                \t{self.memory_size} bytes (Memory),
                \t{self.address_width} bits (Memory Address)""")

    def get_program_stats(self) -> None:
        with open(f"build/{self.name}.symbols", "r", encoding="utf-8") as file:
            for line in file:
                if "__stack" in line:
                    self.memory_size = int(line.split(" ")[0], 16)
                    self.address_width = calculate_address_width(self.memory_size)

        self.program_size = convert_hex_file(
            "build/" + self.name + ".bin", "build/" + self.name + ".mem"
        )

    def get_build_files(self) -> Sequence[str]:
        "Returns the build files"
        return self.build_files

    def get_linker_script(self) -> str | None:
        "Returns the linker script"
        return self.linker_script

    def write_ninja_build(self, writer: str) -> None:
        "Writes the ninja rules for building this program"
        ninja_writer = NinjaWriter(writer)
        ninja_writer.comment(f"Build steps for {self.name}")

        opt_map = {"opt": self.opt} if self.opt is not None else {}

        object_files: list[str] = []
        for build_file in self.build_files:
            object_file = Path(f"build/{self.name}/{build_file}").with_suffix(".o")
            object_file.parent.mkdir(parents=True, exist_ok=True)
            ninja_writer.build(
                outputs=[str(object_file)],
                rule=(
                    "riscv_assemble"
                    if Path(f"{build_file}").suffix in [".s", ".S"]
                    else "riscv_compile"
                ),
                inputs=[build_file],
                variables={
                    "includes": " ".join(self._get_include_args()),
                }
                | opt_map,
            )
            object_files.append(str(object_file))

        ninja_writer.build(
            outputs=[f"build/{self.name}.o"],
            rule="riscv_link",
            inputs=object_files,
            variables={"linker": f"{self.linker_script}"} | opt_map,
            implicit=[f"{self.linker_script}"],
        )
        ninja_writer.build(
            outputs=[f"build/{self.name}.bin"],
            rule="riscv_objcopy",
            inputs=[f"build/{self.name}.o"],
        )
        ninja_writer.build(
            outputs=[f"build/{self.name}.s"],
            rule="riscv_objdump",
            inputs=[f"build/{self.name}.o"],
        )
        ninja_writer.build(
            outputs=[f"build/{self.name}.symbols"],
            rule="riscv_objdump_symbols",
            inputs=[f"build/{self.name}.o"],
        )

        ninja_writer.newline()
