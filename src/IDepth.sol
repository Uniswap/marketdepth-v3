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
        Both // Both auto executes logic for depth on Side.Lower and Side.Upper.
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

    /// @notice Calculates the market depth (the amount available to trade in or out) for the requested pools
    /// @param pool The address of the pool to calculate market depth in
    /// @param sqrtDepthX96 An array of depths to calculate
    /// @param configs An array of depth configuration for each depth calculation
    /// @return amounts The market depth of the pool with the requested depth and using the provided config
    function calculateDepths(address pool, uint256[] memory sqrtDepthX96, DepthConfig[] memory configs)
        external
        returns (uint256[] memory amounts);
}
