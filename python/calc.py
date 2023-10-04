import sys
from eth_abi import encode

args = sys.argv
arg = [*map(lambda x: int(x), args[1].split(","))]

var = sys.stdout
out = encode(['int256[]'], [arg])

var.write(out.hex())