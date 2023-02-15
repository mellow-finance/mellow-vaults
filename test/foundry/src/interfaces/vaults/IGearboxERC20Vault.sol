// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./IIntegrationVault.sol";

interface IGearboxERC20Vault is IIntegrationVault {
    /// @notice Initialized a new contract.
    /// @dev Can only be initialized by vault governance
    /// @param nft_ NFT of the vault in the VaultRegistry
    /// @param vaultTokens_ ERC20 tokens that will be managed by this Vault
    function initialize(uint256 nft_, address[] memory vaultTokens_) external;

    function adjustAllPositions() external;

    function addSubvault(address addr, uint256 limit) external;

    function changeLimit(uint256 index, uint256 limit) external;

    function changeLimitAndFactor(uint256 index, uint256 limit, uint256 factor) external;

    function distributeDeposits() external;

    function withdraw(uint256 tvlBefore, uint256 shareD) external returns (uint256 withdrawn);

    function setAdapters(address curveAdapter_, address convexAdapter_) external;

    function totalLimit() external returns (uint256);

    function subvaultsStatusMask() external returns (uint256);

    function totalDeposited() external returns (uint256);

    function curveAdapter() external returns (address);

    function convexAdapter() external returns (address);

    function calculatePoolsFeeD() external view returns (uint256);

}
