// SPDX-License-Identifier: BSL-1.1
pragma solidity 0.8.9;

import "../interfaces/utils/IContractMeta.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "../interfaces/external/univ2/IUniswapV2Pair.sol";
import "../interfaces/external/univ2/IUniswapV2Factory.sol";
import "../interfaces/oracles/IUniV2Oracle.sol";
import "../libraries/ExceptionsLibrary.sol";
import "../libraries/CommonLibrary.sol";

contract UniV2Oracle is IContractMeta, IUniV2Oracle, ERC165 {
    bytes32 public constant CONTRACT_NAME = "UniV2Oracle";
    bytes32 public constant CONTRACT_VERSION = "1.0.0";

    IUniswapV2Factory public immutable factory;

    constructor(IUniswapV2Factory factory_) {
        factory = factory_;
    }

    // -------------------------  EXTERNAL, VIEW  ------------------------------

    /// @inheritdoc IOracle
    function price(
        address token0,
        address token1,
        uint256 safetyIndicesSet
    ) external view returns (uint256[] memory pricesX96, uint256[] memory safetyIndices) {
        if (safetyIndicesSet & 0x1 != 1) {
            return (pricesX96, safetyIndices);
        }
        IUniswapV2Pair pool = IUniswapV2Pair(factory.getPair(token0, token1));
        if (address(pool) == address(0)) {
            return (pricesX96, safetyIndices);
        }
        (uint112 reserve0, uint112 reserve1, ) = pool.getReserves();
        pricesX96 = new uint256[](1);
        safetyIndices = new uint256[](1);
        if (token0 < token1) {
            pricesX96[0] = FullMath.mulDiv(reserve1, CommonLibrary.Q96, reserve0);
        } else {
            pricesX96[0] = FullMath.mulDiv(reserve0, CommonLibrary.Q96, reserve1);
        }
        safetyIndices[0] = 1;
    }

    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return super.supportsInterface(interfaceId) || type(IUniV2Oracle).interfaceId == interfaceId;
    }
}
