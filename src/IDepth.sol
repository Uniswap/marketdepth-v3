// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.6;
pragma abicoder v2;

/// @title IDepth
/// @notice Interface for calculating the market depth of a v3 pool.
interface IDepth {
    // The side of the range you want the depth for, either lower, upper, or depth on both sides.
    enum Side {
        Lower,
        Upper,
        Both
    }

    struct DepthConfig {
        Side side;
        // Set to true for amount in token0, set to false for amount in token1
        bool amountInToken0;
        // Set to true for the precise calculation.
        bool exact;
    }

    struct PoolVariables {
        int24 tick;
        int24 tickSpacing;
        uint128 liquidity;
        uint160 sqrtPriceX96;
        address pool;
    }

    function calculateDepths(address pool, uint256[] memory sqrtDepthX96, DepthConfig[] memory configs)
        external
        returns (uint256[] memory amounts);
}
