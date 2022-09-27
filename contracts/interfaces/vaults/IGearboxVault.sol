// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./IIntegrationVault.sol";

interface IGearboxVault is IIntegrationVault {
    
    function initialize(uint256 nft_, address[] memory vaultTokens_) external;

    function updateTargetMarginalFactor(uint256 marginalFactorD_) external;

    function adjustPosition() external;

    function openCreditAccount() external;

}