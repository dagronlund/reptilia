import sys
import math

with open(sys.argv[1], mode='rb') as fileSrc:
    contents = fileSrc.read()
    with open(sys.argv[2], mode='w') as fileDest:
        mem_size_bytes = 0
        word = ""
        for b in contents:
            word = "%02x" % (b) + word
            mem_size_bytes += 1
            if len(word) >= 8:
                fileDest.write(word + "\n")
                word = ""
        mem_addr_width = math.ceil(math.log(mem_size_bytes, 2))
        print("Compiled: %d bytes, Minimum Address Width: %d" % (mem_size_bytes, mem_addr_width))
