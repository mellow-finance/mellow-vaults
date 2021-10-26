// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./IVaultGovernance.sol";

interface IGatewayVaultGovernance is IVaultGovernance {
    function limits() external view returns (uint256[] memory);

    function redirects() external view returns (address[] memory);
}
