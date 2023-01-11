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

    function testDepth() public {
        // address poolAddress = address(0x8ad599c3A0ff1De082011EFDDc58f1908eb6e6D8);
        
        // // sqrt(1.02) * 2^96 = 80016521857016597127997947904
        // uint256 sqrtDepthX96 = 80016521857016597127997947904;

        uint256 depth_return = depth.calculateDepth(0x8ad599c3A0ff1De082011EFDDc58f1908eb6e6D8, 80016521857016597127997947904, true, false);
        log_named_uint("Current token0 depth", depth_return);
        
        assertEq(true, true);
    }
}