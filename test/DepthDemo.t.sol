// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.6;
pragma abicoder v2;

import {Depth} from "src/Depth.sol";
import {IDepth} from "src/IDepth.sol";

import "forge-std/Test.sol";

contract DepthDemo is Test {
    Depth depth;
    address pool;
    uint256[] sqrtDepthX96;

    string[] config;

    string outputPath = "data/output.json";
    uint256 mainnetFork;

    function setUp() public {
        mainnetFork = vm.createFork(vm.envString("MAINNET_RPC_URL"));
        vm.selectFork(mainnetFork);

        depth = new Depth();

        string memory json = vm.readLine("data/input.json");
        pool = abi.decode(vm.parseJson(json, ".pool"), (address));
        sqrtDepthX96 = abi.decode(vm.parseJson(json, ".sqrtDepth"), (uint256[]));

        config = abi.decode(vm.parseJson(json, ".configs"), (string[]));
    }

    function testRunDepth() public {
        IDepth.DepthConfig[] memory configs = new IDepth.DepthConfig[](config.length);

        for (uint256 i = 0; i < config.length; i++) {
            string memory c = config[i];
            IDepth.DepthConfig memory depthConfig = IDepth.DepthConfig({
                side: abi.decode(vm.parseJson(c, ".side"), (IDepth.Side)),
                amountInToken0: abi.decode(vm.parseJson(c, ".amountInToken0"), (bool)),
                exact: abi.decode(vm.parseJson(c, ".exact"), (bool))
            });
            configs[i] = depthConfig;
        }

        uint256[] memory amounts = depth.calculateDepths(pool, sqrtDepthX96, configs);
        string memory amountSerialized = vm.serializeUint("uint256", "amounts", amounts);
        vm.writeJson(amountSerialized, outputPath);
    }
}
