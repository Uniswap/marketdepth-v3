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
        } else {
            revert("InvalidSideToCalculateTargetPrice");
        }
    }
}
