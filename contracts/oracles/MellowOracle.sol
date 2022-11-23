// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.9;

import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "../interfaces/oracles/IChainlinkOracle.sol";
import "../interfaces/oracles/IUniV3Oracle.sol";
import "../interfaces/oracles/IUniV2Oracle.sol";
import "../interfaces/oracles/IMellowOracle.sol";
import "../utils/ContractMeta.sol";

contract MellowOracle is ContractMeta, IMellowOracle, ERC165 {
    /// @inheritdoc IMellowOracle
    IUniV2Oracle public immutable univ2Oracle;
    /// @inheritdoc IMellowOracle
    IUniV3Oracle public immutable univ3Oracle;
    /// @inheritdoc IMellowOracle
    IChainlinkOracle public immutable chainlinkOracle;

    constructor(
        IUniV2Oracle univ2Oracle_,
        IUniV3Oracle univ3Oracle_,
        IChainlinkOracle chainlinkOracle_
    ) {
        univ2Oracle = univ2Oracle_;
        univ3Oracle = univ3Oracle_;
        chainlinkOracle = chainlinkOracle_;
    }

    // -------------------------  EXTERNAL, VIEW  ------------------------------

    function priceX96(
        address token0,
        address token1,
        uint256 safetyIndicesSet
    ) external view returns (uint256[] memory pricesX96, uint256[] memory safetyIndices) {
        IOracle[] memory oracles = _oracles();
        pricesX96 = new uint256[](6);
        safetyIndices = new uint256[](6);
        uint256 len;
        for (uint256 i = 0; i < oracles.length; i++) {
            IOracle oracle = oracles[i];
            (uint256[] memory oPrices, uint256[] memory oSafetyIndixes) = oracle.priceX96(
                token0,
                token1,
                safetyIndicesSet
            );
            for (uint256 j = 0; j < oPrices.length; j++) {
                pricesX96[len] = oPrices[j];
                safetyIndices[len] = oSafetyIndixes[j];
                len += 1;
            }
        }
        assembly {
            mstore(pricesX96, len)
            mstore(safetyIndices, len)
        }
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return super.supportsInterface(interfaceId) || type(IOracle).interfaceId == interfaceId;
    }

    // -------------------------  INTERNAL, VIEW  ------------------------------

    function _contractName() internal pure override returns (bytes32) {
        return bytes32("MellowOracle");
    }

    function _contractVersion() internal pure override returns (bytes32) {
        return bytes32("1.0.0");
    }

    function _oracles() internal view returns (IOracle[] memory oracles) {
        oracles = new IOracle[](3);
        uint256 len;
        if (address(univ2Oracle) != address(0)) {
            oracles[len] = univ2Oracle;
            len += 1;
        }
        if (address(univ3Oracle) != address(0)) {
            oracles[len] = univ3Oracle;
            len += 1;
        }
        if (address(chainlinkOracle) != address(0)) {
            oracles[len] = chainlinkOracle;
            len += 1;
        }
        assembly {
            mstore(oracles, len)
        }
    }
}
