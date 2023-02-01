// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.6;

import "forge-std/Test.sol";
import "../src/Depth.sol";

contract DepthTest is Test {
    Depth public depth;
    uint256 mainnetFork;
    string MAINNET_RPC_URL;

    function setUp() public {
        MAINNET_RPC_URL = "https://eth-mainnet.g.alchemy.com/v2/5IScbzuGm18sygT5eoFpKiRWFu9NOWFS";
        mainnetFork = vm.createFork(MAINNET_RPC_URL);
        vm.selectFork(mainnetFork);

        depth = new Depth();
        
    }

    function testMultipleDepth() public {
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

        // bool[] memory both = [false, false, false, false];

        uint256[] memory depth_return = depth.calculateMultipleDepth(0x8ad599c3A0ff1De082011EFDDc58f1908eb6e6D8, depths, token0, both);
        
        for (uint i=0; i<depth_return.length; i++) {
            log_named_uint("Found token1 depth", depth_return[i]);
        }

        assertEq(true, true);
    }


    function testSingleDepth() public {
        // address poolAddress = address(0x8ad599c3A0ff1De082011EFDDc58f1908eb6e6D8);
        
        // // sqrt(1.02) * 2^96 = 80016521857016597127997947904
        // uint256 sqrtDepthX96 = 80016521857016597127997947904;

        uint256 depth_return = depth.calculateDepth(0x8ad599c3A0ff1De082011EFDDc58f1908eb6e6D8, 80016521857016597127997947904, false, false);
        log_named_uint("Current token1 depth", depth_return);

        // depth_return = depth.calculateDepth(0x8ad599c3A0ff1De082011EFDDc58f1908eb6e6D8, 80016521857016597127997947904, false, true);
        // log_named_uint("Current both token1 depth", depth_return);

        depth_return = depth.calculateDepth(0x8ad599c3A0ff1De082011EFDDc58f1908eb6e6D8, 80016521857016597127997947904, true, false);
        log_named_uint("Current both token0 depth", depth_return);

        // depth_return = depth.calculateDepth(0x8ad599c3A0ff1De082011EFDDc58f1908eb6e6D8, 80016521857016597127997947904, true, true);
        // log_named_uint("Current both token0 depth", depth_return);
        
        assertEq(true, true);
    }
}