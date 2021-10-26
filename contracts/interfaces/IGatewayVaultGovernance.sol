// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./IVaultGovernanceOld.sol";

interface IGatewayVaultGovernance is IVaultGovernanceOld {
    function limits() external view returns (uint256[] memory);

    function redirects() external view returns (address[] memory);
}
