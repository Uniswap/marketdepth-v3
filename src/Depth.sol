// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.6;

import {IUniswapV3Pool} from 'v3-core/contracts/interfaces/IUniswapV3Pool.sol';
import {FullMath} from 'v3-core/contracts/libraries/FullMath.sol';
import {TickMath} from 'v3-core/contracts/libraries/TickMath.sol';
import {SqrtPriceMath} from 'v3-core/contracts/libraries/SqrtPriceMath.sol';
import {LiquidityMath}  from 'v3-core/contracts/libraries/LiquidityMath.sol';


contract Depth {
    IUniswapV3Pool pool;
    struct DepthCache {
        // pool level characteristics
        uint160 sqrtPriceX96;
        int24 tick;
        uint128 liquidity;
        int24 tickSpacing;

        // depth cache information
        uint256 tokenAmt;
        int24 tickNext;
        uint160 sqrtPriceRatioNext;
        bool token0;
        uint256 sqrtDepthX96;
    }

    function calculateDepth(address poolAddress, uint256 sqrtDepthX96, bool token0, bool both) public returns (uint256) {
        uint256 returnAmt = 0;

        pool = IUniswapV3Pool(address(poolAddress));
        
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

    function calculateOneSide(bool token0, uint256 sqrtDepthX96, bool lower) private returns (uint256) {
        // load current state variables
        // TODO: pass this info instead of loading it twice
        (uint160 sqrtPriceX96, int24 tick,,,,,) = pool.slot0();
        
        DepthCache memory cache = 
            DepthCache({
                sqrtPriceX96: sqrtPriceX96,
                tick: tick, 
                liquidity: pool.liquidity(),
                tickSpacing: pool.tickSpacing(),
                tokenAmt: 0,
                tickNext: 0,
                sqrtPriceRatioNext: sqrtPriceX96,
                token0: token0,
                sqrtDepthX96: sqrtDepthX96
            });


        uint128 sqrtPriceX96Tgt = lower ? uint128(FullMath.mulDiv(cache.sqrtPriceX96, 1 << 96, sqrtDepthX96))
                                        : uint128(FullMath.mulDiv(cache.sqrtPriceX96, sqrtDepthX96, 1 << 96));
        
        // shift lower if calculating lower
        // shift upper if calculating upper
        cache.tickNext = lower ? (cache.tick / cache.tickSpacing) * cache.tickSpacing
                               : ((cache.tick / cache.tickSpacing) + 1) * cache.tickSpacing;

        uint128 direction = lower ? uint128(-1)
                                 : uint128(1);
        int128 liquidityNet = 0;
        uint256 netTokenAmt = 0;

        // adjust this to account for lower or upp
        while (direction * cache.sqrtPriceRatioNext < direction * sqrtPriceX96Tgt) {
            cache.sqrtPriceRatioNext = TickMath.getSqrtRatioAtTick(cache.tickNext);

            // todo: also adjust this
            if (direction * cache.sqrtPriceRatioNext < direction * sqrtPriceX96Tgt) {
                cache.sqrtPriceRatioNext = sqrtPriceX96Tgt;
            }

            netTokenAmt = token0 ? SqrtPriceMath.getAmount0Delta(cache.sqrtPriceX96, cache.sqrtPriceRatioNext, cache.liquidity, false)
                                 : SqrtPriceMath.getAmount1Delta(cache.sqrtPriceX96, cache.sqrtPriceRatioNext, cache.liquidity, false);
            cache.tokenAmt = cache.tokenAmt + netTokenAmt;

            // shift ticks
            // TODO: move this to a function for reuse
            cache.tickNext = ((cache.tickNext / cache.tickSpacing) + int24(direction)) * cache.tickSpacing;
            (, liquidityNet,,,,,,)  = pool.ticks(cache.tickNext);
            cache.sqrtPriceX96 = cache.sqrtPriceRatioNext;
            cache.liquidity = LiquidityMath.addDelta(cache.liquidity, int128(direction) * liquidityNet);
        }

        return cache.tokenAmt;
    }    
}