// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "./IOracle.sol";

interface IMellowOracle is IOracle {
    /// @notice Reference to UniV2 oracle
    function univ2Oracle() external view returns (IOracle);

    /// @notice Reference to UniV3 oracle
    function univ3Oracle() external view returns (IOracle);

    /// @notice Reference to Chainlink oracle
    function chainlinkOracle() external view returns (IOracle);
}
