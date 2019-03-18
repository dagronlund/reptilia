import sys

with open(sys.argv[1], mode='rb') as fileSrc:
    contents = fileSrc.read()
    with open(sys.argv[2], mode='w') as fileDest:
        word = ""
        for b in contents:
            word = "%02x" % (b) + word
            if len(word) >= 8:
                fileDest.write(word + "\n")
                word = ""
