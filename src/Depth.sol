// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.6;
pragma abicoder v2;

import {IUniswapV3Pool} from "v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {FullMath} from "v3-core/contracts/libraries/FullMath.sol";
import {TickMath} from "v3-core/contracts/libraries/TickMath.sol";
import {SqrtPriceMath} from "v3-core/contracts/libraries/SqrtPriceMath.sol";
import {LiquidityMath} from "v3-core/contracts/libraries/LiquidityMath.sol";
import {IDepth} from "./IDepth.sol";

contract Depth is IDepth {
    function calculateDepths(address pool, uint256[] memory sqrtDepthX96, DepthConfig[] memory configs)
        external
        override
        returns (uint256[] memory amounts)
    {
        require(sqrtDepthX96.length == configs.length, "LengthMismatch");
        amounts = new uint256[](sqrtDepthX96.length);

        // we may just want to do calculation inside here instead of calling out to func
        IDepth.PoolVariables memory poolVariables = initializePoolVariables(pool);

        for (uint256 i = 0; i < sqrtDepthX96.length; i++) {
            amounts[i] = _calculateDepth(poolVariables, configs[i], sqrtDepthX96[i]);
        }
        return amounts;
    }

    function _calculateDepth(PoolVariables memory poolVariables, DepthConfig memory config, uint256 sqrtDepthX96)
        internal
        returns (uint256)
    {
        uint256 returnAmt = 0;

        if (config.side == Side.Both) {
            returnAmt += calculateOneSide(poolVariables, config, sqrtDepthX96, true);
            returnAmt += calculateOneSide(poolVariables, config, sqrtDepthX96, false);
        } else {
            returnAmt += calculateOneSide(poolVariables, config, sqrtDepthX96, config.side == Side.Upper ? true : false);
        }

        return returnAmt;
    }

    function calculateOneSide(
        PoolVariables memory poolVariables,
        DepthConfig memory config,
        uint256 sqrtDepthX96,
        bool calculateUpper
    ) internal view returns (uint256) {
        int24 tickNext;
        int24 direction;
        uint160 sqrtPriceX96Tgt;

        if (calculateUpper) {
            require(poolVariables.sqrtPriceX96 <= sqrtPriceX96Tgt, "UpperboundOverflow");
            tickNext = ((poolVariables.tick / poolVariables.tickSpacing) + 1) * poolVariables.tickSpacing;
            direction = int24(1);
            sqrtPriceX96Tgt = uint160(FullMath.mulDiv(poolVariables.sqrtPriceX96, sqrtDepthX96, 1 << 96));
        } else {
            tickNext = (poolVariables.tick / poolVariables.tickSpacing) * poolVariables.tickSpacing;
            direction = int24(-1);
            sqrtPriceX96Tgt = uint160(FullMath.mulDiv(poolVariables.sqrtPriceX96, 1 << 96, sqrtDepthX96));
        }
        // why are these mutually exclusive? pretty confusing & should separate out if possible..
        // and.. what happens if not upper and we want exact?
        if (config.exact) {
            // we want to calculate deflator = (1-p)^2 / 2 to approximate (1-p) instead of 1/(1+p)
            // because 1 / (1 + p) * price * (1-deflator) = (1-p) * price
            // this is because of the taylor series expansion of these values
            // however we need to keep everything in integers, so we cannot directly calculate sqrt(1-p)
            // 112045541949572287496682733568 = sqrt(2) * 2^96, which breaks this code/deflation
            require(sqrtDepthX96 < 112045541949572287496682733568, "ExceededMaxDepth");

            uint256 deflator = (sqrtDepthX96 * sqrtDepthX96 - (4 * (1 << 96)) - (1 << 192)) / (1 << 96);
            sqrtPriceX96Tgt =
                uint160(FullMath.mulDiv(sqrtPriceX96Tgt, ((1 << 192) - (deflator * deflator) / 2), 1 << 192));
        }

        uint160 sqrtPriceX96Current = poolVariables.sqrtPriceX96;
        uint128 liquiditySpot = poolVariables.liquidity;
        int128 liquidityNet;
        uint256 tokenAmt;
        uint160 sqrtPriceRatioNext;

        // we are going to find the sqrtPriceX96Tgt that we want to find
        // however we also don't want to overshoot it
        // here we are looking to see if we are equal to the sqrtPriceX96Tgt
        while (calculateUpper ? sqrtPriceX96Current < sqrtPriceX96Tgt : sqrtPriceX96Current > sqrtPriceX96Tgt) {
            sqrtPriceRatioNext = TickMath.getSqrtRatioAtTick(tickNext);

            // here we are checking if we blew past the target, and then if we did, we set it to the value we are searching for
            // then the loop above breaks
            if (calculateUpper ? sqrtPriceRatioNext > sqrtPriceX96Tgt : sqrtPriceRatioNext < sqrtPriceX96Tgt) {
                sqrtPriceRatioNext = sqrtPriceX96Tgt;
            }

            tokenAmt += config.amountInToken0
                ? SqrtPriceMath.getAmount0Delta(sqrtPriceX96Current, sqrtPriceRatioNext, liquiditySpot, false)
                : SqrtPriceMath.getAmount1Delta(sqrtPriceX96Current, sqrtPriceRatioNext, liquiditySpot, false);

            // find the amount of liquidity to shift before we calculate the next tick
            // kick out or add in the liquidiy that we are moving
            (, liquidityNet,,,,,,) = IUniswapV3Pool(poolVariables.pool).ticks(tickNext);

            // liquidityNet is added to the spot when going left to right (upper)
            // liquidityNet is subtracted to the spot when going right to left (lower)
            liquidityNet = liquidityNet * direction;
            liquiditySpot = LiquidityMath.addDelta(liquiditySpot, liquidityNet);

            // find what tick we will be shifting to
            // shift the range
            tickNext = ((tickNext / poolVariables.tickSpacing) + direction) * poolVariables.tickSpacing;
            sqrtPriceX96Current = sqrtPriceRatioNext;
        }

        return tokenAmt;
    }

    function initializePoolVariables(address poolAddress) internal view returns (PoolVariables memory poolVariables) {
        IUniswapV3Pool pool = IUniswapV3Pool(poolAddress);

        int24 tick;
        uint160 sqrtPriceX96;
        (sqrtPriceX96, tick,,,,,) = pool.slot0();

        poolVariables = IDepth.PoolVariables({
            tick: tick,
            tickSpacing: pool.tickSpacing(),
            liquidity: pool.liquidity(),
            sqrtPriceX96: sqrtPriceX96,
            pool: poolAddress
        });
    }
}
