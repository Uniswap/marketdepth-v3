// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.6;
pragma abicoder v2;

import {IUniswapV3Pool} from 'v3-core/contracts/interfaces/IUniswapV3Pool.sol';
import {FullMath} from 'v3-core/contracts/libraries/FullMath.sol';
import {TickMath} from 'v3-core/contracts/libraries/TickMath.sol';
import {SqrtPriceMath} from 'v3-core/contracts/libraries/SqrtPriceMath.sol';
import {LiquidityMath}  from 'v3-core/contracts/libraries/LiquidityMath.sol';
import {IDepth} from "./IDepth.sol";

contract Depth is IDepth {

    function calculateDepths(address pool, uint256[] memory sqrtDepthX96, DepthConfig[] memory configs)
        external
        override
        returns (uint256[] memory amounts)
    {
        if (sqrtDepthX96.length != configs.length) revert("LengthMismatch"); //revert LengthMismatch();
        amounts = new uint256[](sqrtDepthX96.length);

        IDepth.PoolVariables memory pool = initializePoolVariables(pool);

        for (uint256 i = 0; i < sqrtDepthX96.length; i++) {
            amounts[i] = _calculateDepth(pool, configs[i], sqrtDepthX96[i]);
        }
        return amounts;
    }

    function _calculateDepth(PoolVariables memory pool, DepthConfig memory config, uint256 sqrtDepthX96) 
        internal 
        returns (uint256) 
    {
        uint256 returnAmt = 0;

        if (config.bothSides) {
            returnAmt+=calculateOneSide(pool, config, sqrtDepthX96, true);
            returnAmt+=calculateOneSide(pool, config, sqrtDepthX96, false);
        } else {
            returnAmt+=calculateOneSide(pool, config, sqrtDepthX96, false);
        }
       
        return returnAmt;
    }

    function calculateOneSide(PoolVariables memory pool, DepthConfig memory config, uint256 sqrtDepthX96, bool inversion) 
        internal 
        returns (uint256) 
    {
        uint160 sqrtPriceRatioNext = pool.sqrtPriceX96;
        uint160 sqrtPriceX96Current = pool.sqrtPriceX96;
        bool upper = config.token0;

        if (inversion) {
            upper = !upper;
        }

        uint160 sqrtPriceX96Tgt = upper ? uint160(FullMath.mulDiv(pool.sqrtPriceX96, sqrtDepthX96, 1 << 96))
                                        : uint160(FullMath.mulDiv(pool.sqrtPriceX96, 1 << 96, sqrtDepthX96));
        if (upper) { 
            require(pool.sqrtPriceX96 <= sqrtPriceX96Tgt);
        } else if (config.exact) {
            // we want to calculate deflator = (1-p)^2 / 2 to approximate (1-p) instead of 1/(1+p)
            // because 1 / (1 + p) * price * (1-deflator) = (1-p) * price
            // this is because of the taylor series expansion of these values
            // however we need to keep everything in integers, so we cannot directly calculate sqrt(1-p)
            // 112045541949572287496682733568 = sqrt(2) * 2^96, which breaks this code/deflation
            require(sqrtDepthX96 < 112045541949572287496682733568);

            uint256 deflator = (sqrtDepthX96 * sqrtDepthX96 - (4 * (1 << 96)) - (1 << 192)) / (1 << 96);
            sqrtPriceX96Tgt = uint160(FullMath.mulDiv(sqrtPriceX96Tgt, ((1 << 192) - (deflator * deflator) / 2),  1 << 192));
        }
        
        // this finds the floor for lower and ceil for upper of the current tick range
        int24 tickNext = upper ? ((pool.tick / pool.tickSpacing) + 1) * pool.tickSpacing
                               : (pool.tick / pool.tickSpacing) * pool.tickSpacing;

        int24 direction = upper ? int24(1)
                                  : int24(-1);

        int128 liquidityNet = 0;
        uint128 liquiditySpot = pool.liquidity;
        uint256 tokenAmt = 0;

        // we are going to find the sqrtPriceX96Tgt that we want to find
        // however we also don't want to overshoot it
        // here we are looking to see if we are equal to the sqrtPriceX96Tgt
        while (upper ? sqrtPriceRatioNext < sqrtPriceX96Tgt
                  : sqrtPriceRatioNext > sqrtPriceX96Tgt) {

            sqrtPriceRatioNext = TickMath.getSqrtRatioAtTick(tickNext);
  
            // here we are checking if we blew past the target, and then if we did, we set it to the value we are searching for
            // then the loop above breaks
            if (upper ? sqrtPriceRatioNext > sqrtPriceX96Tgt
                  : sqrtPriceRatioNext < sqrtPriceX96Tgt) {
                sqrtPriceRatioNext = sqrtPriceX96Tgt;
            }

            tokenAmt += config.token0 ? SqrtPriceMath.getAmount0Delta(sqrtPriceX96Current, sqrtPriceRatioNext, liquiditySpot, false)
                                      : SqrtPriceMath.getAmount1Delta(sqrtPriceX96Current, sqrtPriceRatioNext, liquiditySpot, false);

            // find the amount of liquidity to shift before we calculate the next tick
            // kick out or add in the liquidiy that we are moving
            (, liquidityNet,,,,,,)  = IUniswapV3Pool(pool.pool).ticks(tickNext);

            if (!upper) liquidityNet = -liquidityNet;
            liquiditySpot = LiquidityMath.addDelta(liquiditySpot, liquidityNet);

            // find what tick we will be shifting to
            // shift the range 
            tickNext = ((tickNext / pool.tickSpacing) + direction) * pool.tickSpacing;
            sqrtPriceX96Current = sqrtPriceRatioNext;
        }

        return tokenAmt;
    }

    function initializePoolVariables(address poolAddress) 
        internal 
        returns (PoolVariables memory poolVar) 
    {
        IUniswapV3Pool pool = IUniswapV3Pool(address(poolAddress));

        int24 tick;
        uint160 sqrtPriceX96;
        // load data into global memory
        (sqrtPriceX96, tick,,,,,) = pool.slot0(); // sload, sstore

        poolVar = IDepth.PoolVariables({
            tick: tick,
            tickSpacing: pool.tickSpacing(),
            liquidity: pool.liquidity(),
            sqrtPriceX96: sqrtPriceX96,
            pool: poolAddress
        });
    }
}
