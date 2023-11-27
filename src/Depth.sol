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
    using PoolTickBitmap for IDepth.PoolVariables;

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
        int24 tickNext = poolVariables.findNextTick(poolVariables.tick, upper, sqrtPriceX96Tgt);
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
                // If not going upper, always push tickNext to the next word because we are on a word boundary.
                tickNext = tickNext - 1;
            }
            liquidityCurrent = LiquidityMath.addDelta(liquidityCurrent, liquidityNet);
            tickNext = poolVariables.findNextTick(tickNext, upper, sqrtPriceX96Tgt);

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
}
