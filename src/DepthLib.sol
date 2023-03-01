// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.6;

import {DepthConfig} from "./Depth.sol";

library DepthLib {
    function setInitialPrices(DepthConfig memory config, uint160 sqrtPriceX96)
        internal
        returns (uint160 sqrtPriceX96Current, uint128 sqrtPriceX96Tgt)
    {
        if (config.bothSides) {
            // if both, current is lower and target the upper range and we just move upwards
            sqrtPriceX96Current = uint128(FullMath.mulDiv(sqrtPriceX96, 1 << 96, sqrtDepthX96));
            sqrtPriceX96Tgt = uint128(FullMath.mulDiv(sqrtPriceX96, sqrtDepthX96, 1 << 96));
        } else {
            // if upper is true, set current to price and tgt to upper
            // if upper is false, set current to lower and tgt to price
            sqrtPriceX96Current =
                config.upper ? sqrtPriceX96 : uint128(FullMath.mulDiv(sqrtPriceX96, sqrtDepthX96, 1 << 96));
            sqrtPriceX96Tgt =
                config.upper ? uint128(FullMath.mulDiv(sqrtPriceX96, sqrtDepthX96, 1 << 96)) : sqrtPriceX96;
        }
    }
}
