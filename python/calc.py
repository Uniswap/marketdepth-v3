from eth_abi import encode
import math
import sys

def tickToPrice(tick):
    return 1.0001**(tick)

def priceToToken0(priceLower, priceUpper, liquidity):
    sqrtPriceLower = math.sqrt(priceLower)
    sqrtPriceUpper = math.sqrt(priceUpper)
    
    return (liquidity * (sqrtPriceUpper - sqrtPriceLower)) / (sqrtPriceUpper * sqrtPriceLower)

def priceToToken1(priceLower, priceUpper, liquidity):
    sqrtPriceLower = math.sqrt(priceLower)
    sqrtPriceUpper = math.sqrt(priceUpper)
    
    return (liquidity * (sqrtPriceUpper - sqrtPriceLower))

# immutables
sqrtDepths = [.0025, .005, .01, .02, .05, .1]
feeToTickSpacing = [200, 60, 10, 1]
MAX_TICK = 1024 # int16.max / int5.max = 1024  
args = sys.argv

# parse the command line arguments
command_name = args[0]
pos1 = [*map(lambda x: int(x), args[1].split(","))]
pos2 = [*map(lambda x: int(x), args[2].split(","))]
token = args[3]
direction = args[4]
sqrtDepthX96Index = args[5]
feeTierIdx = args[6]

# parse the args
depth = sqrtDepths[int(sqrtDepthX96Index)]
ts = feeToTickSpacing[int(feeTierIdx)]

# these are invariants currently in the system
lower = 1 # equiv to 1 << 96
upper = 1
MIN_TICK = -1 * MAX_TICK

# apply the depths to the current price
if direction == 'upper' or direction == 'both':
    upper*=(1+depth)
    
if direction == 'lower' or direction == 'both':
    lower*=(1/(1+depth))

# srry
amtOut = 0


# we need to put the iteration on the nearest possible tick spacings
minIteration = (MIN_TICK // ts) * ts
maxIteration = ((ts + MAX_TICK) // ts) * ts

# we know that the tick-spacing on the fuzzer is -1024, 1024
# we iterate just closer to that
for tick in range(minIteration, maxIteration + 1, ts):
    liquidity = 0
    
    if pos1[0] <= tick and tick < pos1[1]:
        liquidity += pos1[2]
        
    if pos2[0] <= tick and tick < pos2[1]:
        liquidity += pos2[2]
        
    if liquidity == 0:
        continue
            
    tickLowerSqrtPrice = tickToPrice(tick)
    tickUpperSqrtPrice = tickToPrice(tick+ts)
    lowerPrice = 0
    upperPrice = 0
    
    # is the lowest price of depth range greater 
    # than highest price of the tick range?
    if tickUpperSqrtPrice <= lower:
        continue
    # truncate down to the end of the depth range
    elif tickLowerSqrtPrice <= lower < tickUpperSqrtPrice:
        lowerPrice = lower
    # just pass on the tick prices
    else:
        lowerPrice = tickLowerSqrtPrice
        
    # is the highest price of the depth range smaller 
    # than lowest price of the tick range?
    if upper <= tickLowerSqrtPrice:
        continue
    # truncate down to the top of the depth range
    elif tickLowerSqrtPrice <= upper < tickUpperSqrtPrice:
        upperPrice = upper
    # just pass on the tick prices
    else:
        upperPrice = tickUpperSqrtPrice
    
    # apply the liquidity math calculations
    if liquidity != 0 and float(lower) != float(upper):
        if token == '1':
            t = priceToToken1(lowerPrice, upperPrice, liquidity)
        else:
            t = priceToToken0(lowerPrice, upperPrice, liquidity)
            
        amtOut+=t

var = sys.stdout
out = encode(['int256'], [int(amtOut)])
var.write(out.hex())
