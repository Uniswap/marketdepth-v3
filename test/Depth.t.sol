// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.6;
pragma abicoder v2;

import "forge-std/Test.sol";
import "../src/TestToken.sol";
import 'v3-core/contracts/interfaces/IUniswapV3Factory.sol';
import 'v3-core/contracts/interfaces/IUniswapV3Pool.sol';
import 'v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol';
import 'v3-periphery/contracts/interfaces/IQuoterV2.sol';
import "../src/Depth.sol";
import {IDepth} from "../src/IDepth.sol";

contract CounterTest is Test {
    uint256 mainnetFork;

    TestToken public token0;
    TestToken public token1;

    address poolAddress;
    IUniswapV3Factory v3Factory;
    IUniswapV3Pool pool;
    INonfungiblePositionManager nftPosManager;

    address nftPosManagerAddress = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;
    address me = vm.addr(0x1);
    INonfungiblePositionManager.MintParams mintParams;

    Depth public depth;

    // this is the lower limit for floating point arithmetic
    uint256 toleranceTrue = 1e10;
    // we approximate the  difference so is it not as accurate. this equals 10 bps
    uint256 toleranceApprox = 1e13;
    uint256 offchainCalculation;
    uint256 pctDiff;

    function evalulatePct(uint256 offchain, uint256 onchain) public returns (uint256) {
        return offchain > onchain ? ((offchain - onchain) * 1e18 / onchain)
                                  : ((onchain - offchain) * 1e18 / offchain);
    }

    function createV3() public {
        uint256 MAX_INT = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
        v3Factory = IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);
        nftPosManager = INonfungiblePositionManager(nftPosManagerAddress);

        token0 = new TestToken("Test Token1", 'T1');
        token1 = new TestToken("Test Token2", 'T2');

        poolAddress = v3Factory.createPool(address(token0), address(token1), 500);
        pool = IUniswapV3Pool(poolAddress);
        pool.initialize(1 << 96);

        token0.approve(nftPosManagerAddress, MAX_INT);
        token1.approve(nftPosManagerAddress, MAX_INT);

        mintParams = INonfungiblePositionManager.MintParams({
            token0: pool.token0(),
            token1: pool.token1(),
            fee: pool.fee(),
            tickLower: -500,
            tickUpper: 500,
            amount0Desired: 100000e18,
            amount1Desired: 100000e18,
            amount0Min: 0,
            amount1Min: 0,
            recipient: me,
            deadline: block.timestamp + 100
        });
        
        // create a position
        // liquidity = 4050408317414413260938526
        nftPosManager.mint(mintParams);

        // create a second position
        mintParams.tickLower = 0;
        mintParams.tickUpper = 50;
        // liquidity = 40052020798957899520605299
        nftPosManager.mint(mintParams);
    }      

    function setUp() public {
        mainnetFork = vm.createFork(vm.envString("MAINNET_RPC_URL"));
        vm.selectFork(mainnetFork);
        vm.startPrank(me);

        depth = new Depth();

        createV3();
    }

    function testDepthsToken0() public {
        // testing against theoretical depth calculations from off-chain
        // liquidityLow = 4050408317414413260938526 or liquidity from ticks [-500, 0] U [50, 500] 
        // liquidityHigh = 44102429116372312781543825 or liquidity from ticks [0, 50]
        //
        // .025% depth = 55024886201110690267136
        // 55024886201110690267136 = (((sqrt(1 * 1.0025) - 1) / (sqrt(1 * 1.0025) * 1)) * liquidityHigh
        //
        // .05% depth = 109844327765827609690112
        // 109844327765827609690112 = ((sqrt(1 * 1.005) - 1) / (sqrt(1 * 1.005) * 1)) * liquidityHigh
        //
        // 1% depth = 120101406051197037576192
        // 120101406051197037576192 = ((sqrt(1.0001 ** 50) - 1) / (sqrt(1.0001 ** 50) * 1)) * liquidityHigh + ((sqrt(1 * 1.01) - sqrt(1.0001 ** 50)) / (sqrt(1 * 1.01) * sqrt(1.0001 ** 50))) * liquidityLow

        // 2% depth = 139906473874238226825216
        // 139906473874238226825216 = ((sqrt(1.0001 ** 50) - 1) / (sqrt(1.0001 ** 50) * 1)) * liquidityHigh + ((sqrt(1 * 1.02) - sqrt(1.0001 ** 50)) / (sqrt(1 * 1.02) * sqrt(1.0001 ** 50))) * liquidityLow
        // .025%, .05%, 1%, 2%
        uint256[] memory depths = new uint256[](4);
        uint256[4] memory depthsValues = [uint256(79327135897655778240513441792),
                                        uint256(79425985949584623951891398656),
                                        uint256(79623317895830908422001262592),
                                        uint256(80016521857016597127997947904)];
                                        
        for (uint256 i=0; i<4; i++){
            depths[i] = depthsValues[i];
        }

        IDepth.DepthConfig[] memory config = new  IDepth.DepthConfig[](4);
        for (uint256 i=0; i<4; i++){
            config[i] = IDepth.DepthConfig({
                                            bothSides: false,
                                            token0: true,
                                            exact: false
                                        });
        }


        uint256[] memory depthsMultiple = depth.calculateDepths(poolAddress, depths, config);
        uint256[4] memory offchainCalculations = [uint256(55024886201110690267136), 
                                                  uint256(109844327765827609690112), 
                                                  uint256(120101406051197037576192), 
                                                  uint256(139906473874238226825216)];
        
        bool truth = true;
        for (uint256 i=0; i<offchainCalculations.length; i++){
            // test if our floating point calculations is within lower bound of floating point arithmetic
            truth = truth && (evalulatePct(depthsMultiple[i], offchainCalculations[i]) < toleranceTrue);
        }

        assertEq(truth, true);
    }

    function testDepthsToken1() public {
        // testing against theoretical depth calculations from off-chain
        // liquidityLow = 4050408317414413260938526 or liquidity from ticks [-500, 0] U [50, 500] 
        // liquidityHigh = 44102429116372312781543825 or liquidity from ticks [0, 50]
        //
        // .025% depth = 5053536986492639903744
        // 5053536986492639903744 = (sqrt(1) - sqrt(1 / (1 + .0025))) * liquidityLow
        //
        // .05% depth = 10088205745527348789248
        // 10088205745527348789248 = (sqrt(1) - sqrt(1 / (1 + .005))) * liquidityLow
        //
        // 1% depth = 20101406051205610733568
        // 20101406051205610733568 = (sqrt(1) - sqrt(1 / (1 + .01))) * liquidityLow

        // 2% depth = 39906473874246514769920
        // 39906473874246514769920 = (sqrt(1) - sqrt(1 / (1 + .02))) * liquidityLow
        // .025%, .05%, 1%, 2%
        uint256[] memory depths = new uint256[](4);
        uint256[4] memory depthsValues = [uint256(79327135897655778240513441792),
                                        uint256(79425985949584623951891398656),
                                        uint256(79623317895830908422001262592),
                                        uint256(80016521857016597127997947904)];
                                        
        for (uint256 i=0; i<4; i++){
            depths[i] = depthsValues[i];
        }

        IDepth.DepthConfig[] memory config = new  IDepth.DepthConfig[](4);
        for (uint256 i=0; i<4; i++){
            config[i] = IDepth.DepthConfig({
                                            bothSides: false,
                                            token0: false,
                                            exact: false
                                        });
        }


        uint256[] memory depthsMultiple = depth.calculateDepths(poolAddress, depths, config);
        uint256[4] memory offchainCalculations = [uint256(5053536986492639903744), 
                                                  uint256(10088205745527348789248), 
                                                  uint256(20101406051205610733568), 
                                                  uint256(39906473874246514769920)];
        
        bool truth = true;
        for (uint256 i=0; i<offchainCalculations.length; i++){
            // test if our floating point calculations is within lower bound of floating point arithmetic
            truth = truth && (evalulatePct(depthsMultiple[i], offchainCalculations[i]) < toleranceTrue);
        }

        assertEq(truth, true);
    }

    function testExactDepthsToken1() public {
        // testing against theoretical depth calculations from off-chain
        // liquidityLow = 4050408317414413260938526 or liquidity from ticks [-500, 0] U [50, 500] 
        // liquidityHigh = 44102429116372312781543825 or liquidity from ticks [0, 50]
        //
        // .025% depth = 5066178739934128504832
        // 5066178739934128504832 = (sqrt(1) - sqrt(1 - .0025)) * liquidityLow
        //
        // .05% depth = 10138710062577439735808
        // 10138710062577439735808 = (sqrt(1) - sqrt(1 - .005)) * liquidityLow
        //
        // 1% depth = 20302926434909349216256
        // 20302926434909349216256 = (sqrt(1) - sqrt(1 - .01)) * liquidityLow

        // 2% depth = 40708654469037168787456
        // 40708654469037168787456 = (sqrt(1) - sqrt(1 - .02)) * liquidityLow
        // .025%, .05%, 1%, 2%
        uint256[] memory depths = new uint256[](4);
        uint256[4] memory depthsValues = [uint256(79327135897655778240513441792),
                                        uint256(79425985949584623951891398656),
                                        uint256(79623317895830908422001262592),
                                        uint256(80016521857016597127997947904)];
                                        
        for (uint256 i=0; i<4; i++){
            depths[i] = depthsValues[i];
        }

        IDepth.DepthConfig[] memory config = new  IDepth.DepthConfig[](4);
        for (uint256 i=0; i<4; i++){
            config[i] = IDepth.DepthConfig({
                                            bothSides: false,
                                            token0: false,
                                            exact: true
                                        });
        }


        uint256[] memory depthsMultiple = depth.calculateDepths(poolAddress, depths, config);
        uint256[4] memory offchainCalculations = [uint256(5066178739934128504832), 
                                                  uint256(10138710062577439735808), 
                                                  uint256(20302926434909349216256), 
                                                  uint256(40708654469037168787456)];
        
        bool truth = true;
        for (uint256 i=0; i<offchainCalculations.length; i++){
            // test if our floating point calculations is within lower bound of floating point arithmetic + error for series approximation
            truth = truth && (evalulatePct(depthsMultiple[i], offchainCalculations[i]) < toleranceApprox);
        }

        assertEq(truth, true);
    }
    
    function testExactDepthsToken0() public {
        // exact has no impact on price movement upward calculations
        // .025%, .05%, 1%, 2%
        uint256[] memory depths = new uint256[](4);
        uint256[4] memory depthsValues = [uint256(79327135897655778240513441792),
                                        uint256(79425985949584623951891398656),
                                        uint256(79623317895830908422001262592),
                                        uint256(80016521857016597127997947904)];
                                        
        for (uint256 i=0; i<4; i++){
            depths[i] = depthsValues[i];
        }

        IDepth.DepthConfig[] memory configExact = new  IDepth.DepthConfig[](4);
        for (uint256 i=0; i<4; i++){
            configExact[i] = IDepth.DepthConfig({
                                            bothSides: false,
                                            token0: true,
                                            exact: true
                                        });
        }


        IDepth.DepthConfig[] memory config = new  IDepth.DepthConfig[](4);
        for (uint256 i=0; i<4; i++){
            config[i] = IDepth.DepthConfig({
                                            bothSides: false,
                                            token0: true,
                                            exact: false
                                        });
        }



        uint256[] memory depthsExactMultiple = depth.calculateDepths(poolAddress, depths, configExact);
        uint256[] memory depthsMultiple = depth.calculateDepths(poolAddress, depths, config);

        assertEq(depthsExactMultiple, depthsMultiple);
    }

    function testDepthsToken1Both() public {
        // testing against theoretical depth calculations from off-chain
        // liquidityLow = 4050408317414413260938526 or liquidity from ticks [-500, 0] U [50, 500] 
        // liquidityHigh = 44102429116372312781543825 or liquidity from ticks [0, 50]
        //
        // 2% depth = 180460337100921740722176
        // 180460337100921740722176 = ((sqrt(1.0001 ** 0) - sqrt(1 / (1 + .02))) * liquidityLow) + ((sqrt(1.0001 ** 50) - sqrt(1.0001 ** 0)) * liquidityHigh) + ((sqrt(1 + .02) - sqrt(1.0001 ** 50)) * liquidityLow)
        uint256[] memory depths = new uint256[](1);
        uint256[1] memory depthsValues = [uint256(80016521857016597127997947904)];
                                        
        for (uint256 i=0; i<depthsValues.length; i++){
            depths[i] = depthsValues[i];
        }

        IDepth.DepthConfig[] memory config = new IDepth.DepthConfig[](1);
        for (uint256 i=0; i<config.length; i++){
            config[i] = IDepth.DepthConfig({
                                            bothSides: true,
                                            token0: false,
                                            exact: false
                                        });
        }


        uint256[] memory depthsMultiple = depth.calculateDepths(poolAddress, depths, config);
        uint256[1] memory offchainCalculations = [uint256(180460337100921740722176)];
        
        bool truth;
        for (uint256 i=0; i<offchainCalculations.length; i++){
            // test if our floating point calculations is within lower bound of floating point arithmetic
            truth = (evalulatePct(depthsMultiple[i], offchainCalculations[i]) < toleranceTrue);
        }

        assertEq(truth, true);
    }

    function testExactDepthsToken1Both() public {
        // testing against theoretical depth calculations from off-chain
        // liquidityLow = 4050408317414413260938526 or liquidity from ticks [-500, 0] U [50, 500] 
        // liquidityHigh = 44102429116372312781543825 or liquidity from ticks [0, 50]
        //
        // 2% depth = 181262517695712386351104
        // 181262517695712386351104 = ((sqrt(1.0001 ** 0) - sqrt(1 - .02)) * liquidityLow) + ((sqrt(1.0001 ** 50) - sqrt(1.0001 ** 0)) * liquidityHigh) + ((sqrt(1 + .02) - sqrt(1.0001 ** 50)) * liquidityLow)
        uint256[] memory depths = new uint256[](1);
        uint256[1] memory depthsValues = [uint256(80016521857016597127997947904)];
                                        
        for (uint256 i=0; i<depthsValues.length; i++){
            depths[i] = depthsValues[i];
        }

        IDepth.DepthConfig[] memory config = new IDepth.DepthConfig[](1);
        for (uint256 i=0; i<config.length; i++){
            config[i] = IDepth.DepthConfig({
                                            bothSides: true,
                                            token0: false,
                                            exact: true
                                        });
        }


        uint256[] memory depthsMultiple = depth.calculateDepths(poolAddress, depths, config);
        uint256[1] memory offchainCalculations = [uint256(181262517695712386351104)];
        
        bool truth;
        for (uint256 i=0; i<offchainCalculations.length; i++){
            // test if our floating point calculations is within lower bound of floating point arithmetic + error for series approximation
            truth = (evalulatePct(depthsMultiple[i], offchainCalculations[i]) < toleranceApprox);
        }

        assertEq(truth, true);
    }

    function testDepthsToken0Both() public {
        // testing against theoretical depth calculations from off-chain
        // liquidityLow = 4050408317414413260938526 or liquidity from ticks [-500, 0] U [50, 500] 
        // liquidityHigh = 44102429116372312781543825 or liquidity from ticks [0, 50]
        //
        // 2% depth = 180460337100921740722176
        // 180460337100921740722176 = ((sqrt(1.0001 ** 0) - sqrt(1 / (1 + .02))) * liquidityLow) + ((sqrt(1.0001 ** 50) - sqrt(1.0001 ** 0)) * liquidityHigh) + ((sqrt(1 + .02) - sqrt(1.0001 ** 50)) * liquidityLow)
        uint256[] memory depths = new uint256[](1);
        uint256[1] memory depthsValues = [uint256(80016521857016597127997947904)];
                                        
        for (uint256 i=0; i<depthsValues.length; i++){
            depths[i] = depthsValues[i];
        }

        IDepth.DepthConfig[] memory config = new IDepth.DepthConfig[](1);
        for (uint256 i=0; i<config.length; i++){
            config[i] = IDepth.DepthConfig({
                                            bothSides: true,
                                            token0: true,
                                            exact: false
                                        });
        }


        uint256[] memory depthsMultiple = depth.calculateDepths(poolAddress, depths, config);
        uint256[1] memory offchainCalculations = [uint256(180210036870795216551936)];
        
        bool truth;
        for (uint256 i=0; i<offchainCalculations.length; i++){
            // test if our floating point calculations is within lower bound of floating point arithmetic
            truth = (evalulatePct(depthsMultiple[i], offchainCalculations[i]) < toleranceTrue);
        }

        assertEq(truth, true);
    }

    function testExactDepthsToken0Both() public {
        // testing against theoretical depth calculations from off-chain
        // liquidityLow = 4050408317414413260938526 or liquidity from ticks [-500, 0] U [50, 500] 
        // liquidityHigh = 44102429116372312781543825 or liquidity from ticks [0, 50]
        //
        // 2% depth = 180460337100921740722176
        // 180460337100921740722176 = ((sqrt(1.0001 ** 0) - sqrt(1 / (1 + .02))) * liquidityLow) + ((sqrt(1.0001 ** 50) - sqrt(1.0001 ** 0)) * liquidityHigh) + ((sqrt(1 + .02) - sqrt(1.0001 ** 50)) * liquidityLow)
        uint256[] memory depths = new uint256[](1);
        uint256[1] memory depthsValues = [uint256(80016521857016597127997947904)];
                                        
        for (uint256 i=0; i<depthsValues.length; i++){
            depths[i] = depthsValues[i];
        }

        IDepth.DepthConfig[] memory config = new IDepth.DepthConfig[](1);
        for (uint256 i=0; i<config.length; i++){
            config[i] = IDepth.DepthConfig({
                                            bothSides: true,
                                            token0: true,
                                            exact: true
                                        });
        }


        uint256[] memory depthsMultiple = depth.calculateDepths(poolAddress, depths, config);
        uint256[1] memory offchainCalculations = [uint256(181028424771432853012480)];
        
        bool truth;
        for (uint256 i=0; i<offchainCalculations.length; i++){
            // test if our floating point calculations is within lower bound of floating point arithmetic + error for series approximation
            truth = (evalulatePct(depthsMultiple[i], offchainCalculations[i]) < toleranceApprox);
        }

        assertEq(truth, true);
    }

    function testLengthMismatchReversion() public {
         uint256[] memory depths = new uint256[](1);
        uint256[1] memory depthsValues = [uint256(80016521857016597127997947904)];
                                        
        for (uint256 i=0; i<depthsValues.length; i++){
            depths[i] = depthsValues[i];
        }

        IDepth.DepthConfig[] memory config = new IDepth.DepthConfig[](2);
        for (uint256 i=0; i<config.length; i++){
            config[i] = IDepth.DepthConfig({
                                            bothSides: false,
                                            token0: false,
                                            exact: false
                                        });
        }

        vm.expectRevert("LengthMismatch");
        uint256[] memory depthsMultiple = depth.calculateDepths(poolAddress, depths, config);
    }

    function testExceededMaxDepthReversion() public {
         uint256[] memory depths = new uint256[](1);
        uint256[1] memory depthsValues = [uint256(112045541949572287496682733568)];
                                        
        for (uint256 i=0; i<depthsValues.length; i++){
            depths[i] = depthsValues[i];
        }

        IDepth.DepthConfig[] memory config = new IDepth.DepthConfig[](1);
        for (uint256 i=0; i<config.length; i++){
            config[i] = IDepth.DepthConfig({
                                            bothSides: true,
                                            token0: true,
                                            exact: true
                                        });
        }

        vm.expectRevert("ExceededMaxDepth");
        uint256[] memory depthsMultiple = depth.calculateDepths(poolAddress, depths, config);
    }

}
