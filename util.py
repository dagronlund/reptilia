#!/usr/bin/env python3
"Various helper functions for building the project"

import math

from colorama import Fore, Style


def debug(msg, flush=True, end="\n"):
    "Print colored debug message"
    print("         " + msg, flush=flush, end=end)


def info(msg, flush=True, end="\n"):
    "Print colored info message"
    print(Fore.GREEN + "INFO:    " + Style.RESET_ALL + msg, flush=flush, end=end)


def warning(msg, flush=True, end="\n"):
    "Print colored warning message"
    print(Fore.YELLOW + "WARNING: " + Style.RESET_ALL + msg, flush=flush, end=end)


def error(msg, flush=True, end="\n"):
    "Print colored error message"
    print(Fore.RED + "ERROR:   " + Style.RESET_ALL + msg, flush=flush, end=end)


def convert_hex(src_file, dest_file):
    "Convert binary values to hex values readmemh can understand"
    len_bytes = 0
    word = ""
    for src_byte in src_file:
        word = "%02x" % (src_byte) + word
        if len(word) >= 8:
            dest_file.write(word + "\n")
            word = ""
        len_bytes += 1
    if len(word) > 0:
        dest_file.write(word + "\n")
    return len_bytes


def convert_hex_file(src_filename, dest_filename):
    "Convert binary file to hex file readmemh can understand"
    with open(src_filename, mode="rb") as src_file:
        with open(dest_filename, mode="w") as dest_file:
            return convert_hex(src_file.read(), dest_file)


def calculate_address_width(size_bytes):
    "Calculates memory address width required to store this many bytes"
    return math.ceil(math.log(size_bytes, 2))
