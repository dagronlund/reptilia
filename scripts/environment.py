"""Helpers for discovering tools in the build environment."""

import shutil
import subprocess
from pathlib import Path


def find_executable(name: str) -> Path:
    """Return the resolved path to an executable available on PATH."""
    path_string = shutil.which(name)
    if path_string is None:
        raise RuntimeError(f"{name} was not found on PATH")
    return Path(path_string).resolve()


def discover_riscv_gcc() -> Path:
    """Discover the RISC-V GNU gcc compiler"""
    return find_executable("riscv64-unknown-elf-gcc")


def discover_riscv_objcopy() -> Path:
    """Discover the RISC-V GNU objcopy utility"""
    return find_executable("riscv64-unknown-elf-objcopy")


def discover_riscv_objdump() -> Path:
    """Discover the RISC-V GNU objdump utility"""
    return find_executable("riscv64-unknown-elf-objdump")


def discover_verilator() -> Path:
    """Discover the Verilator tool"""
    return find_executable("verilator")


def get_verilator_root(verilator: Path) -> Path:
    """Return the runtime root reported by a Verilator executable."""
    root_string = subprocess.check_output(
        [verilator, "--getenv", "VERILATOR_ROOT"], text=True
    ).strip()
    if not root_string:
        raise RuntimeError(f"{verilator} did not report VERILATOR_ROOT")

    root = Path(root_string).resolve()
    if not (root / "include").is_dir():
        raise RuntimeError(f"Verilator include directory was not found under {root}")
    return root
