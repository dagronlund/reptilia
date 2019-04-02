import sys
from subprocess import call

base_name = sys.argv[1]

name_c = base_name + ".c"
name_o = base_name + ".o"
name_bin = base_name + ".bin"
name_mem = base_name + ".mem"

call(["C:/gnu_riscv/bin/riscv-none-embed-gcc.exe",
      # "-nostdlib",
      "-lgcc",
      "-nostartfiles",
      "-Wl,--no-relax",
      "-T", "linker_script.lds",
      "-march=rv32i",
      "-mabi=ilp32",
      "-O3", "-fno-inline",
      # Files to include
      name_c, "crt0.s", "libmem.c", "libio.c", "dhrystone/dhrystone.c", "dhrystone/dhrystone_main.c",
      # "-S",
      "-o", name_o
      ]) # Compiler
call(["C:/gnu_riscv/bin/riscv-none-embed-objcopy.exe", "-O", "binary", name_o, name_bin]) # Symbol Removal
call(["python", "hex_converter.py", name_bin, name_mem]) # Hex Conversion
