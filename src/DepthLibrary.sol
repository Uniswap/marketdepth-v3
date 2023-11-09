// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.6;

import {IDepth} from "./IDepth.sol";
import {FullMath} from "v3-core/contracts/libraries/FullMath.sol";
import {FixedPoint96} from "v3-core/contracts/libraries/FixedPoint96.sol";

library DepthLibrary {
    // 112045541949572287496682733568 = sqrt(2) * 2^96
    // The maximum depth calculated in the exact case is 100%.
    uint160 public constant MAX_DEPTH_EXACT = 112045541949572287496682733568;

    function getSqrtPriceX96Tgt(IDepth.DepthConfig memory config, uint160 sqrtPriceX96, uint256 sqrtDepthX96)
        internal
        pure
        returns (uint160 sqrtPriceX96Tgt)
    {
        if (config.side == IDepth.Side.Upper) {
            sqrtPriceX96Tgt = uint160(FullMath.mulDiv(sqrtPriceX96, sqrtDepthX96, FixedPoint96.Q96));
            require(sqrtPriceX96 <= sqrtPriceX96Tgt, "UpperboundOverflow");
        } else if (config.side == IDepth.Side.Lower) {
            sqrtPriceX96Tgt = uint160(FullMath.mulDiv(sqrtPriceX96, FixedPoint96.Q96, sqrtDepthX96));

            // Deflates the Side.Lower sqrtPriceX96Tgt
            if (config.side == IDepth.Side.LowerExact) {
                // TODO
                // Fix Comments
                // Make squares constants

                // we want to calculate deflator = (1-p)^2 / 2 to approximate (1-p) instead of 1/(1+p)
                // because 1 / (1 + p) * price * (1-deflator) = (1-p) * price
                // this is because of the taylor series expansion of these values
                // however we need to keep everything in integers, so we cannot directly calculate sqrt(1-p)
                require(sqrtDepthX96 < MAX_DEPTH_EXACT, "ExceededMaxDepth");

                uint256 deflator = (
                    sqrtDepthX96 * sqrtDepthX96 - (4 * (FixedPoint96.Q96)) - (FixedPoint96.Q96 * FixedPoint96.Q96)
                ) / (FixedPoint96.Q96);
                sqrtPriceX96Tgt = uint160(
                    FullMath.mulDiv(
                        sqrtPriceX96Tgt,
                        ((FixedPoint96.Q96 * FixedPoint96.Q96) - (deflator * deflator) / 2),
                        FixedPoint96.Q96 * FixedPoint96.Q96
                    )
                );
            }
        } else {
            revert("InvalidSideToCalculateTargetPrice");
        }
    }
}
