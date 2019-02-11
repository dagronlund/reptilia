import struct
import random
import math

def floats(n, req):
	op = req
	for i in range(0, n):
		a = random.uniform(-2**63, 2**63)
		b = random.uniform(-2**63, 2**63)
		if(req==5):
			op = random.randint(0, 4)
		sum = a + b
		diff = a - b
		product = a * b
		quotient = a/b
		sqrt = math.sqrt(abs(a))
		

		if(op==0):
			c = sum
		elif(op==1):
			c = diff
		elif(op==2): 
			c = product
		elif(op==3):
			c = quotient
		elif(op==4): 
			a = abs(a)
			c = sqrt
			b = 0xFFFFFFFF

		numbers = ""
		s = str("@" + str(hex(i)) + " " + str(op) + "_" + 
		        str(hex(struct.unpack('<I', struct.pack('<f', a))[0])) + "_" +  
				hex(struct.unpack('<I', struct.pack('<f', b))[0]) + "_" + 
			    hex(struct.unpack('<I', struct.pack('<f', c))[0]))
		s = s.split("0x")
		for x in s:
			numbers += x
		
		print(numbers)

def get_floats():
	op = int(input(""))
	n = int(input(""))
	floats(n, op)

get_floats()
