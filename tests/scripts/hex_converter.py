import math
import sys


def convert(src_file, dest_file):
    contents = src_file.read()
    mem_size_bytes = 0
    word = ""
    for b in contents:
        word = "%02x" % (b) + word
        mem_size_bytes += 1
        if len(word) >= 8:
            dest_file.write(word + "\n")
            word = ""
    return mem_size_bytes


def convert_file(src_filename, dest_filename):
    with open(src_filename, mode='rb') as src_file:
        with open(dest_filename, mode='w') as dest_file:
            return convert(src_file, dest_file)


def calculate_address_width(size_bytes):
    return math.ceil(math.log(size_bytes, 2))


def main():
    mem_size_bytes = convert_file(sys.argv[1], sys.argv[2])
    mem_addr_width = calculate_address_width(mem_size_bytes)
    print("Compiled: %d bytes, Minimum Address Width: %d" % (mem_size_bytes, mem_addr_width))


if __name__ == "__main__":
    main()
