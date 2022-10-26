// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./IIntegrationVault.sol";
import "../external/voltz/IMarginEngine.sol";
import "../external/voltz/IPeriphery.sol";
import "../external/voltz/IVAMM.sol";
import "../external/voltz/rate_oracles/IRateOracle.sol";

interface IVoltzVault is IIntegrationVault {
    /// @dev LP Position on Voltz
    struct TickRange {
        /// @dev Lower tick of LP position on Voltz
        int24 tickLower;
        /// @dev Upper tick of LP position on Voltz
        int24 tickUpper;
    }

    struct InitializeParams {
        /// @dev Lower tick of initial LP position on Voltz
        int24 tickLower;
        /// @dev Upper tick of initial LP position on Voltz
        int24 tickUpper;
        /// @dev Leverage used for LP positions on Voltz (in wad)
        uint256 leverageWad; 
        /// @dev Multiplier used to decide how much margin is left in partially unwound positions on Voltz (in wad)
        uint256 marginMultiplierPostUnwindWad;
    }

    // -------------------  EXTERNAL, VIEW  -------------------

    /// @notice Returns the leverage used for LP positions on Voltz (in wad)
    function leverageWad() external view returns (uint256);

    /// @notice Returns the multiplier used to decide how much margin is 
    /// @notice left in partially unwound positions on Voltz (in wad)
    function marginMultiplierPostUnwindWad() external view returns (uint256);

    /// @notice Reference to the margin engine of Voltz Protocol
    function marginEngine() external view returns (IMarginEngine);

    /// @notice Reference to the vamm of Voltz Protocol
    function vamm() external view returns (IVAMM);

    /// @notice Reference to the rate oracle of Voltz Protocol
    function rateOracle() external view returns (IRateOracle);

    /// @notice Reference to the periphery of Voltz Protocol
    function periphery() external view returns (IPeriphery);

    /// @notice Returns the currently active LP position of the Vault
    function currentPosition() external view returns (TickRange memory);

    /// @notice Returns the address of the associated Voltz Vault Helper
    function voltzVaultHelper() external view returns (address);

    // -------------------  EXTERNAL, MUTATING  -------------------

    /// @notice Initializes a new vault
    /// @dev Can only be initialized by vault governance
    /// @param nft_ NFT of the vault in the VaultRegistry
    /// @param vaultTokens_ ERC20 tokens that will be managed by this Vault
    /// @param marginEngine_ the underlying margin engine of the Voltz pool
    /// @param initializeParams the InitializeParams used to initiate the vault
    function initialize(
        uint256 nft_,
        address[] memory vaultTokens_,
        address marginEngine_,
        address periphery_,
        address voltzHelper_,
        InitializeParams memory initializeParams
    ) external;

    /// @notice Vault's available funds are moved to a new LP position
    /// @dev Unwinds existing active position and funnels 
    /// @dev available funds into a new LP position on Voltz
    /// @param position The new LP position on Voltz
    function rebalance(TickRange memory position) external;

    /// @notice Settles Vault-owned position on Voltz and withdraws margin
    /// @dev The function settles position only if not settled before and
    /// @dev withdraws all available funds
    /// @param position The LP position to be settled and withdrawn from
    function settleVaultPositionAndWithdrawMargin(TickRange memory position) external;

    /// @notice Settles up to batchSize Vault-owned positions on Voltz and withdraws margin
    /// @dev Only positions with strictly positive cashflows are settled
    /// @dev and withdrawn from
    /// @param batchSize Limit on the number of positions to be settled (settles all positions if 0)
    /// @return settledBatchSize Number of positions which were settled and withdrawn from
    function settleVault(uint256 batchSize) external returns (uint256 settledBatchSize);

    /// @notice Updates estimated tvl values
    function updateTvl() external returns (
        uint256[] memory minTokenAmounts, 
        uint256[] memory maxTokenAmounts
    ); 

    /// @notice Sets the leverage used for LP positions on Voltz (in wad)
    function setLeverageWad(uint256 leverageWad) external;

    /// @notice Sets the multiplier used to decide how much margin is 
    /// @notice left in partially unwound positions on Voltz (in wad)
    function setMarginMultiplierPostUnwindWad(uint256 marginMultiplierPostUnwindWad) external;

    // -------------------  EVENTS  -------------------

    /// @notice Emitted when active LP position is changed
    /// @param oldPosition the previous active position
    /// @param marginLeftInOldPosition margin left in previous unwound position
    /// @param newPosition the new active position
    /// @param marginDepositedInNewPosition margin deposited in the new active position
    /// @param notionalLiquidityMintedInNewPosition the amount of notional that was minted as liquidity in the new position
    event PositionRebalance(
        TickRange oldPosition,
        int256 marginLeftInOldPosition,
        TickRange newPosition,
        uint256 marginDepositedInNewPosition,
        uint256 notionalLiquidityMintedInNewPosition
    );

    /// @notice Emitted when Vault is initialised
    /// @param marginEngine The address of the Voltz margin engine
    /// @param periphery The address of the Voltz periphery
    /// @param voltzVaultHelper The address of the Voltz Vault helper
    /// @param tickLower Lower tick of initial LP position on Voltz
    /// @param tickUpper Upper tick of initial LP position on Voltz
    /// @param leverageWad Leverage used for LP positions on Voltz (in wad)
    /// @param marginMultiplierPostUnwindWad Multiplier used to decide how much margin is left in partially unwound positions on Voltz (in wad)
    event VaultInitialized(
        address indexed marginEngine,
        address indexed periphery,
        address indexed voltzVaultHelper,
        int24 tickLower,
        int24 tickUpper,
        uint256 leverageWad,
        uint256 marginMultiplierPostUnwindWad
    );

    /// @notice Emitted when tokens are deposited into the Vault
    /// @param amountDeposited The amount depositied
    /// @param notionalLiquidityMinted The amount of liquidity minted on deposit
    event PushDeposit(
        uint256 amountDeposited,
        uint256 notionalLiquidityMinted
    );

    /// @notice Emitted when tokens are withdrawn from the Vault
    /// @param to Address of recipient
    /// @param amountRequestedToWithdraw The amount requested to be withdrawn
    /// @param amountWithdrawn The amount sent to the recipient
    event PullWithdraw(
        address to,
        uint256 amountRequestedToWithdraw,
        uint256 amountWithdrawn
    );

    /// @notice Emitted when TVL is updated
    /// @param tvl The estimated TVL
    event TvlUpdate(
        int256 tvl
    );

    /// @notice Emitted when a single Vault-owned position is settled and withdrawn from
    /// @param tickLower The lower tick of the position
    /// @param tickUpper The upper tick of the position
    /// @param margin The margin withdrawn
    event PositionSettledAndMarginWithdrawn(
        int24 tickLower,
        int24 tickUpper,
        int256 margin
    );

    /// @notice Emitted when multilpe Vault-owned positions are settled and withdrawn from
    /// @param batchSizeRequested The number of positions requested to be settled and withdrawn from
    /// @param fromIndex The index of the first position from the trackedPositions array to be settled and withdrawn from
    /// @param toIndex The index of the last position from the trackedPositions array to be settled and withdrawn from
    event VaultSettle(
        uint256 batchSizeRequested,
        uint256 fromIndex,
        uint256 toIndex
    );

    /// @notice Emitted when unwind fails
    /// @param reason Reason of failure
    event UnwindFail(
        string reason
    );
}
