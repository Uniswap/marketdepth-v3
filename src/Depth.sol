// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.6;

import {IUniswapV3Pool} from "v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {FullMath} from "v3-core/contracts/libraries/FullMath.sol";
import {TickMath} from "v3-core/contracts/libraries/TickMath.sol";
import {SqrtPriceMath} from "v3-core/contracts/libraries/SqrtPriceMath.sol";
import {LiquidityMath} from "v3-core/contracts/libraries/LiquidityMath.sol";
import {DepthLib} from "./DepthLib.sol";
import {IDepth} from "./IDepth.sol";

contract Depth is IDepth {
    using DepthLib for IDepth.DepthConfig;

    // error LengthMismatch();

    // todo input granular depth amounts
    function calculateDepths(address pool, uint256[] memory sqrtDepthX96, DepthConfig[] memory configs)
        external
        returns (uint256[] memory amounts)
    {
        if (sqrtDepthX96.length != configs.length) revert("LengthMismatch"); //revert LengthMismatch();
        amounts = new uint256[](sqrtDepthX96.length);

        IDepth.PoolVariables memory pool = initializePoolVariables(pool);

        for (uint256 i = 0; i < sqrtDepthX96.length; i++) {
            amounts[i] = calculateDepthAmount(pool, configs[i], sqrtDepthX96[i]);
        }
        return amounts;
    }

    function calculateDepthAmount(PoolVariables memory poolVar, DepthConfig memory config, uint256 sqrtDepthX96)
        internal
        returns (uint256 amount)
    {
        // instead of calculating one side lets just use the both bool to figure out the range we need to calculate
        // idea: why dont we just always calculate up?
        // why are these not the same uint?
        uint160 sqrtPriceX96Current;
        uint160 sqrtPriceX96Tgt;

        (sqrtPriceX96Current, sqrtPriceX96Tgt) = config.setInitialPrices(poolVar.sqrtPriceX96, sqrtDepthX96);

        uint256 amount = 0;
        uint160 sqrtPriceX96Next;
        uint128 liquidityGross;
        // calculates the lower bounds closest tick, then calculates the top of that tick-range
        int24 tickNext =
            ((TickMath.getTickAtSqrtRatio(sqrtPriceX96Tgt) / poolVar.tickSpacing) + 1) * poolVar.tickSpacing;
        (liquidityGross,,,,,,,) = IUniswapV3Pool(poolVar.pool).ticks(tickNext);

        while (sqrtPriceX96Current < sqrtPriceX96Tgt) {
            sqrtPriceX96Next = TickMath.getSqrtRatioAtTick(tickNext);
            if (sqrtPriceX96Next > sqrtPriceX96Tgt) {
                // handles when CURRENT < TARGET but NEXT > TARGET
                sqrtPriceX96Next = sqrtPriceX96Tgt;
            }

            amount += config.token0
                ? SqrtPriceMath.getAmount0Delta(sqrtPriceX96Current, sqrtPriceX96Next, liquidityGross, false)
                : SqrtPriceMath.getAmount1Delta(sqrtPriceX96Current, sqrtPriceX96Next, liquidityGross, false);

            // TODO: we don't need this updating after the last run of the contract
            // we could instead exit early

            int128 liquidityNet;

            // update liquidity before next tick
            (, liquidityNet,,,,,,) = IUniswapV3Pool(poolVar.pool).ticks(tickNext);
            liquidityGross = LiquidityMath.addDelta(liquidityGross, liquidityNet);

            // update tick upward
            tickNext = ((tickNext / poolVar.tickSpacing) + 1) * poolVar.tickSpacing;

            // update price
            sqrtPriceX96Current = sqrtPriceX96Next;
        }
        return amount;
    }

    function initializePoolVariables(address poolAddress) private returns (PoolVariables memory poolVar) {
        IUniswapV3Pool pool = IUniswapV3Pool(address(poolAddress));

        int24 tick;
        uint160 sqrtPriceX96;
        // load data into global memory
        (sqrtPriceX96, tick,,,,,) = pool.slot0(); // sload, sstore

        poolVar = PoolVariables({
            tick: tick,
            tickSpacing: pool.tickSpacing(),
            liquidity: pool.liquidity(),
            sqrtPriceX96: sqrtPriceX96,
            pool: poolAddress
        });
    }
}
