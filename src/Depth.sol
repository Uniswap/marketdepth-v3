// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.6;

import {IUniswapV3Pool} from 'v3-core/contracts/interfaces/IUniswapV3Pool.sol';
import {FullMath} from 'v3-core/contracts/libraries/FullMath.sol';
import {TickMath} from 'v3-core/contracts/libraries/TickMath.sol';
import {SqrtPriceMath} from 'v3-core/contracts/libraries/SqrtPriceMath.sol';
import {LiquidityMath}  from 'v3-core/contracts/libraries/LiquidityMath.sol';
// import "forge-std/console.sol";

contract Depth {

    IUniswapV3Pool pool;
    uint160 sqrtPriceX96;
    int24 tick;
    uint128 liquidity;
    int24 tickSpacing;

    function calculateDepth(address poolAddress, uint256 sqrtDepthX96, bool token0, bool both) public returns (uint256) {
        uint256 returnAmt = 0;

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
        return returnAmt;
    }

    function calculateOneSide(bool token0, uint256 sqrtDepthX96, bool upper) private returns (uint256) {
        uint160 sqrtPriceRatioNext = sqrtPriceX96;
        uint160 sqrtPriceX96Current = sqrtPriceX96;

        uint128 sqrtPriceX96Tgt = upper ? uint128(FullMath.mulDiv(sqrtPriceX96, sqrtDepthX96, 1 << 96))
                                        : uint128(FullMath.mulDiv(sqrtPriceX96, 1 << 96, sqrtDepthX96));
        
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
            if (upper ? sqrtPriceRatioNext < sqrtPriceX96Tgt
                  : sqrtPriceRatioNext > sqrtPriceX96Tgt) {
                sqrtPriceRatioNext = sqrtPriceX96Tgt;
            }

            tokenAmt += token0 ? SqrtPriceMath.getAmount0Delta(sqrtPriceX96Current, sqrtPriceRatioNext, liquidity, false)
                                 : SqrtPriceMath.getAmount1Delta(sqrtPriceX96Current, sqrtPriceRatioNext, liquidity, false);

            // find the amount of liquidity to shift before we calculate the next tick
            // kick out or add in the liquidiy that we are moving
            (, liquidityNet,,,,,,)  = pool.ticks(tickNext);

            if (!upper) liquidityNet = -liquidityNet;
            liquiditySpot = LiquidityMath.addDelta(liquiditySpot, liquidityNet);

            // find what tick we will be shifting to
            // shift the range 
            tickNext = ((tickNext / tickSpacing) + direction) * tickSpacing;
            sqrtPriceX96Current = sqrtPriceRatioNext;
        }

        return tokenAmt;
    }    
}