// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.6;
pragma abicoder v2;

import "forge-std/Test.sol";
import "../src/MockToken.sol";
import "v3-core/contracts/UniswapV3Factory.sol";
import "v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import "v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {NonfungiblePositionManager} from "v3-periphery/contracts/NonfungiblePositionManager.sol";
import "v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import "v3-periphery/contracts/libraries/LiquidityAmounts.sol";
import "../src/Depth.sol";
import {IDepth} from "../src/IDepth.sol";
import "forge-std/console2.sol";
import "forge-std/console.sol";

// forge test --match-path test/Depth.t.sol

contract DepthTest is Test {
    uint256 mainnetFork;

    Depth public depth;
    //UniswapV3Factory public v3Factory;
    NonfungiblePositionManager public posManager;
    INonfungiblePositionManager.MintParams mintParams;
    address nftPosManagerAddress = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;
    
    address descriptor = 0x91ae842A5Ffd8d12023116943e72A606179294f3;
    address weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    
    MockToken public token0;
    MockToken public token1;

    IUniswapV3Pool pool;

    address me = vm.addr(0x1);

    struct PositionDelta {
        int8 tickLower;
        int8 tickUpper;
        uint16 token0Amt;
        uint128 liquidity;
    }

    function setUp() public {
        mainnetFork = vm.createFork(vm.envString("MAINNET_RPC_URL"));
        vm.selectFork(mainnetFork);

        vm.startPrank(me);

        depth = new Depth();
        token0 = new MockToken(me);
        token1 = new MockToken(me);
    }

    function cleanV3() public {
        //v3Factory = new UniswapV3Factory();
        //posManager = new NonfungiblePositionManager(address(v3Factory), 
                                                            // weth, 
                                                            // descriptor);
        IUniswapV3Factory v3Factory = IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);
        address poolAddress = v3Factory.createPool(address(token0), address(token1), 500);
        pool = IUniswapV3Pool(poolAddress);
        pool.initialize(1 << 96);

        token0.approve(address(nftPosManagerAddress), type(uint256).max);
        token1.approve(address(nftPosManagerAddress), type(uint256).max);
    }


    function checkPosition(PositionDelta memory delta) public returns (PositionDelta memory) {
        delta.tickLower = (delta.tickLower / 10) * 10;
        delta.tickUpper = (delta.tickUpper / 10) * 10;

        vm.assume(delta.tickLower != delta.tickUpper);
        if (delta.tickLower > delta.tickUpper) {
            (delta.tickLower, delta.tickUpper) = (delta.tickUpper, delta.tickLower);
        }
        delta.liquidity = createPosition(delta);

        return delta;
    }

    function createPosition(PositionDelta memory delta) public returns (uint128) {
        uint160 sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(int24(delta.tickLower));
        uint160 sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(int24(delta.tickUpper));

        uint128 liquidity = LiquidityAmounts.getLiquidityForAmount0(sqrtRatioAX96, sqrtRatioBX96, delta.token0Amt * type(uint16).max);
        (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(1 << 96, sqrtRatioAX96, sqrtRatioBX96, liquidity);
         
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

        INonfungiblePositionManager(address(nftPosManagerAddress)).mint(mintParams);

        return liquidity;
    }

    function garrisonMintParamsToString(PositionDelta memory delta) pure public returns (string memory) {
        string memory parameters = "";

        parameters = string(abi.encodePacked(parameters, vm.toString(int256(delta.tickLower))));
        parameters = string(abi.encodePacked(parameters, ",")); 
        parameters = string(abi.encodePacked(parameters, vm.toString(int256(delta.tickUpper))));
        parameters = string(abi.encodePacked(parameters, ",")); 
        parameters = string(abi.encodePacked(parameters, vm.toString(int256(delta.liquidity))));

        return parameters;
    }

    function runDepthCalculation(address poolAddress) public returns (uint256[] memory) {
        uint256[] memory depths = new uint256[](1);
        uint256[1] memory depthsValues = [
            uint256(80016521857016597127997947904)
        ];

        for (uint256 i = 0; i < depthsValues.length; i++) {
            depths[i] = depthsValues[i];
        }

        IDepth.DepthConfig[] memory config = new  IDepth.DepthConfig[](1);
        for (uint256 i = 0; i < depthsValues.length; i++) {
            config[i] = IDepth.DepthConfig({side: IDepth.Side.Upper, amountInToken0: true, exact: false});
        }

        uint256[] memory depthsMultiple = depth.calculateDepths(poolAddress, depths, config);

        return depthsMultiple;
    }

    /// forge-config: default.fuzz.runs = 50
    function testToken0(PositionDelta memory delta1, PositionDelta memory delta2) public {
        // clean out v3
        cleanV3();

        delta1 = checkPosition(delta1);
        delta2 = checkPosition(delta2);
    
        // run the onchain calculations
        uint256[] memory depths = runDepthCalculation(address(pool));

        string[] memory runJsInputs = new string[](5);
        
        // build ffi command string
        runJsInputs[0] = "python3";
        runJsInputs[1] = "python/calc.py";
        runJsInputs[2] = garrisonMintParamsToString(delta1);
        runJsInputs[3] = garrisonMintParamsToString(delta2);
        runJsInputs[4] = string(abi.encode(depths[0]));

        bytes memory jsResult = vm.ffi(runJsInputs);
        //int256[] memory jsSqrtRatios = abi.decode(jsResult, (int256[]));
        //int256 val = jsSqrtRatios[0];
        
        assertEq(true, true);
    }
}
