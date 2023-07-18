// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../interfaces/external/univ3/IUniswapV3Factory.sol";
import "./MockUniswapV3Pool.sol";

contract MockUniswapV3Factory is IUniswapV3Factory {
    MockUniswapV3Pool uniV3Pool;

    constructor(MockUniswapV3Pool pool_) {
        uniV3Pool = pool_;
    }

    function owner() external view returns (address) {}

    function feeAmountTickSpacing(uint24 fee) external view returns (int24) {}

    function getPool(address, address, uint24) external view returns (address pool) {
        pool = address(uniV3Pool);
    }

    function createPool(address tokenA, address tokenB, uint24 fee) external returns (address pool) {}

    function setOwner(address _owner) external {}

    function enableFeeAmount(uint24 fee, int24 tickSpacing) external {}
}
