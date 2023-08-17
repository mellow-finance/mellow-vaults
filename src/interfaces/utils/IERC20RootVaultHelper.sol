// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../oracles/IOracle.sol";

interface IERC20RootVaultHelper {
    function getTvlToken0(
        uint256[] calldata tvls,
        address[] calldata tokens,
        IOracle oracle
    ) external view returns (uint256 tvl0);
}
