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

contract CounterTest is Test {
    TestToken public token0;
    TestToken public token1;
    uint256 mainnetFork;
    string MAINNET_RPC_URL;
    IUniswapV3Factory v3Factory;
    IUniswapV3Pool pool;
    INonfungiblePositionManager nftPosManager;
    IQuoterV2 quoter;
    IQuoterV2.QuoteExactInputSingleParams swapParams;

    address nftPosManagerAddress = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;
    address quoterAddress = 0x61fFE014bA17989E743c5F6cB21bF9697530B21e;
    address me = vm.addr(0x1);
    INonfungiblePositionManager.MintParams mintParams;


    function setUp() public {
        MAINNET_RPC_URL = "https://eth-mainnet.g.alchemy.com/v2/5IScbzuGm18sygT5eoFpKiRWFu9NOWFS";
        mainnetFork = vm.createFork(MAINNET_RPC_URL);
        vm.selectFork(mainnetFork);

        vm.startPrank(me);

        token0 = new TestToken("Test Token1", 'T1');
        token1 = new TestToken("Test Token2", 'T2');
        console.log(address(token0));
        console.log(address(token1));

        v3Factory = IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);
        address poolAddress = v3Factory.createPool(address(token0), address(token1), 500);
        nftPosManager = INonfungiblePositionManager(nftPosManagerAddress);
        quoter = IQuoterV2(quoterAddress);

        console.log(poolAddress);

        pool = IUniswapV3Pool(poolAddress);
        pool.initialize(1 << 96);

        console.log(pool.liquidity());
        console.log(pool.token0());
        console.log(pool.token1());
        console.log(token0.balanceOf(me));
        console.log(token1.balanceOf(me));

        token0.approve(nftPosManagerAddress, 1e18);
        token1.approve(nftPosManagerAddress, 1e18);
        token0.approve(quoterAddress, 1e18);
        token1.approve(quoterAddress, 1e18);

        mintParams = INonfungiblePositionManager.MintParams({
            token0: pool.token0(),
            token1: pool.token1(),
            fee: pool.fee(),
            tickLower: -500,
            tickUpper: 500,
            amount0Desired: 24688868914785168,
            amount1Desired: 24688868914785168,
            amount0Min: 0,
            amount1Min: 0,
            recipient: me,
            deadline: block.timestamp + 100
        });

        // liquidity = 1000000000000000034
        (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1) = nftPosManager.mint(mintParams);
        console.log(tokenId);
        console.log(liquidity);
        console.log(amount0);
        console.log(amount1);

        swapParams = IQuoterV2.QuoteExactInputSingleParams({
                        tokenIn: pool.token0(),
                        tokenOut: pool.token1(),
                        amountIn: 10050506338833420,
                        fee:  pool.fee(),
                        sqrtPriceLimitX96: 0
                    });

        (uint256 amountOut, uint160 sqrtPriceX96After,,) = quoter.quoteExactInputSingle(swapParams);
        console.log(amountOut);
        console.log(sqrtPriceX96After);
    }

    function testIncrement() public {
        assertEq(true, true);
    }

    // function testSetNumber(uint256 x) public {
    //     counter.setNumber(x);
    //     assertEq(counter.number(), x);
    // }
}
