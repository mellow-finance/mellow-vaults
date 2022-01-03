// SPDX-License-Identifier: BSL-1.1
pragma solidity 0.8.9;

import "../interfaces/external/univ2/IUniswapV2Pair.sol";
import "../interfaces/external/univ2/IUniswapV2Factory.sol";
import "../interfaces/oracles/IUniV2Oracle.sol";
import "../libraries/ExceptionsLibrary.sol";
import "../libraries/CommonLibrary.sol";

contract UniV2Oracle is IUniV2Oracle {
    IUniswapV2Factory public immutable factory;

    constructor(IUniswapV2Factory factory_) {
        factory = factory_;
    }

    /// @inheritdoc IUniV2Oracle
    function spotPrice(address token0, address token1) external view returns (uint256 spotPriceX96) {
        require(token1 > token0, ExceptionsLibrary.INVARIANT);
        address pool = factory.getPair(token0, token1);
        require(pool != address(0), ExceptionsLibrary.NOT_FOUND);
        (uint112 reserve0, uint112 reserve1, ) = IUniswapV2Pair(pool).getReserves();
        spotPriceX96 = FullMath.mulDiv(reserve1, CommonLibrary.Q96, reserve0);
    }
}
