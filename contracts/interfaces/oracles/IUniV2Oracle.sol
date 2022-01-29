// SPDX-License-Identifier: BSL-1.1
pragma solidity 0.8.9;

import "../external/univ2/IUniswapV2Factory.sol";
import "./IOracle.sol";

interface IUniV2Oracle is IOracle {
    /// @notice Reference to UniV2 factory
    function factory() external returns (IUniswapV2Factory);
}
