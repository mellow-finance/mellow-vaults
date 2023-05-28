// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.9;

import "../external/aave/ILendingPool.sol";
import "./IIntegrationVault.sol";

interface IAaveVault is IIntegrationVault {
    /// @notice Reference to Aave protocol lending pool.
    function lendingPool() external view returns (ILendingPool);

    /// @notice Update all tvls to current aToken balances.
    function updateTvls() external;

    /// @notice Initialized a new contract.
    /// @dev Can only be initialized by vault governance
    /// @param nft_ NFT of the vault in the VaultRegistry
    /// @param vaultTokens_ ERC20 tokens that will be managed by this Vault
    function initialize(uint256 nft_, address[] memory vaultTokens_, bool[] memory tokenStatus_) external;

    function borrow(address token, address to, uint256 amount) external;

    function repay(address token, address from, uint256 amount) external;

    function getDebt(address token) external view returns (uint256 debt);

    function tokenStatus(uint256) external view returns (bool);

    function aTokens(uint256) external view returns (address);

    function getLTV(address token) external view returns (uint256 ltv);
}
