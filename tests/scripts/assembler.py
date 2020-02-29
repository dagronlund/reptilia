import hex_converter
import os
import sys
from subprocess import call

base_name = sys.argv[1]

input_file = sys.argv[1]
directory, filename = os.path.split(input_file)
filename_base, filename_ext = filename, ''
filename_split = filename.split('.')
if len(filename_split) == 2:
    filename_base = filename_split[0]
    filename_ext = filename_split[1]

call(["C:/gnu_riscv/bin/riscv-none-embed-gcc.exe",
      "-I../../riscv-tests/isa/macros/scalar",
      "-I../../riscv-tests/isa/rv32ui",
      "-I../../riscv-tests/isa/rv64ui",
      "-I../../riscv-tests/env/p",
      "-T", "linker.ld",
      "-nostdlib",
      "-nostartfiles",
      "-Wl,--no-relax",
      "-march=rv32im",
      "-mabi=ilp32",
      input_file,
      "-o", filename_base + ".o"]) # Assembler
call(["C:/gnu_riscv/bin/riscv-none-embed-objcopy.exe",
      "-O", "binary",
      filename_base + ".o",
      filename_base + ".bin"]) # Symbol Removal

mem_size_bytes = hex_converter.convert_file(
    os.path.join(os.getcwd(), filename_base + ".bin"),
    os.path.join(os.getcwd(), "test.mem"))
print("Compiled: %d bytes, Minimum Address Width: %d" %
      (mem_size_bytes, hex_converter.calculate_address_width(mem_size_bytes)))
