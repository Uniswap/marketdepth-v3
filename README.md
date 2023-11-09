## Uniswap v3 market depth calculator

Calculates market depth (the amount of assets avaiable to trade within a certain price region)
Inspired by [Uniswap market depth study](https://github.com/Uniswap/v3-market-depth-study) and [python implimentation](https://github.com/Uniswap/v3-market-depth-study)

### Usage
Can be used for routing heuritistics, onchain liquidity calculations, or for plotting.

`sqrtDepthX96` is sqrt(1 + \delta) * 2^96 where \delta is the price region that you want to calculate.
For example, 2% market depth is 80016521857016597127997947904 or sqrt(1 + .02) * 2^96.

`side` provides the depth in either higher, lower, and both (which is higher + lower).

`amountInToken0` determines the token that depth is quoted in (token0 or token1)

### Running the tests
We test using a python script with ffi so you need to install eth_abi
`python3 -m pip install eth_abi`

Then run the tests with:
`forge test --ffi`