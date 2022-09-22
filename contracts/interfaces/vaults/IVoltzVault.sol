// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./IIntegrationVault.sol";
import "../external/voltz/IMarginEngine.sol";
import "../external/voltz/IVAMM.sol";
import "../external/voltz/IPeriphery.sol";

interface IVoltzVault is IIntegrationVault {
    struct TickRange {
        int24 tickLower;
        int24 tickUpper;
    }

    /// @notice Reference to IMarginEngine of Voltz Protocol.
    function marginEngine() external view returns (IMarginEngine);

    /// @notice Reference to IVAMM of Voltz Protocol.
    function vamm() external view returns (IVAMM);

    /// @notice Initializes a new contract.
    /// @dev Can only be initialized by vault governance
    /// @param nft_ NFT of the vault in the VaultRegistry
    /// @param vaultTokens_ ERC20 tokens that will be managed by this Vault
    /// @param marginEngine_ the underlying margin engine of the Voltz pool
    function initialize(
        uint256 nft_,
        address[] memory vaultTokens_,
        address marginEngine_,
        int24 initialTickLower,
        int24 intitialTickUpper
    ) external;

    /// @notice Updates ticks of current active position
    /// @dev Unwinds existing active position and 
    /// @dev creates a new one with the new ticks
    /// @param ticks The lower and upper ticks of the new position
    function rebalance(TickRange memory ticks) external;

    /// @notice tick range of current position
    function currentPosition() external view returns (TickRange memory);
}
