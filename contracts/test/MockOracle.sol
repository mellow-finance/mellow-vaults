// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.9;

import "../interfaces/oracles/IOracle.sol";

contract MockOracle is IOracle {
    uint256 public currentPriceX96 = 1 << 96;
    uint256 public safetyIndex = 1;

    function updatePrice(uint256 newPrice) public {
        currentPriceX96 = newPrice;
    }

    function updateSafetyIndex(uint256 newSafetyIndex) public {
        safetyIndex = newSafetyIndex;
    }

    function priceX96(
        address,
        address,
        uint256
    ) external view returns (uint256[] memory pricesX96, uint256[] memory safetyIndices) {
        pricesX96 = new uint256[](2);
        safetyIndices = new uint256[](2);
        for (uint256 i = 0; i < 2; ++i) {
            pricesX96[i] = currentPriceX96;
            safetyIndices[i] = safetyIndex;
        }
    }
}
