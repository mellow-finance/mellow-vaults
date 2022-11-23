// SPDX-License-Identifier: BSL-1.1
pragma solidity 0.8.9;

import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "../interfaces/external/univ2/IUniswapV2Pair.sol";
import "../interfaces/external/univ2/IUniswapV2Factory.sol";
import "../interfaces/oracles/IUniV2Oracle.sol";
import "../libraries/external/FullMath.sol";
import "../libraries/CommonLibrary.sol";
import "../utils/ContractMeta.sol";

contract UniV2Oracle is ContractMeta, IUniV2Oracle, ERC165 {
    /// @inheritdoc IUniV2Oracle
    IUniswapV2Factory public immutable factory;
    /// @inheritdoc IUniV2Oracle
    uint8 public constant safetyIndex = 1;

    constructor(IUniswapV2Factory factory_) {
        factory = factory_;
    }

    // -------------------------  EXTERNAL, VIEW  ------------------------------

    /// @inheritdoc IOracle
    function priceX96(
        address token0,
        address token1,
        uint256 safetyIndicesSet
    ) external view returns (uint256[] memory pricesX96, uint256[] memory safetyIndices) {
        bool isSwapped = false;
        if (token0 > token1) {
            (token0, token1) = (token1, token0);
            isSwapped = true;
        }
        if (((safetyIndicesSet >> safetyIndex) & 1) != 1) {
            return (pricesX96, safetyIndices);
        }
        IUniswapV2Pair pool = IUniswapV2Pair(factory.getPair(token0, token1));
        if (address(pool) == address(0)) {
            return (pricesX96, safetyIndices);
        }
        (uint112 reserve0, uint112 reserve1, ) = pool.getReserves();
        pricesX96 = new uint256[](1);
        safetyIndices = new uint256[](1);
        if (isSwapped) {
            pricesX96[0] = FullMath.mulDiv(reserve0, CommonLibrary.Q96, reserve1);
        } else {
            pricesX96[0] = FullMath.mulDiv(reserve1, CommonLibrary.Q96, reserve0);
        }
        safetyIndices[0] = safetyIndex;
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return super.supportsInterface(interfaceId) || type(IUniV2Oracle).interfaceId == interfaceId;
    }

    // -------------------  INTERNAL, VIEW  -------------------

    function _contractName() internal pure override returns (bytes32) {
        return bytes32("UniV2Oracle");
    }

    function _contractVersion() internal pure override returns (bytes32) {
        return bytes32("1.0.0");
    }
}
