// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.6;
pragma abicoder v2;

import {IUniswapV3Pool} from "v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {FullMath} from "v3-core/contracts/libraries/FullMath.sol";
import {TickMath} from "v3-core/contracts/libraries/TickMath.sol";
import {SqrtPriceMath} from "v3-core/contracts/libraries/SqrtPriceMath.sol";
import {LiquidityMath} from "v3-core/contracts/libraries/LiquidityMath.sol";
import {IDepth} from "./IDepth.sol";
import {PoolTickBitmap} from "./PoolTickBitmap.sol";
import {FixedPoint96} from "v3-core/contracts/libraries/FixedPoint96.sol";
import {DepthLibrary} from "./DepthLibrary.sol";

contract Depth is IDepth {
    using DepthLibrary for IDepth.DepthConfig;

    function calculateDepths(address pool, uint256[] memory sqrtDepthX96, DepthConfig[] memory configs)
        external
        view
        override
        returns (uint256[] memory amounts)
    {
        require(sqrtDepthX96.length == configs.length, "LengthMismatch");
        amounts = new uint256[](sqrtDepthX96.length);

        IDepth.PoolVariables memory poolVariables = _initializePoolVariables(pool);

        for (uint256 i = 0; i < sqrtDepthX96.length; i++) {
            amounts[i] = _calculateDepth(poolVariables, configs[i], sqrtDepthX96[i]);
        }
        return amounts;
    }

    function _calculateDepth(PoolVariables memory poolVariables, DepthConfig memory config, uint256 sqrtDepthX96)
        internal
        view
        returns (uint256 returnAmt)
    {
        if (config.side == Side.Both) {
            config.side = Side.Upper;
            returnAmt += calculateOneSide(poolVariables, config, sqrtDepthX96);
            config.side = Side.Lower;
            returnAmt += calculateOneSide(poolVariables, config, sqrtDepthX96);
        } else {
            returnAmt += calculateOneSide(poolVariables, config, sqrtDepthX96);
        }

        return returnAmt;
    }

    function calculateOneSide(PoolVariables memory poolVariables, DepthConfig memory config, uint256 sqrtDepthX96)
        internal
        view
        returns (uint256 amount)
    {
        bool upper = config.side == Side.Upper;

        // Prep step variables.
        uint160 sqrtPriceX96Current = poolVariables.sqrtPriceX96;
        uint160 sqrtPriceX96Tgt = config.getSqrtPriceX96Tgt(poolVariables.sqrtPriceX96, sqrtDepthX96);

        uint128 liquidityCurrent = poolVariables.liquidity;
        int24 tickNext = _findNextTick(poolVariables, poolVariables.tick, upper, sqrtPriceX96Tgt);
        uint160 sqrtPriceX96Next = TickMath.getSqrtRatioAtTick(tickNext);

        while (upper ? sqrtPriceX96Current < sqrtPriceX96Tgt : sqrtPriceX96Tgt < sqrtPriceX96Current) {
            // If we calculated a next price that is past the target we can calculate the amount directly to the target and break.
            if (upper ? sqrtPriceX96Next > sqrtPriceX96Tgt : sqrtPriceX96Next < sqrtPriceX96Tgt) {
                amount +=
                    _getAmountToNextPrice(config.amountInToken0, sqrtPriceX96Current, sqrtPriceX96Tgt, liquidityCurrent);
                break;
            }

            amount +=
                _getAmountToNextPrice(config.amountInToken0, sqrtPriceX96Current, sqrtPriceX96Next, liquidityCurrent);

            // Update the state variables.
            // First, we need liquidity net to calculate the liquidity spot.
            (, int128 liquidityNet,,,,,,) = IUniswapV3Pool(poolVariables.pool).ticks(tickNext);
            if (!upper) {
                liquidityNet = -liquidityNet;
            }
            liquidityCurrent = LiquidityMath.addDelta(liquidityCurrent, liquidityNet);
            tickNext = _findNextTick(poolVariables, upper ? tickNext : tickNext - 1, upper, sqrtPriceX96Tgt);

            // move the sqrtPriceCurrent to the end of the current bucket
            // then move the sqrtPriceX96Next to the end of the next bucket
            sqrtPriceX96Current = sqrtPriceX96Next;
            sqrtPriceX96Next = TickMath.getSqrtRatioAtTick(tickNext);
        }
    }

    function _initializePoolVariables(address poolAddress) internal view returns (PoolVariables memory poolVariables) {
        IUniswapV3Pool pool = IUniswapV3Pool(poolAddress);

        (uint160 sqrtPriceX96, int24 tick,,,,,) = pool.slot0();

        poolVariables = IDepth.PoolVariables({
            tick: tick,
            tickSpacing: pool.tickSpacing(),
            liquidity: pool.liquidity(),
            sqrtPriceX96: sqrtPriceX96,
            pool: poolAddress
        });
    }

    function _getAmountToNextPrice(
        bool amountInToken0,
        uint160 sqrtPriceX96Current,
        uint160 sqrtPriceX96Next,
        uint128 liquidityCurrent
    ) internal pure returns (uint256 amount) {
        if (liquidityCurrent != 0) {
            if (amountInToken0) {
                amount = SqrtPriceMath.getAmount0Delta(sqrtPriceX96Current, sqrtPriceX96Next, liquidityCurrent, false);
            } else {
                amount = SqrtPriceMath.getAmount1Delta(sqrtPriceX96Current, sqrtPriceX96Next, liquidityCurrent, false);
            }
        }
    }

    function _findNextTick(PoolVariables memory poolVariables, int24 tick, bool upper, uint160 sqrtPriceX96Tgt)
        internal
        view
        returns (int24 tickNext)
    {
        bool initialized;

        (tickNext, initialized) =
            PoolTickBitmap.nextInitializedTickWithinOneWord(poolVariables, tick, !upper);
        
        // we most likely hit the end of the word that we are in - we need to know if there is another word that
        // we can move into
        if (!initialized) {
            // check outside the current tick range but inside the current 256 tick spacing bounds before calculating anything
            (tickNext, initialized) =
                        PoolTickBitmap.nextInitializedTickWithinOneWord(poolVariables, upper ? tick : tick - 1, !upper);

            // we found a tick that is within 256 tick spacings
            if (initialized) {
                return tickNext;
            }

            // because this function the greatest tick that is below the target ratio, it is problematic if you are going up in price
            // the getTickAtSqrtRatio is functionally rounding down the fractional part of the tick, but we want to round it up
            // if we are going up (we can do this by adding 1)
            // getTickAtSqrtRatio(tick) <= ratio
            int24 tickMax = TickMath.getTickAtSqrtRatio(sqrtPriceX96Tgt);
            if (upper) {
                tickMax = tickMax + 1;
            }

            while (!initialized && upper ? tick <= tickMax : tick >= tickMax) {
                tick = upper ? tick + 255 * poolVariables.tickSpacing 
                             : tick - 255 * poolVariables.tickSpacing;

                (tickNext, initialized) =
                        PoolTickBitmap.nextInitializedTickWithinOneWord(poolVariables, tick, !upper);
            }
        }
    }
}
