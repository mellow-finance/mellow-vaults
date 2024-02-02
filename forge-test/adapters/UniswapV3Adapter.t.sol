// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/src/Test.sol";
import "forge-std/src/Vm.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

import "../../src/interfaces/external/univ3/IUniswapV3Factory.sol";
import "../../src/interfaces/external/univ3/IUniswapV3Pool.sol";

import "../../src/adapters/UniswapV3Adapter.sol";

contract Unit is Test {
    using SafeERC20 for IERC20;

    INonfungiblePositionManager public positionManager =
        INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);

    UniswapV3Adapter public adapter;

    address[8] tokens = [
        0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2,
        0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48,
        0xdAC17F958D2ee523a2206206994597C13D831ec7,
        0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599,
        0x6B175474E89094C44Da98b954EedeAC495271d0F,
        0x853d955aCEf822Db058eb8505911ED77F175b99e,
        0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984,
        0x514910771AF9Ca656af840dff83E8264EcF986CA
    ];
    uint24[4] fees = [100, 500, 3000, 10000];

    address[] pools;

    function setUp() external {
        adapter = new UniswapV3Adapter(positionManager);
        IUniswapV3Factory factory = IUniswapV3Factory(positionManager.factory());
        for (uint256 i = 0; i < tokens.length; i++) {
            for (uint256 j = i + 1; j < tokens.length; j++) {
                for (uint256 k = 0; k < 4; k++) {
                    address pool = factory.getPool(tokens[i], tokens[j], fees[k]);
                    if (pool == address(0)) continue;
                    (, , , uint16 observationCardinality, , , ) = IUniswapV3Pool(pool).slot0();
                    if (observationCardinality < 50) continue;
                    pools.push(pool);
                }
            }
        }
    }

    function test() external view {
        for (uint256 i = 0; i < pools.length; i++) {
            uint256 n = 20;
            int24[] memory deltas = adapter.getDeltas(pools[i], uint16(n));
            IUniswapV3Pool pool = IUniswapV3Pool(pools[i]);
            string memory response = string(
                abi.encodePacked(
                    IERC20Metadata(pool.token0()).symbol(),
                    "-",
                    IERC20Metadata(pool.token1()).symbol(),
                    "-",
                    vm.toString(pool.fee()),
                    ":\t"
                )
            );
            for (uint256 j = 0; j < n; j++) {
                int24 delta = deltas[j];
                response = string(abi.encodePacked(response, vm.toString(delta), (j + 1 == n ? ";" : ",\t")));
            }
            console2.log(response);
        }
    }
}
