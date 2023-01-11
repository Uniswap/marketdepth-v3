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
        uint256 amt0;
        uint256 amt1;
        // if down then -1 if up then 1
        bool downOrUp;
        int24 tickNext;
        uint160 sqrtPriceRatioNext;
    }

    function calculateLowerAmt0(address poolAddress, uint256 sqrtDepthX96
                   ) public returns (uint256) {
        
        pool = IUniswapV3Pool(address(poolAddress));
        
        // load current state variables
        (uint160 sqrtPriceX96, int24 tick,,,,,) = pool.slot0();

        uint128 liquidity = pool.liquidity();
        int24 tickSpacing = pool.tickSpacing();
        
        DepthCache memory cache = 
            DepthCache({
                sqrtPriceX96: sqrtPriceX96,
                tick: tick, 
                liquidity: pool.liquidity(),
                tickSpacing: pool.tickSpacing(),
                amt0: 0,
                amt1: 0,
                downOrUp: false,
                tickNext: 0,
                sqrtPriceRatioNext: sqrtPriceX96
            });

        // calculate sqrtPriceRatios at the given depth
        uint128 sqrtPriceX96Above = uint128(FullMath.mulDiv(cache.sqrtPriceX96, sqrtDepthX96, 1 << 96));
        uint128 sqrtPriceX96Below = uint128(FullMath.mulDiv(cache.sqrtPriceX96, 1 << 96, sqrtDepthX96));
        

        // determine lower tick of current range
        cache.tickNext = (cache.tick / cache.tickSpacing) * cache.tickSpacing;

        
        int128 direction = 1;
        if (cache.downOrUp) {
                direction = -1;
            }

        int128 liquidityNet = 0;
        while (sqrtPriceX96Below < cache.sqrtPriceRatioNext) {
            cache.sqrtPriceRatioNext = TickMath.getSqrtRatioAtTick(cache.tickNext);

            if (cache.sqrtPriceRatioNext < sqrtPriceX96Below) {
                cache.sqrtPriceRatioNext = sqrtPriceX96Below;
            }

            uint256 deltaAmt0 = SqrtPriceMath.getAmount0Delta(cache.sqrtPriceX96, cache.sqrtPriceRatioNext, cache.liquidity, false);
            cache.amt0 = cache.amt0 + deltaAmt0;

            // shift ticks
            cache.tickNext = ((cache.tickNext / cache.tickSpacing) - int24(direction)) * cache.tickSpacing;
            (, liquidityNet,,,,,,)  = pool.ticks(cache.tickNext);
            cache.sqrtPriceX96 = cache.sqrtPriceRatioNext;
            cache.liquidity = LiquidityMath.addDelta(cache.liquidity, direction * liquidityNet);
        }

        return cache.amt0;
    }
}