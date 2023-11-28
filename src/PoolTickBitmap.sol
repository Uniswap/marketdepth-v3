// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.7.6;

import {IUniswapV3Pool} from "v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {BitMath} from "v3-core/contracts/libraries/BitMath.sol";
import {IDepth} from "./IDepth.sol";
import {TickMath} from "v3-core/contracts/libraries/TickMath.sol";

/// @title Packed tick initialized state library
/// @notice Stores a packed mapping of tick index to its initialized state
/// @dev The mapping uses int16 for keys since ticks are represented as int24 and there are 256 (2^8) values per word.
library PoolTickBitmap {
    /// @notice Computes the position in the mapping where the initialized bit for a tick lives
    /// @param tick The tick for which to compute the position
    /// @return wordPos The key in the mapping containing the word in which the bit is stored
    /// @return bitPos The bit position in the word where the flag is stored

    function position(int24 tick) private pure returns (int16 wordPos, uint8 bitPos) {
        wordPos = int16(tick >> 8);
        bitPos = uint8(tick % 256);
    }

    /// @notice Returns the next initialized tick contained in the same word (or adjacent word) as the tick that is either
    /// to the left (less than or equal to) or right (greater than) of the given tick
    /// @param poolVars Depth from the pool variables
    /// @param tick The starting tick
    /// @param lte Whether to search for the next initialized tick to the left (less than or equal to the starting tick)
    /// @return next The next initialized or uninitialized tick up to 256 ticks away from the current tick
    /// @return initialized Whether the next tick is initialized, as the function only searches within up to 256 ticks
    function _nextInitializedTickWithinOneWord(IDepth.PoolVariables memory poolVars, int24 tick, bool lte)
        internal
        view
        returns (int24 next, bool initialized)
    {
        int24 compressed = tick / poolVars.tickSpacing;
        if (tick < 0 && tick % poolVars.tickSpacing != 0) compressed--; // round towards negative infinity

        if (lte) {
            (int16 wordPos, uint8 bitPos) = position(compressed);
            // all the 1s at or to the right of the current bitPos
            uint256 mask = (1 << bitPos) - 1 + (1 << bitPos);
            uint256 masked = IUniswapV3Pool(poolVars.pool).tickBitmap(wordPos) & mask;

            // if there are no initialized ticks to the right of or at the current tick, return rightmost in the word
            initialized = masked != 0;
            // overflow/underflow is possible, but prevented externally by limiting both tickSpacing and tick
            next = initialized
                ? (compressed - int24(bitPos - BitMath.mostSignificantBit(masked))) * poolVars.tickSpacing
                : (compressed - int24(bitPos)) * poolVars.tickSpacing;
        } else {
            // start from the word of the next tick, since the current tick state doesn't matter
            (int16 wordPos, uint8 bitPos) = position(compressed + 1);
            // all the 1s at or to the left of the bitPos
            uint256 mask = ~((1 << bitPos) - 1);
            uint256 masked = IUniswapV3Pool(poolVars.pool).tickBitmap(wordPos) & mask;

            // if there are no initialized ticks to the left of the current tick, return leftmost in the word
            initialized = masked != 0;
            // overflow/underflow is possible, but prevented externally by limiting both tickSpacing and tick
            next = initialized
                ? (compressed + 1 + int24(BitMath.leastSignificantBit(masked) - bitPos)) * poolVars.tickSpacing
                : (compressed + 1 + int24(type(uint8).max - bitPos)) * poolVars.tickSpacing;
        }
    }

    /// @dev This may return a tick beyond the tick at the sqrtPriceX96Tgt.
    /// Instead of truncating the tickNext returned if it goes beyond the sqrtPriceTarget, we check the boundaries in `calculateOneSide` because we need to calculate amounts to a price that may be between two ticks.
    function findNextTick(IDepth.PoolVariables memory poolVariables, int24 tick, bool upper, uint160 sqrtPriceX96Tgt)
        internal
        view
        returns (int24 tickNext)
    {
        bool initialized;
        (tickNext, initialized) = _nextInitializedTickWithinOneWord(poolVariables, tick, !upper);

        int24 tickMax =
            upper ? TickMath.getTickAtSqrtRatio(sqrtPriceX96Tgt) + 1 : TickMath.getTickAtSqrtRatio(sqrtPriceX96Tgt);

        // tick next at this point is either 
        // initialized (never enters this loop) or a word boundry
        while (!initialized && (upper ? tickNext < tickMax : tickNext > tickMax)) {
            (tickNext, initialized) = _nextInitializedTickWithinOneWord(poolVariables, upper ? tickNext : tickNext - 1, !upper);
        }
    }
}
