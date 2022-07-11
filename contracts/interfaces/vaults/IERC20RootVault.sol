// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./IAggregateVault.sol";
import "../utils/IERC20RootVaultHelper.sol";

interface IERC20RootVault is IAggregateVault, IERC20 {
    /// @notice Initialized a new contract.
    /// @dev Can only be initialized by vault governance
    /// @param nft_ NFT of the vault in the VaultRegistry
    /// @param vaultTokens_ ERC20 tokens that will be managed by this Vault
    /// @param strategy_ The address that will have approvals for subvaultNfts
    /// @param subvaultNfts_ The NFTs of the subvaults that will be aggregated by this ERC20RootVault
    function initialize(
        uint256 nft_,
        address[] memory vaultTokens_,
        address strategy_,
        uint256[] memory subvaultNfts_,
        IERC20RootVaultHelper helper_
    ) external;

    /// @notice The timestamp of last charging of fees
    function lastFeeCharge() external view returns (uint64);

    /// @notice The timestamp of last updating totalWithdrawnAmounts array
    function totalWithdrawnAmountsTimestamp() external view returns (uint64);

    /// @notice Returns value from totalWithdrawnAmounts array by _index
    /// @param _index The index at which the value will be returned
    function totalWithdrawnAmounts(uint256 _index) external view returns (uint256);

    /// @notice LP parameter that controls the charge in performance fees
    function lpPriceHighWaterMarkD18() external view returns (uint256);

    /// @notice List of addresses of depositors from which interaction with private vaults is allowed
    function depositorsAllowlist() external view returns (address[] memory);

    /// @notice Add new depositors in the depositorsAllowlist
    /// @param depositors Array of new depositors
    /// @dev The action can be done only by user with admins, owners or by approved rights
    function addDepositorsToAllowlist(address[] calldata depositors) external;

    /// @notice Remove depositors from the depositorsAllowlist
    /// @param depositors Array of depositors for remove
    /// @dev The action can be done only by user with admins, owners or by approved rights
    function removeDepositorsFromAllowlist(address[] calldata depositors) external;

    /// @notice The function of depositing the amount of tokens in exchange
    /// @param tokenAmounts Array of amounts of tokens for deposit
    /// @param minLpTokens Minimal value of LP tokens
    /// @param vaultOptions Options of vaults
    /// @return actualTokenAmounts Arrays of actual token amounts after deposit
    function deposit(
        uint256[] memory tokenAmounts,
        uint256 minLpTokens,
        bytes memory vaultOptions
    ) external returns (uint256[] memory actualTokenAmounts);

    /// @notice The function of withdrawing the amount of tokens in exchange
    /// @param to Address to which the withdrawal will be sent
    /// @param lpTokenAmount LP token amount, that requested for withdraw
    /// @param minTokenAmounts Array of minmal remining wtoken amounts after withdrawal
    /// @param vaultsOptions Options of vaults
    /// @return actualTokenAmounts Arrays of actual token amounts after withdrawal
    function withdraw(
        address to,
        uint256 lpTokenAmount,
        uint256[] memory minTokenAmounts,
        bytes[] memory vaultsOptions
    ) external returns (uint256[] memory actualTokenAmounts);
}
