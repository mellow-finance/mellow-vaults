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
        0x94b008aA00579c1307B0EF2c499aD98a8ce58e58,
        0x7F5c764cBc14f9669B88837ca1490cCa17c31607,
        0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85,
        0x350a791Bfc2C21F9Ed5d10980Dad2e2638ffa7f6,
        0x68f180fcCe6836688e9084f035309E29Bf0A2095,
        0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1,
        0x4200000000000000000000000000000000000042,
        0x4200000000000000000000000000000000000006
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
