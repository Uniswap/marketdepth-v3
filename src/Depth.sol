// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.6;

import {IUniswapV3Pool} from 'v3-core/contracts/interfaces/IUniswapV3Pool.sol';
import {FullMath} from 'v3-core/contracts/libraries/FullMath.sol';
import {TickMath} from 'v3-core/contracts/libraries/TickMath.sol';
import {SqrtPriceMath} from 'v3-core/contracts/libraries/SqrtPriceMath.sol';
import {LiquidityMath}  from 'v3-core/contracts/libraries/LiquidityMath.sol';
// import "forge-std/console.sol";

contract Depth {

    // good practice to specify visibility of vars, these are default internal which is fine
    IUniswapV3Pool pool;

    // pack vars in a struct to save gas, up to 256 bits
    struct PoolVariables {
        int24 tick;
        int24 tickSpacing;
        uint128 liquidity;
    }
    PoolVariables poolVars;

    uint160 sqrtPriceX96;
    bool token1;

    PoolVariables internal poolVariables;

    function initializePoolVariables(address poolAddress) private {
        // todo ask what this means
        // also probably dont need pool as a storage var, just save whatever info u need from this pool ie looks like u use liquidity net
        pool = IUniswapV3Pool(address(poolAddress));
        
        int24 tick;
        // load data into global memory
        (sqrtPriceX96, tick,,,,,) = pool.slot0();

        poolVars = PoolVariables({
                tick: tick,
                tickSpacing: pool.tickSpacing(),
                liquidity: pool.liquidity()
            });
    }

    function calculateMultipleDepth(address poolAddress, uint256[] calldata sqrtDepthX96, 
                                    bool[] calldata token1, bool[] calldata both) public returns (uint256[] memory) {
        require((sqrtDepthX96.length == token1.length) &&
                 sqrtDepthX96.length == both.length, 'Different lengths provided');

        initializePoolVariables(poolAddress);

        // we ensured that all the variables are the same length, so shouldn't be too problematic to do this
        uint256[] memory returnArray = new uint[](sqrtDepthX96.length);
        uint256 tokenAmt;

        for (uint i=0; i<sqrtDepthX96.length; i++) {
            tokenAmt = _calculateDepth(sqrtDepthX96[i], token1[i], both[i]);

            returnArray[i] = tokenAmt;
        }

        return returnArray;
    }

    function calculateDepth(address poolAddress, uint256 sqrtDepthX96, bool token1, bool both) public returns (uint256) {
        initializePoolVariables(poolAddress);

        return _calculateDepth(sqrtDepthX96, token1, both);
    }

    // consider initializing the pool variables in a separate function: initializePoolVariables(address pool)
    // that way you could call calculateDepth multiple times in the same txn if you want different depths on the same pool
    function _calculateDepth(uint256 sqrtDepthX96, bool token1, bool both) private returns (uint256) {
        uint256 returnAmt = 0;

        // put it into global
        token1 = token1; 

        if (both) {
            returnAmt+=calculateOneSide(sqrtDepthX96, token1);
            returnAmt+=calculateOneSide(sqrtDepthX96, !token1);
        } else {
            returnAmt+=calculateOneSide(sqrtDepthX96, token1);
        }
       
        return returnAmt;
    }

    // can just send one bool into this function to determine direction
    // calculateOneSide(bool zeroForOne, uint256 sqrtDepthX96)
    function calculateOneSide(uint256 sqrtDepthX96, bool upper) private returns (uint256) {
        uint160 sqrtPriceRatioNext = sqrtPriceX96;
        uint160 sqrtPriceX96Current = sqrtPriceX96;

        // todo ask q
        // 1 << 96 is Q96
        // overflow potential?
        uint128 sqrtPriceX96Tgt = upper ? uint128(FullMath.mulDiv(sqrtPriceX96, sqrtDepthX96, 1 << 96))
                                        : uint128(FullMath.mulDiv(sqrtPriceX96, 1 << 96, sqrtDepthX96));
        
        // todo check if underflow can occur
        if (upper) { 
            require(sqrtPriceX96 <= sqrtPriceX96Tgt);
        }

        // todo ask q
        // shift lower if calculating lower
        // shift upper if calculating upper
        // this is simulating floor and ceiling to tick spacing
        int24 tickNext = upper ? ((poolVars.tick / poolVars.tickSpacing) + 1) * poolVars.tickSpacing
                               : (poolVars.tick / poolVars.tickSpacing) * poolVars.tickSpacing;

        int24 direction = upper ? int24(1)
                                  : int24(-1);

        int128 liquidityNet = 0;
        uint128 liquiditySpot = poolVars.liquidity;
        uint256 tokenAmt = 0;

        while (upper ? sqrtPriceRatioNext < sqrtPriceX96Tgt
                  : sqrtPriceRatioNext > sqrtPriceX96Tgt) {

            sqrtPriceRatioNext = TickMath.getSqrtRatioAtTick(tickNext);

            // todo: also adjust this
            // does this work? seems like youd just set it to target even if you have ticks to cross before target
            if (upper ? sqrtPriceRatioNext < sqrtPriceX96Tgt
                  : sqrtPriceRatioNext > sqrtPriceX96Tgt) {
                sqrtPriceRatioNext = sqrtPriceX96Tgt;
            }

            tokenAmt += token1 ? SqrtPriceMath.getAmount1Delta(sqrtPriceX96Current, sqrtPriceRatioNext, liquiditySpot, false)
                                 : SqrtPriceMath.getAmount0Delta(sqrtPriceX96Current, sqrtPriceRatioNext, liquiditySpot, false);

            // find the amount of liquidity to shift before we calculate the next tick
            // kick out or add in the liquidiy that we are moving
            (, liquidityNet,,,,,,)  = pool.ticks(tickNext);

            //todo q
            if (!upper) liquidityNet = -liquidityNet;
            liquiditySpot = LiquidityMath.addDelta(liquiditySpot, liquidityNet);

            // find what tick we will be shifting to
            // shift the range 
            // todo q why is this different than the calculation above?
            tickNext = ((tickNext / poolVars.tickSpacing) + direction) * poolVars.tickSpacing;
            sqrtPriceX96Current = sqrtPriceRatioNext;
        }

        return tokenAmt;
    }    
}
