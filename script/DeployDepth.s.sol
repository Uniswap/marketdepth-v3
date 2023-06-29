// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.6;

import "forge-std/console2.sol";
import "forge-std/Script.sol";
import {Depth} from "src/Depth.sol";

contract DeployDepth is Script {
    function setUp() public {}

    function run() public returns (Depth depth) {
        vm.startBroadcast();

        depth = new Depth();
        console2.log("MarketDepth Deployed:", address(depth));

        vm.stopBroadcast();
    }
}
