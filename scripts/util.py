"""Various helper functions for building the project"""

from __future__ import annotations

import math
from collections.abc import Iterable
from os import PathLike
from typing import TextIO, Union

from colorama import Fore, Style

FilePath = Union[str, PathLike[str]]


def debug(msg: str, flush: bool = True, end: str = "\n") -> None:
    """Print colored debug message"""
    print("         " + msg, flush=flush, end=end)


def info(msg: str, flush: bool = True, end: str = "\n") -> None:
    """Print colored info message"""
    print(Fore.GREEN + "INFO:    " + Style.RESET_ALL + msg, flush=flush, end=end)


def warning(msg: str, flush: bool = True, end: str = "\n") -> None:
    """Print colored warning message"""
    print(Fore.YELLOW + "WARNING: " + Style.RESET_ALL + msg, flush=flush, end=end)


def error(msg: str, flush: bool = True, end: str = "\n") -> None:
    """Print colored error message"""
    print(Fore.RED + "ERROR:   " + Style.RESET_ALL + msg, flush=flush, end=end)


def convert_hex(src_file: Iterable[int], dest_file: TextIO) -> int:
    """Convert binary values to hex values readmemh can understand"""
    len_bytes = 0
    word = ""
    for src_byte in src_file:
        word = f"{src_byte:02x}{word}"
        if len(word) >= 8:
            dest_file.write(word + "\n")
            word = ""
        len_bytes += 1
    if len(word) > 0:
        dest_file.write(word + "\n")
    return len_bytes


def convert_hex_file(src_filename: FilePath, dest_filename: FilePath) -> int:
    """Convert binary file to hex file readmemh can understand"""
    with (
        open(src_filename, mode="rb") as src_file,
        open(dest_filename, mode="w", encoding="utf-8") as dest_file,
    ):
        return convert_hex(src_file.read(), dest_file)


def calculate_address_width(size_bytes: int) -> int:
    """Calculates memory address width required to store this many bytes"""
    return math.ceil(math.log2(size_bytes))
