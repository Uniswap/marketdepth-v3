// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.6;
pragma abicoder v2;

import "forge-std/Test.sol";
import "../src/TestToken.sol";
import "forge-std/console.sol";
import 'v3-core/contracts/interfaces/IUniswapV3Factory.sol';
import 'v3-core/contracts/interfaces/IUniswapV3Pool.sol';
import 'v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol';
import 'v3-periphery/contracts/interfaces/IQuoterV2.sol';
import "../src/Depth.sol";

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
    uint256 toleranceExact = 1e10;
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

        // liquidity = 4050408317414413260938526
        nftPosManager.mint(mintParams);
    }      

    function setUp() public {
        mainnetFork = vm.createFork(vm.envString("MAINNET_RPC_URL"));
        vm.selectFork(mainnetFork);
        vm.startPrank(me);

        depth = new Depth();

        createV3();
    }

    function testBaseLower() public {
        uint256 depth_return = depth.calculateDepth(poolAddress, 80016521857016597127997947904, false, false, false);
        console.log(depth_return);
        
        // liquidity * (1 - sqrt(1 / (1 + .02))) = 39906473874246514769920
        offchainCalculation = 39906473874246514769920;
        pctDiff = evalulatePct(offchainCalculation, depth_return);

        assertEq(pctDiff < toleranceExact, true);
    }

    function testExactLower() public {
        uint256 depth_return = depth.calculateDepth(poolAddress, 80016521857016597127997947904, false, false, true);
        console.log(depth_return);
        
        // liquidity * (1 - sqrt(1.02)) = 40708654469037168787456
        offchainCalculation = 40708654469037168787456;
        pctDiff = evalulatePct(offchainCalculation, depth_return);

        assertEq(pctDiff < toleranceApprox, true);
    }
    
    // function calculateDepth(address poolAddress, uint256 sqrtDepthX96, bool token0, bool both, bool exact) public returns (uint256) {
    function testBaseUpper() public {
        uint256 depth_return = depth.calculateDepth(poolAddress, 80016521857016597127997947904, true, false, false);
        console.log(depth_return);
        
        // liquidity * (1 - sqrt(1.02)) = 39906473874246565101568
        offchainCalculation = 39906473874246565101568;
        pctDiff = evalulatePct(offchainCalculation, depth_return);

        assertEq(pctDiff < toleranceExact, true);
    }

    // function calculateDepth(address poolAddress, uint256 sqrtDepthX96, bool token0, bool both, bool exact) public returns (uint256) {
    function testExactUpper() public {
        uint256 depthReturnBase = depth.calculateDepth(poolAddress, 80016521857016597127997947904, true, false, false);
        uint256 depthReturnExact = depth.calculateDepth(poolAddress, 80016521857016597127997947904, true, false, true);
        
        assertEq(depthReturnBase, depthReturnExact);
    }

    function testBothToken1() public {
        uint256 depthReturnBase = depth.calculateDepth(poolAddress, 80016521857016597127997947904, false, true, false);

        // liquidity * (sqrt(1.02) - sqrt(1 / 1.02)) = 80210036870803563216896
        offchainCalculation = 80210036870803563216896;
        pctDiff = evalulatePct(offchainCalculation, depthReturnBase);

        assertEq(pctDiff < toleranceApprox, true);
    }

    function testBothToken0() public {
        uint256 depthReturnBase = depth.calculateDepth(poolAddress, 80016521857016597127997947904, true, true, false);

        // liquidity * (sqrt(1.02) - sqrt(1 /1.02)) / (sqrt(1.02) * sqrt(1/1.02)) = 80210036870803563216896
        offchainCalculation = 80210036870803563216896;
        pctDiff = evalulatePct(offchainCalculation, depthReturnBase);

        assertEq(pctDiff < toleranceApprox, true);
    }

    function testBothToken0vsToken1() public {
        uint256 depthReturnBaseToken0 =  depth.calculateDepth(poolAddress, 80016521857016597127997947904, false, true, false);
        uint256 depthReturnBaseToken1 = depth.calculateDepth(poolAddress, 80016521857016597127997947904, false, true, false);

        assertEq(depthReturnBaseToken0, depthReturnBaseToken1);
    }

    function testMultipleToken1() public {
        // .025%, .05%, 1%, 2%
        uint256[] memory depths = new uint256[](4);
        uint256[4] memory depthsValues = [uint256(79327135897655778240513441792),
                                        uint256(79425985949584623951891398656),
                                        uint256(79623317895830908422001262592),
                                        uint256(80016521857016597127997947904)];
                                        
        for (uint256 i=0; i<4; i++){
            depths[i] = depthsValues[i];
        }

        bool[] memory token0 = new bool[](4);
        for (uint256 i=0; i<4; i++){
            token0[i] = false;
        }

        bool[] memory both = new bool[](4);
        for (uint256 i=0; i<4; i++){
            both[i] = false;
        }

        uint256[] memory depthsMultiple = depth.calculateMultipleDepth(poolAddress, depths, token0, both, false);

        uint256[] memory depthsSingles = new uint256[](4);
        for (uint i=0; i<4; i++){
            depthsSingles[i] = depth.calculateDepth(poolAddress, depths[i], false, false, false);
        }

        assertEq(depthsSingles, depthsMultiple);
    }
}
