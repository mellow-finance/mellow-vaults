// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "../src/interfaces/oracles/IOracle.sol";

contract MockOracle is IOracle {
    uint256 public currentPriceX96 = 1 << 96;
    uint256 public safetyIndex = 32;

    mapping (address => mapping (address => uint256)) p;

    function updatePrice(address token0, address token1, uint256 newPrice) public {
        p[token0][token1] = newPrice;
        p[token1][token0] = currentPriceX96 * currentPriceX96 / newPrice;
    }

    function priceX96(
        address token0,
        address token1,
        uint256
    ) external view returns (uint256[] memory pricesX96, uint256[] memory safetyIndices) {
        pricesX96 = new uint256[](2);
        safetyIndices = new uint256[](2);
        for (uint256 i = 0; i < 2; ++i) {
            pricesX96[i] = p[token0][token1];
            safetyIndices[i] = safetyIndex;
        }
    }
}
