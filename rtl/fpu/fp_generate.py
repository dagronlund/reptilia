import struct
import random

def floats(n):
	for i in range(0, n):
		a = random.uniform(-2**127, 2**127)
		b = random.uniform(-2**127, 2**127)
		c = a/b
		numbers = ""
		s = str("@" + str(i) + " " + str(hex(struct.unpack('<I', struct.pack('<f', a))[0])) + "_" +  
					hex(struct.unpack('<I', struct.pack('<f', b))[0]) + "_" + 
		 		  hex(struct.unpack('<I', struct.pack('<f', c))[0]))
		s = s.split("0x")
		for x in s:
			numbers += x
		
		print(numbers)


floats(10)
