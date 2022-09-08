// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./IIntegrationVault.sol";
import "../external/voltz/IMarginEngine.sol";
import "../external/voltz/IVAMM.sol";

interface IVoltzVault is IIntegrationVault {
    struct Options {
        int256 notionalForLiquidity;
        int256 notionalForTrade;
        uint160 sqrtPriceLimitX96;
        bool updatePosition;
        int24 newTickLow;
        int24 newTickHigh;
        bool closingPositions;
        uint256 batchForClosingPositions;
    }

    struct TickRange {
        int24 low;
        int24 high;
    }

    struct OpenedPositions {
        mapping (bytes => bool) initializedRange;
        TickRange[] ranges;
        uint256 closing;
    }

    /// @notice list of opened positions
    function openedPositions() external view returns (TickRange[] memory);

    /// @notice number of opened positions
    function numberOpenedPositions() external view returns (uint256);

    /// @notice number of closed positions
    function closing() external view returns (uint256);

    /// @notice checks if some range is initialized
    function isRangeInitialized(TickRange memory ticks) external view returns (bool);

    /// @notice Reference to IMarginEngine of Voltz Protocol.
    function marginEngine() external view returns (IMarginEngine);

    /// @notice Reference to IVAMM of Voltz Protocol.
    function vamm() external view returns (IVAMM);

    /// @notice tick ranges of current position
    function currentPosition() external view returns (TickRange memory);

    /// @notice convert liquidity into notional
    function liquidityToNotional(uint128 liquidity) external view returns (uint256);

    /// @notice convert notional into liquidity
    function notionalToLiquidity(uint256 notional) external view returns (uint128);

    /// @notice Initialized a new contract.
    /// @dev Can only be initialized by vault governance
    /// @param nft_ NFT of the vault in the VaultRegistry
    /// @param vaultTokens_ ERC20 tokens that will be managed by this Vault
    /// @param marginEngine_ the underlying margin engine of the Voltz pool
    function initialize(
        uint256 nft_,
        address[] memory vaultTokens_,
        address marginEngine_,
        int24 initialTickLow_,
        int24 initialTickHigh_
    ) external;

    /// @notice tvl() is view so we need to update the position before getting it
    function updateTvl() external;
}
