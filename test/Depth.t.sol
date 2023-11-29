// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.6;
pragma abicoder v2;

import "forge-std/Test.sol";
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

    // .25%, .5%, 1%, 2% depths
    // sqrt(1+.0025) * Q96, sqrt(1+.005) * Q96, sqrt(1+.01) * Q96, sqrt(1+.02) * Q96,
    uint256[4] depthsValues = [
        uint256(79327135897655778240513441792),
        uint256(79425985949584623951891398656),
        uint256(79623317895830908422001262592),
        uint256(80016521857016597127997947904)
    ];

    // we do them in reverse order bc 100 bps is the most likely to fail vm.assume
    uint24[4] feeTiers = [uint24(10000), uint24(3000), uint24(500), uint24(100)];

    address me = vm.addr(0x1);

    struct PositionDelta {
        int8 tickLower;
        int8 tickUpper;
        uint128 liquidityDelta;
    }

    struct ConfigurationParameters {
        bool amountInToken0;
        uint8 depthIdx;
        uint8 feeIdx;
    }

    uint256 constant ONE_PIP = 1e6;

    function setUp() public {
        mainnetFork = vm.createFork(vm.envString("MAINNET_RPC_URL"));
        vm.selectFork(mainnetFork);

        vm.startPrank(me);

        depth = new Depth();
        v3Factory = IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);
    }

    function createV3Pool(uint24 feeTier) public returns (address poolAddress) {
        // Deploy tokens and approve.
        MockToken token0 = new MockToken(me);
        MockToken token1 = new MockToken(me);

        token0.approve(address(nftPosManagerAddress), type(uint256).max);
        token1.approve(address(nftPosManagerAddress), type(uint256).max);

        poolAddress = v3Factory.createPool(address(token0), address(token1), feeTier);
        IUniswapV3Pool(poolAddress).initialize(1 << 96);
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

    function checkPosition(IUniswapV3Pool pool, PositionDelta memory delta) public returns (PositionDelta memory) {
        // we need the position to not round down
        vm.assume(delta.liquidityDelta > 1e9);

        // make sure we don't overflow liquidity per tick
        vm.assume(delta.liquidityDelta < (pool.maxLiquidityPerTick() / 2));

        int24 tickSpacing = pool.tickSpacing();
        // we want to sufficiently randomize but the pool requires that the ticks
        // are on the tick spacing - so we push them to the closest
        delta.tickLower = int8((int24(delta.tickLower) / tickSpacing) * tickSpacing);
        delta.tickUpper = int8((int24(delta.tickUpper) / tickSpacing) * tickSpacing);

        // tick have to be at least 1 tick spacing apart to not break
        vm.assume(delta.tickLower != delta.tickUpper);

        // we can just flip the ticks instead of re-attempting the fuzz
        if (delta.tickLower > delta.tickUpper) {
            (delta.tickLower, delta.tickUpper) = (delta.tickUpper, delta.tickLower);
        }
        // it is possible that the positions
        delta.liquidityDelta = createPosition(pool, delta);

        return delta;
    }

    function createPosition(IUniswapV3Pool pool, PositionDelta memory delta) public returns (uint128) {
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
        IDepth.Side side,
        ConfigurationParameters[] memory params
    ) public {
        address[] memory randomPools = new address[](params.length);
        uint256[] memory randomDepthValues = new uint256[](params.length);
        IDepth.DepthConfig[] memory randomDepthConfig = new IDepth.DepthConfig[](params.length);
        for (uint256 i = 0; i < params.length; i++) {
            ConfigurationParameters memory configParams = params[i];
            randomPools[i] = createV3Pool(feeTiers[configParams.feeIdx]);
            randomDepthValues[i] = depthsValues[configParams.depthIdx];
            randomDepthConfig[i] = IDepth.DepthConfig({side: side, amountInToken0: configParams.amountInToken0});
        }

        uint256[] memory solResults = depth.calculateDepths(randomPools, randomDepthValues, randomDepthConfig);
        // ffi cannot handle a return of 0
        for (uint256 i = 0; i < solResults.length; i++) {
            vm.assume(solResults[i] > 0);
        }
        uint256[] memory pyResults = calculateDepthsPython(delta1, delta2, side, params);

        for (uint256 i = 0; i < params.length; i++) {
            uint256 solDepth = solResults[i];
            uint256 pyDepth = pyResults[i];
            // check to see if the python returns within the floating point limit
            (uint256 gtResult, uint256 ltResult) = pyDepth > solDepth ? (pyDepth, solDepth) : (solDepth, pyDepth);
            uint256 resultsDiff = gtResult - ltResult;

            // assert solc/py result is at most off by 1/100th of a bip (aka one pip)
            assertEq(resultsDiff * ONE_PIP / pyDepth, 0);
        }
    }

    function calculateDepthsPython(
        PositionDelta memory delta1,
        PositionDelta memory delta2,
        IDepth.Side side,
        ConfigurationParameters[] memory params
    ) public returns (uint256[] memory pyResults) {
        pyResults = new uint256[](params.length);
        for (uint256 i = 0; i < params.length; i++) {
            ConfigurationParameters memory configParams = params[i];
            // Create python input command for this depth calculation.
            string[] memory runPyInputs = new string[](8);

            // build ffi command string
            runPyInputs[0] = "python3";
            runPyInputs[1] = "python/calc.py";
            runPyInputs[2] = garrisonMintParamsToString(delta1);
            runPyInputs[3] = garrisonMintParamsToString(delta2);
            runPyInputs[4] = tokenBooltoString(configParams.amountInToken0);
            runPyInputs[5] = sideToString(side);
            runPyInputs[6] = vm.toString(uint256(configParams.depthIdx)); // sqrtDepthX96
            runPyInputs[7] = vm.toString(uint256(configParams.feeIdx)); // feeTier

            // return the python result
            bytes memory pythonResult = vm.ffi(runPyInputs);
            pyResults[i] = abi.decode(pythonResult, (uint256));
        }
    }

    function truncateSearchSpace(uint8 feeIdx, uint8 depthIdx) public pure returns (uint8, uint8) {
        // we want to fuzz a choice between 4 values, but we don't know which one we will pick
        // we truncate down from 2^8 by dividing by 84 which approx a max of 3 (we cant divide by 64) bc
        // need 4 numbers not 5
        feeIdx = feeIdx / 84;
        depthIdx = depthIdx / 84;
        vm.assume(feeIdx <= 3);
        vm.assume(depthIdx <= 3);

        return (feeIdx, depthIdx);
    }

    /// forge-config: default.fuzz.runs = 200
    function testTokenBoth(
        PositionDelta memory delta1,
        PositionDelta memory delta2,
        ConfigurationParameters memory param
    ) public {
        ConfigurationParameters[] memory configParams = new ConfigurationParameters[](1);

        (uint8 feeIdx, uint8 depthIdx) = truncateSearchSpace(param.feeIdx, param.depthIdx);
        param.depthIdx = depthIdx;
        param.feeIdx = feeIdx;

        configParams[0] = param;

        runTest(delta1, delta2, IDepth.Side.Both, configParams);
    }

    /// forge-config: default.fuzz.runs = 200
    function testTokenLower(
        PositionDelta memory delta1,
        PositionDelta memory delta2,
        ConfigurationParameters memory param
    ) public {
        ConfigurationParameters[] memory configParams = new ConfigurationParameters[](1);

        (uint8 feeIdx, uint8 depthIdx) = truncateSearchSpace(param.feeIdx, param.depthIdx);
        param.depthIdx = depthIdx;
        param.feeIdx = feeIdx;

        configParams[0] = param;

        runTest(delta1, delta2, IDepth.Side.Lower, configParams);
    }

    /// forge-config: default.fuzz.runs = 200
    function testTokenUpper(
        PositionDelta memory delta1,
        PositionDelta memory delta2,
        ConfigurationParameters memory param
    ) public {
        ConfigurationParameters[] memory configParams = new ConfigurationParameters[](1);

        (uint8 feeIdx, uint8 depthIdx) = truncateSearchSpace(param.feeIdx, param.depthIdx);
        param.depthIdx = depthIdx;
        param.feeIdx = feeIdx;

        configParams[0] = param;

        runTest(delta1, delta2, IDepth.Side.Upper, configParams);
    }
}
