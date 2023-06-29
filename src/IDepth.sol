// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.6;
pragma abicoder v2;

/// @title IDepth
/// @notice Interface for calculating the market depth of a v3 pool.
interface IDepth {
    struct DepthConfig {
        // set to true if you want the entire depth range
        bool bothSides;
        // set to 0 for amount in token0, set to 1 for amount in token1
        bool token0;
        // ?? for the precise calculation.. tbh i think we should just always calculate exact?
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
