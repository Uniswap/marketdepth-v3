// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.6;

import {IUniswapV3Pool} from "v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {FullMath} from "v3-core/contracts/libraries/FullMath.sol";
import {TickMath} from "v3-core/contracts/libraries/TickMath.sol";
import {SqrtPriceMath} from "v3-core/contracts/libraries/SqrtPriceMath.sol";
import {LiquidityMath} from "v3-core/contracts/libraries/LiquidityMath.sol";

contract Depth {
    using DepthLib for DepthConfig;

    error LengthMismatch();
    struct PoolVariables {
        int24 tick;
        int24 tickSpacing;
        uint128 liquidity;
        uint160 sqrtPriceX96;
    }

    struct DepthConfig {
        // set to true if you want the entire depth range
        bool bothSides;
        // set to 0 for amount in token0, set to 1 for amount in token1
        bool token0;
        // if bothSides == false, set the direction of the depth calculation
        // if false, will do lower range, if true does upper range
        bool upper;
        // ?? for the precise calculation.. tbh i think we should just always calculate exact?
        bool exact;
    }

    // todo input granular depth amounts 
    function calculateDepths(address pool, uint256[] calldata sqrtDepthX96, DepthConfig[] calldata configs)
        external
        returns (uint256[] amounts)
    {
        if (depths.length != configs.length) revert LengthMismatch();
        amounts = new uint256[](depths.length);

        PoolVariables memory pool = initializePoolVariables(pool);

        for (uint256 i = 0; i < depths.length; i++) {
            amounts[i] = calculateDepthAmount(poolVar, config[i]);
        }
        return amounts;
    }

    function calculateDepthAmount(PoolVariables memory poolVar, DepthConfig memory config)
        internal
        returns (uint256 amount)
    {
        // instead of calculating one side lets just use the both bool to figure out the range we need to calculate
        // idea: why dont we just always calculate up?
        // why are these not the same uint?
        uint160 sqrtPriceX96Current;
        uint128 sqrtPriceX96Tgt;

        (sqrtPriceX96Current, sqrtPriceX96Tgt) = config.setInitialPrices(sqrtPriceX96);

        uint256 amount = 0;
        uint160 sqrtPriceX96Next;
        // this might be wrong actually...
        int24 tickNext = ((poolVars.tick / poolVars.tickSpacing) + 1) * poolVars.tickSpacing;
        uint128 liquiditySpot = poolVars.liquidity;

        while (sqrtPriceX96Current < sqrtPriceX96Tgt) {
            // skipping exact rn bc idk what that is

            sqrtPriceX96Next = TickMath.getSqrtRatioAtTick(tickNext);
            if (sqrtPriceX96Next > sqrtPriceX96Tgt) {
                // handles when CURRENT < TARGET but NEXT > TARGET
                sqrtPriceX96Next = sqrtPriceX96Tgt;
            }

            amount += config.token0
                ? SqrtPriceMath.getAmount0Delta(sqrtPriceX96Current, sqrtPriceX96Next, liquiditySpot, false)
                : SqrtPriceMath.getAmount1Delta(sqrtPriceX96Current, sqrtPriceX96Next, liquiditySpot, false);

            // update liquidity before next tick
            (, liquidityNet,,,,,,) = pool.ticks(tickNext);
            liquiditySpot = LiquidityMath.addDelta(liquiditySpot, liquidityNet);

            // update tick
            tickNext = ((tickNext / poolVars.tickSpacing) + 1) * poolVars.tickSpacing;

            // update price
            sqrtPriceX96Current = sqrtPriceX96Next;
        }
        return amount;
    }

    function initializePoolVariables(address poolAddress) private returns (PoolVariables memory poolVars) {
        IUniswapV3Pool memory pool = IUniswapV3Pool(address(poolAddress));

        int24 tick;
        uint160 sqrtPriceX96;
        // load data into global memory
        (sqrtPriceX96, tick,,,,,) = pool.slot0(); // sload, sstore

        poolVars = PoolVariables({tick: tick, tickSpacing: pool.tickSpacing(), liquidity: pool.liquidity(), sqrtPriceX96});
    }

}
