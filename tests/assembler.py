import sys
from subprocess import call

base_name = sys.argv[1]

name_s = base_name + ".s"
name_o = base_name + ".o"
name_so = base_name + ".so"
name_bin = base_name + ".bin"
name_mem = base_name + ".mem"

call(["C:/gnu_riscv/bin/riscv-none-embed-as.exe", name_s, "-o", name_o]) # Assembler
call(["C:/gnu_riscv/bin/riscv-none-embed-ld.exe", "-T", "linker.ld", name_o, "-o", name_so]) # Linker
call(["C:/gnu_riscv/bin/riscv-none-embed-objcopy.exe", "-O", "binary", name_so, name_bin]) # Symbol Removal
call(["python", "hex_converter.py", name_bin, name_mem]) # Hex Conversion
