// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.9;

import "./IOracle.sol";
import "./IUniV2Oracle.sol";
import "./IUniV3Oracle.sol";
import "./IChainlinkOracle.sol";

interface IMellowOracle is IOracle {
    /// @notice Reference to UniV2 oracle
    function univ2Oracle() external view returns (IUniV2Oracle);

    /// @notice Reference to UniV3 oracle
    function univ3Oracle() external view returns (IUniV3Oracle);

    /// @notice Reference to Chainlink oracle
    function chainlinkOracle() external view returns (IChainlinkOracle);
}
