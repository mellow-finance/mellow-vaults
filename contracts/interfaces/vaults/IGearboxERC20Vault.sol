// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./IIntegrationVault.sol";
import "../utils/IGearboxERC20Helper.sol";

interface IGearboxERC20Vault is IIntegrationVault {
    /// @notice Initialized a new contract.
    /// @dev Can only be initialized by vault governance
    /// @param nft_ NFT of the vault in the VaultRegistry
    /// @param vaultTokens_ ERC20 tokens that will be managed by this Vault
    function initialize(uint256 nft_, address[] memory vaultTokens_) external;

    function adjustAllPositions() external;

    function helper() external view returns (IGearboxERC20Helper);

    function addSubvault(address addr, uint256 limit) external;

    function changeLimit(uint256 index, uint256 limit) external;

    function changeLimitAndFactor(uint256 index, uint256 limit, uint256 factor) external;

    function distributeDeposits() external;

    function withdraw(uint256 tvlBefore, uint256 shareD) external returns (uint256 withdrawn);

    function setAdapters(address curveAdapter_, address convexAdapter_) external;

    function totalLimit() external returns (uint256);

    function subvaultsStatusMask() external returns (uint256);

    function totalDeposited() external view returns (uint256);

    function curveAdapter() external returns (address);

    function convexAdapter() external view returns (address);

    function calculatePoolsFeeD() external view returns (uint256);

    function totalConvexLpTokens() external view returns (uint256);

    function cumulativeSumRAY() external view returns (uint256);

    function totalBorrowedAmount() external view returns (uint256);

    function totalEarnedCRV() external view returns (uint256);

    function cumulativeSumCRV() external view returns (uint256);

    function cumulativeSubCRV() external view returns (uint256);

    function totalEarnedLDO() external view returns (uint256);

    function cumulativeSumLDO() external view returns (uint256);

    function cumulativeSubLDO() external view returns (uint256);

    function subvaultsList(uint256) external view returns (address);

    function limitsList(uint256) external view returns (uint256);

    function vaultsCount() external view returns (uint256);

}
