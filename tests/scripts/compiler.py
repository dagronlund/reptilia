import sys
import os
import hex_converter
from subprocess import call

base_name = sys.argv[1]

flags = "-march=rv32i"
if len(sys.argv) > 2:
    if sys.argv[2] == 'm':
        flags = "-march=rv32im"

name_c = base_name + ".c"
name_o = base_name + ".o"
name_bin = base_name + ".bin"
name_mem = base_name + ".mem"

call(["C:/gnu_riscv/bin/riscv-none-embed-gcc.exe",
      # "-nostdlib",
      "-mfdiv",
      "-nostartfiles",
      "-Wl,--no-relax",
      "-T", "linker_script.lds",
      flags,
      "-mabi=ilp32",
      "-O3", "-fno-inline",
      "-lgcc",
      # Files to include
      "crt0.s", "libmem.c", "libio.c",
      "dhrystone/dhrystone.c", "dhrystone/dhrystone_main.c",
      name_c,
      # "-S",
      "-o", name_o
      ]) # Compiler
call(["C:/gnu_riscv/bin/riscv-none-embed-objcopy.exe", "-O", "binary", name_o, name_bin]) # Symbol Removal

mem_size_bytes = hex_converter.convert_file(
    os.path.join(os.getcwd(), name_bin),
    os.path.join(os.getcwd(), name_mem))
print("Compiled: %d bytes, Minimum Address Width: %d" %
      (mem_size_bytes, hex_converter.calculate_address_width(mem_size_bytes)))
