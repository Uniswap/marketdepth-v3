// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.6;
pragma abicoder v2;

import {Test, console, console2} from "forge-std/Test.sol";
import "../src/MockToken.sol";
import "v3-core/contracts/UniswapV3Factory.sol";
import "v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import "v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import "v3-periphery/contracts/libraries/LiquidityAmounts.sol";
import "../src/Depth.sol";
import {IDepth} from "../src/IDepth.sol";

contract DepthTest is Test {
    uint256 mainnetFork;
    Depth public depth;

    address nftPosManagerAddress = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;
    INonfungiblePositionManager.MintParams mintParams;
    IUniswapV3Factory v3Factory;
    IUniswapV3Pool pool;

    // .25%, .5%, 1%, 2%, 5%, 10% depths
    // sqrt(1+.0025) * Q96, sqrt(1+.005) * Q96, sqrt(1+.01) * Q96, sqrt(1+.02) * Q96,
    uint256[6] depthsValues = [
        uint256(79327135897655778240513441792),
        uint256(79425985949584623951891398656),
        uint256(79623317895830908422001262592),
        uint256(80016521857016597127997947904),
        uint256(81184708056111256723576061952),
        uint256(83095197869223164535776477184)
    ];

    // we do them in reverse order bc 100 bps is the most likely to fail vm.assume
    uint24[4] feeTiers = [uint24(10000), uint24(3000), uint24(500), uint24(100)];

    address me = vm.addr(0x1);

    struct PositionDelta {
        int16 tickLower;
        int16 tickUpper;
        uint128 liquidityDelta;
    }

    uint256 constant ONE_PIP = 1e6;

    function setUp() public {
        mainnetFork = vm.createFork(vm.envString("MAINNET_RPC_URL"));
        vm.selectFork(mainnetFork);

        vm.startPrank(me);

        depth = new Depth();
        v3Factory = IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);
    }

    function setV3Pools(uint24 feeTier) public {
        // deploy new tokens to create clean pools
        MockToken token0 = new MockToken(me);
        MockToken token1 = new MockToken(me);

        address poolAddress = v3Factory.createPool(address(token0), address(token1), feeTier);
        pool = IUniswapV3Pool(poolAddress);
        pool.initialize(1 << 96);

        token0.approve(address(nftPosManagerAddress), type(uint256).max);
        token1.approve(address(nftPosManagerAddress), type(uint256).max);
    }

    function sideToString(IDepth.Side side) public pure returns (string memory) {
        string memory sideString;
        if (side == IDepth.Side.Lower) {
            sideString = "lower";
        } else if (side == IDepth.Side.Upper) {
            sideString = "upper";
        } else if (side == IDepth.Side.Both) {
            sideString = "both";
        }

        return sideString;
    }

    function tokenBooltoString(bool token) public pure returns (string memory) {
        string memory token_type;
        if (token) {
            token_type = "0";
        } else {
            token_type = "1";
        }

        return token_type;
    }

    function runDepthCalculation(address poolAddress, uint256 sqrtPriceRatioX96, bool amountInToken0, IDepth.Side side)
        public
        view
        returns (uint256[] memory)
    {
        uint256[] memory depths = new uint256[](1);

        for (uint256 i = 0; i < depths.length; i++) {
            depths[i] = sqrtPriceRatioX96;
        }

        IDepth.DepthConfig[] memory config = new IDepth.DepthConfig[](1);
        for (uint256 i = 0; i < depths.length; i++) {
            config[i] = IDepth.DepthConfig({side: side, amountInToken0: amountInToken0, exact: false});
        }

        uint256[] memory depthsMultiple = depth.calculateDepths(poolAddress, depths, config);

        return depthsMultiple;
    }

    function checkPosition(PositionDelta memory delta) public returns (PositionDelta memory) {
        // we need the position to not round down (due to FFI constraints)
        vm.assume(delta.liquidityDelta > 1e9);

        // make sure we don't overflow liquidity per tick
        vm.assume(delta.liquidityDelta < (pool.maxLiquidityPerTick() / 2));

        int24 tickSpacing = pool.tickSpacing();

        // tick in our fuzzer are between -32,768 and 32,767 (int16)
        // the max depth that we are testing is ~(-1000, 1000), thus thus we 
        // truncate to -32,768 / 32 = -1,024 and 32,767 // 32 = 1023, 
        // which are approx in our range for testing
        delta.tickLower = int16(delta.tickLower) / int16(1 << 5);
        delta.tickUpper = int16(delta.tickUpper) / int16(1 << 5);

        // we want to sufficiently randomize but the pool requires that the ticks
        // are on the tick spacing - so we push them to the closest
        delta.tickLower = int16((int24(delta.tickLower) / tickSpacing) * tickSpacing);
        delta.tickUpper = int16((int24(delta.tickUpper) / tickSpacing) * tickSpacing);

        // tick have to be at least 1 tick spacing apart to not break
        vm.assume(delta.tickLower != delta.tickUpper);

        // we can just flip the ticks instead of re-attempting the fuzz
        if (delta.tickLower > delta.tickUpper) {
            (delta.tickLower, delta.tickUpper) = (delta.tickUpper, delta.tickLower);
        }
        // the liquidity delta may not be on a grid, but this is highly dependent
        // on the make up of the pool - we instead calculate the closet liquidity
        // value that is on the grid and return it
        delta.liquidityDelta = createPosition(delta);

        return delta;
    }

    function createPosition(PositionDelta memory delta) public returns (uint128) {
        uint160 sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(int24(delta.tickLower));
        uint160 sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(int24(delta.tickUpper));

        // calculate the tokens needed for this level of liquidity
        (uint256 amount0, uint256 amount1) =
            LiquidityAmounts.getAmountsForLiquidity(1 << 96, sqrtRatioAX96, sqrtRatioBX96, delta.liquidityDelta);

        mintParams = INonfungiblePositionManager.MintParams({
            token0: pool.token0(),
            token1: pool.token1(),
            fee: pool.fee(),
            tickLower: int24(delta.tickLower),
            tickUpper: int24(delta.tickUpper),
            amount0Desired: amount0,
            amount1Desired: amount1,
            amount0Min: 0,
            amount1Min: 0,
            recipient: me,
            deadline: block.timestamp + 100
        });

        (, uint128 liquidity,,) = INonfungiblePositionManager(nftPosManagerAddress).mint(mintParams);

        return liquidity;
    }

    function garrisonMintParamsToString(PositionDelta memory delta) public pure returns (string memory) {
        string memory parameters = "";

        parameters = string(abi.encodePacked(parameters, vm.toString(int256(delta.tickLower))));
        parameters = string(abi.encodePacked(parameters, ","));
        parameters = string(abi.encodePacked(parameters, vm.toString(int256(delta.tickUpper))));
        parameters = string(abi.encodePacked(parameters, ","));
        parameters = string(abi.encodePacked(parameters, vm.toString(int256(delta.liquidityDelta))));

        return parameters;
    }

    function runTest(
        PositionDelta memory delta1,
        PositionDelta memory delta2,
        bool token0,
        IDepth.Side side,
        uint256 depthIdx,
        uint256 feeIdx
    ) public {
        // set up the pools and try data
        setV3Pools(feeTiers[feeIdx]);
        delta1 = checkPosition(delta1);
        delta2 = checkPosition(delta2);

        // run the solidity contract
        uint256 sqrtDepthX96 = depthsValues[depthIdx];

        uint256[] memory solResults = runDepthCalculation(address(pool), sqrtDepthX96, token0, side);
        uint256 solResult = solResults[0];

        // ffi cannot handle a return of 0
        vm.assume(solResult > 0);

        // create the string array to putting into ffi
        string[] memory runPyInputs = new string[](8);

        // build ffi command string
        runPyInputs[0] = "python3";
        runPyInputs[1] = "python/calc.py";
        runPyInputs[2] = garrisonMintParamsToString(delta1);
        runPyInputs[3] = garrisonMintParamsToString(delta2);
        runPyInputs[4] = tokenBooltoString(token0);
        runPyInputs[5] = sideToString(side);
        runPyInputs[6] = vm.toString(depthIdx); // sqrtDepthX96
        runPyInputs[7] = vm.toString(feeIdx); // feeTier

        // return the python result
        bytes memory pythonResult = vm.ffi(runPyInputs);
        uint256 pyDepth = abi.decode(pythonResult, (uint256));

        // check to see if the python returns within the floating point limit
        (uint256 gtResult, uint256 ltResult) = pyDepth > solResult ? (pyDepth, solResult) : (solResult, pyDepth);
        uint256 resultsDiff = gtResult - ltResult;

        // assert solc/py result is at most off by 1/100th of a bip (aka one pip)
        // or assert that it is at most 1 token off (due to integer rounding)
        // 1 token is the smallest possible difference, but may be larger than 1 pip
        if (resultsDiff == 1) {
            assertEq(resultsDiff, 1);
        } else {
            assertEq(resultsDiff * ONE_PIP / pyDepth, 0);
        }
    }

    function truncateSearchSpace(uint8 feeIdx, uint8 depthIdx) public pure returns (uint8, uint8) {
        // we want to fuzz a choice between 4 values, but we don't know which one we will pick
        // we truncate down from 2^8 by dividing by 84 which approx a max of 3 (we cant divide by 64) bc
        // need 4 numbers not 5
        feeIdx = feeIdx / 84;
        vm.assume(feeIdx <= 3);

        // we need 6 choices for the depth (256 / 51 is close to 5)
        depthIdx = depthIdx / 51;
        vm.assume(depthIdx <= 5);

        return (feeIdx, depthIdx);
    }

    /// forge-config: default.fuzz.runs = 200
    function testTokenBoth(
        PositionDelta memory delta1,
        PositionDelta memory delta2,
        bool token0,
        uint8 feeIdx,
        uint8 depthIdx
    ) public {
        (feeIdx, depthIdx) = truncateSearchSpace(feeIdx, depthIdx);

        runTest(delta1, delta2, token0, IDepth.Side.Both, depthIdx, feeIdx);
    }

    /// forge-config: default.fuzz.runs = 200
    function testTokenLower(
        PositionDelta memory delta1,
        PositionDelta memory delta2,
        bool token0,
        uint8 feeIdx,
        uint8 depthIdx
    ) public {
        (feeIdx, depthIdx) = truncateSearchSpace(feeIdx, depthIdx);

        runTest(delta1, delta2, token0, IDepth.Side.Lower, depthIdx, feeIdx);
    }

    /// forge-config: default.fuzz.runs = 200
    function testTokenUpper(
        PositionDelta memory delta1,
        PositionDelta memory delta2,
        bool token0,
        uint8 feeIdx,
        uint8 depthIdx
    ) public {
        (feeIdx, depthIdx) = truncateSearchSpace(feeIdx, depthIdx);

        runTest(delta1, delta2, token0, IDepth.Side.Upper, depthIdx, feeIdx);
    }
}
