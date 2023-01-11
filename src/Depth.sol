// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.6;

import {IUniswapV3Pool} from 'v3-core/contracts/interfaces/IUniswapV3Pool.sol';
import {FullMath} from 'v3-core/contracts/libraries/FullMath.sol';
import {TickMath} from 'v3-core/contracts/libraries/TickMath.sol';
import {SqrtPriceMath} from 'v3-core/contracts/libraries/SqrtPriceMath.sol';
import {LiquidityMath}  from 'v3-core/contracts/libraries/LiquidityMath.sol';


contract Depth {

    function calculateLowerAmt0(address poolAddress, uint256 sqrtDepthX96
                   ) public view returns (uint256) {
        
        IUniswapV3Pool pool = IUniswapV3Pool(address(poolAddress));

        // load current state variables
        (uint160 sqrtPriceX96, int24 curTick,,,,,) = pool.slot0();
        uint128 liquidity = pool.liquidity();
        int24 tickSpacing = pool.tickSpacing();
        
        // calculate sqrtPriceRatios at the given depth
        uint128 sqrtPriceX96Above = uint128(FullMath.mulDiv(sqrtPriceX96, sqrtDepthX96, 1 << 96));
        uint128 sqrtPriceX96Below = uint128(FullMath.mulDiv(sqrtPriceX96, 1 << 96, sqrtDepthX96));
        uint160 sqrtPriceRatioNext = sqrtPriceX96;
        
        // set up incrimental variables
        uint256 amt0 = 0;
        int128 liquidityNet = 0;

        // determine lower tick of current range
        int24 tickNext = (curTick / tickSpacing) * tickSpacing;

        while (sqrtPriceX96Below < sqrtPriceRatioNext) {
            sqrtPriceRatioNext = TickMath.getSqrtRatioAtTick(tickNext);

            if (sqrtPriceRatioNext < sqrtPriceX96Below) {
                sqrtPriceRatioNext = sqrtPriceX96Below;
            }

            uint256 deltaAmt0 = SqrtPriceMath.getAmount0Delta(sqrtPriceX96, sqrtPriceRatioNext, liquidity, false);
            amt0 = amt0 + deltaAmt0;
        
            // shift to one tick spacing lower
            tickNext = ((tickNext / tickSpacing) - 1 ) * tickSpacing;
            (, liquidityNet,,,,,,)  = pool.ticks(tickNext);
            sqrtPriceX96 = sqrtPriceRatioNext;
            liquidity = LiquidityMath.addDelta(liquidity, -liquidityNet);
        }

        return amt0;
    }
}