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
    IUniswapV3Pool pool;

    address me = vm.addr(0x1);

    struct PositionDelta {
        int8 tickLower;
        int8 tickUpper;
        uint8 token0Amt;
        uint128 liquidity;
    }

    uint256 constant ONE_PIP = 1e6;

    function setUp() public {
        mainnetFork = vm.createFork(vm.envString("MAINNET_RPC_URL"));
        vm.selectFork(mainnetFork);

        vm.startPrank(me);

        depth = new Depth();
        v3Factory = IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);
    }

    function setV3Pools() public {
        // deploy new tokens to create clean pools
        MockToken token0 = new MockToken(me);
        MockToken token1 = new MockToken(me);

        address poolAddress = v3Factory.createPool(address(token0), address(token1), 500);
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
        vm.assume(delta.token0Amt > 0);

        // we want to sufficiently randomize but the pool requires that the ticks
        // are on the tick spacing - so we push them to the closest
        delta.tickLower = (delta.tickLower / 10) * 10;
        delta.tickUpper = (delta.tickUpper / 10) * 10;

        // tick have to be at least 1 tick spacing apart to not break
        vm.assume(delta.tickLower != delta.tickUpper);

        // we can just flip the ticks instead of re-attempting the fuzz
        if (delta.tickLower > delta.tickUpper) {
            (delta.tickLower, delta.tickUpper) = (delta.tickUpper, delta.tickLower);
        }
        delta.liquidity = createPosition(delta);

        return delta;
    }

    function createPosition(PositionDelta memory delta) public returns (uint128) {
        uint160 sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(int24(delta.tickLower));
        uint160 sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(int24(delta.tickUpper));

        // its easier to make sure that we have the expected numbers by going from tokens
        // to liquidity
        uint128 liquidity = LiquidityAmounts.getLiquidityForAmount0(
            sqrtRatioAX96, sqrtRatioBX96, uint128(delta.token0Amt) * uint128(type(uint64).max)
        );
        // make sure we don't overflow liquidity per tick
        if (liquidity > pool.maxLiquidityPerTick()) {
            liquidity = pool.maxLiquidityPerTick();
        }

        // we then overwrite to get on a specific liquidity value
        (uint256 amount0, uint256 amount1) =
            LiquidityAmounts.getAmountsForLiquidity(1 << 96, sqrtRatioAX96, sqrtRatioBX96, liquidity);

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

        INonfungiblePositionManager(nftPosManagerAddress).mint(mintParams);

        return liquidity;
    }

    function garrisonMintParamsToString(PositionDelta memory delta) public pure returns (string memory) {
        string memory parameters = "";

        parameters = string(abi.encodePacked(parameters, vm.toString(int256(delta.tickLower))));
        parameters = string(abi.encodePacked(parameters, ","));
        parameters = string(abi.encodePacked(parameters, vm.toString(int256(delta.tickUpper))));
        parameters = string(abi.encodePacked(parameters, ","));
        parameters = string(abi.encodePacked(parameters, vm.toString(int256(delta.liquidity))));

        return parameters;
    }

    function runTest(PositionDelta memory delta1, PositionDelta memory delta2, bool token0, IDepth.Side side) public {
        setV3Pools();

        delta1 = checkPosition(delta1);
        delta2 = checkPosition(delta2);

        // this is 2% depth - we could try other sizes
        uint256 sqrtPriceRatioX96 = 80016521857016597127997947904;

        // run the solidity contract
        uint256[] memory solResults = runDepthCalculation(address(pool), sqrtPriceRatioX96, token0, side);
        uint256 solResult = solResults[0];

        // ffi cannot handle a return of 0
        vm.assume(solResult > 0);

        // create the string array to putting into ffi
        string[] memory runPyInputs = new string[](6);

        // build ffi command string
        runPyInputs[0] = "python3";
        runPyInputs[1] = "python/calc.py";
        runPyInputs[2] = garrisonMintParamsToString(delta1);
        runPyInputs[3] = garrisonMintParamsToString(delta2);
        runPyInputs[4] = tokenBooltoString(token0);
        runPyInputs[5] = sideToString(side);

        // return the python result
        bytes memory pythonResult = vm.ffi(runPyInputs);
        uint256 pyDepth = abi.decode(pythonResult, (uint256));

        // check to see if the python returns within the floating point limit 
        (uint256 gtResult, uint256 ltResult) = pyDepth > solResult ? (pyDepth, solResult) : (solResult, pyDepth);
        uint256 resultsDiff = gtResult - ltResult;

        // assert solc/py result is at most off by 1/100th of a bip (aka one pip)
        assertEq(resultsDiff * ONE_PIP / pyDepth, 0);
    }

    /// forge-config: default.fuzz.runs = 50
    function testTokenBoth(PositionDelta memory delta1, PositionDelta memory delta2, bool token0) public {
        runTest(delta1, delta2, token0, IDepth.Side.Both);
    }

    /// forge-config: default.fuzz.runs = 50
    function testTokenLower(PositionDelta memory delta1, PositionDelta memory delta2, bool token0) public {
        runTest(delta1, delta2, token0, IDepth.Side.Lower);
    }

    /// forge-config: default.fuzz.runs = 50
    function testTokenUpper(PositionDelta memory delta1, PositionDelta memory delta2, bool token0) public {
        runTest(delta1, delta2, token0, IDepth.Side.Upper);
    }
}
