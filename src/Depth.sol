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
    uint160 sqrtPriceX96;
    int24 tick;
    uint128 liquidity;
    int24 tickSpacing;

    PoolVariables internal poolVariables;


    // consider initializing the pool variables in a separate function: initializePoolVariables(address pool)
    // that way you could call calculateDepth multiple times in the same txn if you want different depths on the same pool
    function calculateDepth(address poolAddress, uint256 sqrtDepthX96, bool token0, bool both) public returns (uint256) {
        uint256 returnAmt = 0;

        // also probably dont need pool as a storage var, just save whatever info u need from this pool ie looks like u use liquidity net
        pool = IUniswapV3Pool(address(poolAddress));
        
        // load data into global memory
        (sqrtPriceX96, tick,,,,,) = pool.slot0();
        liquidity = pool.liquidity();
        tickSpacing = pool.tickSpacing();


        
        if (token0) {
            returnAmt+=calculateOneSide(token0, sqrtDepthX96, false);
            if (both) {
                returnAmt+=calculateOneSide(token0, sqrtDepthX96, true);
            }
        } else {
            returnAmt+=calculateOneSide(token0, sqrtDepthX96, true);
            if (both) {
                returnAmt+=calculateOneSide(token0, sqrtDepthX96, false);
            }
        }

        // nit: consider doing 
        // if (both) {
        //     calculateOneSide(.. true)
        //     calculateOneSide(..false)
        // } else {
        //     calculateOneSide(..token0)
        // }

        return returnAmt;
    }

    // can just send one bool into this function to determine direction
    // calculateOneSide(bool zeroForOne, uint256 sqrtDepthX96)
    function calculateOneSide(bool token0, uint256 sqrtDepthX96, bool upper) private returns (uint256) {
        
        uint160 sqrtPriceRatioNext = sqrtPriceX96;
        uint160 sqrtPriceX96Current = sqrtPriceX96;

        // todo ask q
        // 1 << 96 is Q96
        // overflow potential?
        uint128 sqrtPriceX96Tgt = upper ? uint128(FullMath.mulDiv(sqrtPriceX96, sqrtDepthX96, 1 << 96))
                                        : uint128(FullMath.mulDiv(sqrtPriceX96, 1 << 96, sqrtDepthX96));

        // todo ask q
        // shift lower if calculating lower
        // shift upper if calculating upper
        int24 tickNext = upper ? ((tick / tickSpacing) + 1) * tickSpacing
                               : (tick / tickSpacing) * tickSpacing;

        int24 direction = upper ? int24(1)
                                  : int24(-1);

        int128 liquidityNet = 0;
        uint128 liquiditySpot = liquidity;
        uint256 tokenAmt = 0;

        // adjust this to account for lower or up
        // console.log(sqrtPriceRatioNext);
        // console.log(sqrtPriceX96Tgt);

        while (upper ? sqrtPriceRatioNext < sqrtPriceX96Tgt
                  : sqrtPriceRatioNext > sqrtPriceX96Tgt) {

            sqrtPriceRatioNext = TickMath.getSqrtRatioAtTick(tickNext);

            // todo: also adjust this
            // does this work? seems like youd just set it to target even if you have ticks to cross before target
            if (upper ? sqrtPriceRatioNext < sqrtPriceX96Tgt
                  : sqrtPriceRatioNext > sqrtPriceX96Tgt) {
                sqrtPriceRatioNext = sqrtPriceX96Tgt;
            }

            tokenAmt += token0 ? SqrtPriceMath.getAmount0Delta(sqrtPriceX96Current, sqrtPriceRatioNext, liquidity, false)
                                 : SqrtPriceMath.getAmount1Delta(sqrtPriceX96Current, sqrtPriceRatioNext, liquidity, false);

            // find the amount of liquidity to shift before we calculate the next tick
            // kick out or add in the liquidiy that we are moving
            (, liquidityNet,,,,,,)  = pool.ticks(tickNext);

            //todo q
            if (!upper) liquidityNet = -liquidityNet;
            liquiditySpot = LiquidityMath.addDelta(liquiditySpot, liquidityNet);

            // find what tick we will be shifting to
            // shift the range 
            // todo q why is this different than the calculation above?
            tickNext = ((tickNext / tickSpacing) + direction) * tickSpacing;
            sqrtPriceX96Current = sqrtPriceRatioNext;
        }

        return tokenAmt;
    }    
}i