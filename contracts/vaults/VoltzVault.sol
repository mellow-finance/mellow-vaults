// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.9;

import "../libraries/ExceptionsLibrary.sol";
import "./IntegrationVault.sol";
import "../interfaces/utils/IDefaultAccessControl.sol";

import "../interfaces/vaults/IVoltzVault.sol";
import "../interfaces/external/voltz/utils/Time.sol";

import "../utils/VoltzVaultHelper.sol";

/// @notice Vault that interfaces Voltz protocol in the integration layer on the liquidity provider (LP) side.
contract VoltzVault is IVoltzVault, IntegrationVault {
    using SafeERC20 for IERC20;
    using SafeCastUni for uint128;
    using SafeCastUni for int128;
    using SafeCastUni for uint256;
    using SafeCastUni for int256;
    using PRBMathSD59x18 for int256;
    using PRBMathUD60x18 for uint256;

    /// @dev The helper Voltz contract
    VoltzVaultHelper private _voltzVaultHelper;

    /// @dev The margin engine of Voltz Protocol
    IMarginEngine private _marginEngine;
    /// @dev The vamm of Voltz Protocol
    IVAMM private _vamm;
    /// @dev The rate oracle of Voltz Protocol
    IRateOracle private _rateOracle;
    /// @dev The periphery of Voltz Protocol
    IPeriphery private _periphery;

    /// @dev The VAMM tick spacing
    int24 private _tickSpacing;
    /// @dev The unix termEndTimestamp of the MarginEngine in Wad
    uint256 private _termEndTimestampWad;

    /// @dev The leverage used for LP positions on Voltz (in wad)
    uint256 private _leverageWad;
    /// @dev The multiplier used to decide how much margin is left in partially unwound positions on Voltz (in wad)
    uint256 private _marginMultiplierPostUnwindWad;

    /// @dev The estimated TVL
    int256 private _tvl;

    /// @dev Array of Vault-owned positions on Voltz with strictly positive cashflow
    TickRange[] public trackedPositions;
    /// @dev Index into the trackedPositions array of the currently active LP position of the Vault
    uint256 private _currentPositionIndex;
    /// @dev Maps a given Voltz position to its index into the trackedPositions array,
    /// @dev which is artifically 1-indexed by the mapping.
    mapping(bytes => uint256) private _positionToIndexPlusOne;
    /// @dev Number of positions settled and withdrawn from counting from the first position
    /// @dev in the trackedPositions array
    uint256 private _settledPositionsCount;

    /// @dev Sum of fixed token balances of all positions in the trackedPositions
    /// @dev array, apart from the balance of the currently active position
    int256 private _aggregatedInactiveFixedTokenBalance;
    /// @dev Sum of variable token balances of all positions in the trackedPositions
    /// @dev array, apart from the balance of the currently active position
    int256 private _aggregatedInactiveVariableTokenBalance;
    /// @dev Sum of margins of all positions in the trackedPositions array,
    /// @dev apart from the margin of the currently active position
    int256 private _aggregatedInactiveMargin;

    // -------------------  PUBLIC, MUTATING  -------------------

    /// @inheritdoc IVoltzVault
    function updateTvl() public override returns (uint256[] memory minTokenAmounts, uint256[] memory maxTokenAmounts) {
        int256 tvl_ = _voltzVaultHelper.calculateTVL(
            _aggregatedInactiveFixedTokenBalance,
            _aggregatedInactiveVariableTokenBalance,
            _aggregatedInactiveMargin
        );
        _tvl = tvl_;

        minTokenAmounts = new uint256[](1);
        maxTokenAmounts = new uint256[](1);

        if (tvl_ > 0) {
            minTokenAmounts[0] = tvl_.toUint256();
            maxTokenAmounts[0] = minTokenAmounts[0];
        }

        emit TvlUpdate(tvl_);
    }

    /// @inheritdoc IVoltzVault
    function settleVaultPositionAndWithdrawMargin(TickRange memory position) public override {
        VoltzVaultHelper voltzVaultHelper_ = _voltzVaultHelper;
        IMarginEngine marginEngine_ = _marginEngine;

        Position.Info memory positionInfo = voltzVaultHelper_.getVaultPosition(position);

        if (!positionInfo.isSettled) {
            marginEngine_.settlePosition(address(this), position.tickLower, position.tickUpper);
            positionInfo = voltzVaultHelper_.getVaultPosition(position);
        }

        if (positionInfo.margin > 0) {
            marginEngine_.updatePositionMargin(
                address(this),
                position.tickLower,
                position.tickUpper,
                -positionInfo.margin
            );
        }

        emit PositionSettledAndMarginWithdrawn(position.tickLower, position.tickUpper, positionInfo.margin);
    }

    // -------------------  EXTERNAL, VIEW  -------------------

    /// @inheritdoc IVoltzVault
    function leverageWad() external view override returns (uint256) {
        return _leverageWad;
    }

    /// @inheritdoc IVoltzVault
    function marginMultiplierPostUnwindWad() external view override returns (uint256) {
        return _marginMultiplierPostUnwindWad;
    }

    /// @inheritdoc IVault
    function tvl() public view override returns (uint256[] memory minTokenAmounts, uint256[] memory maxTokenAmounts) {
        minTokenAmounts = new uint256[](1);
        maxTokenAmounts = new uint256[](1);

        int256 tvl_ = _tvl;
        if (tvl_ > 0) {
            minTokenAmounts[0] = tvl_.toUint256();
            maxTokenAmounts[0] = minTokenAmounts[0];
        }
    }

    /// @inheritdoc IVoltzVault
    function marginEngine() external view override returns (IMarginEngine) {
        return _marginEngine;
    }

    /// @inheritdoc IVoltzVault
    function vamm() external view override returns (IVAMM) {
        return _vamm;
    }

    /// @inheritdoc IVoltzVault
    function rateOracle() external view override returns (IRateOracle) {
        return _rateOracle;
    }

    /// @inheritdoc IVoltzVault
    function periphery() external view override returns (IPeriphery) {
        return _periphery;
    }

    /// @inheritdoc IVoltzVault
    function currentPosition() external view override returns (TickRange memory) {
        return trackedPositions[_currentPositionIndex];
    }

    /// @inheritdoc IVoltzVault
    function voltzVaultHelper() external view override returns (address) {
        return address(_voltzVaultHelper);
    }

    /// @inheritdoc IntegrationVault
    function supportsInterface(bytes4 interfaceId) public view override(IERC165, IntegrationVault) returns (bool) {
        return super.supportsInterface(interfaceId) || (interfaceId == type(IVoltzVault).interfaceId);
    }

    // -------------------  EXTERNAL, MUTATING  -------------------

    /// @inheritdoc IVoltzVault
    function setLeverageWad(uint256 leverageWad_) external override {
        require(_isAdmin(msg.sender) || _isStrategy(msg.sender), ExceptionsLibrary.FORBIDDEN);
        _leverageWad = leverageWad_;
    }

    /// @inheritdoc IVoltzVault
    function setMarginMultiplierPostUnwindWad(uint256 marginMultiplierPostUnwindWad_) external override {
        require(_isAdmin(msg.sender) || _isStrategy(msg.sender), ExceptionsLibrary.FORBIDDEN);
        _marginMultiplierPostUnwindWad = marginMultiplierPostUnwindWad_;
        _voltzVaultHelper.setMarginMultiplierPostUnwindWad(marginMultiplierPostUnwindWad_);
    }

    /// @inheritdoc IVoltzVault
    function rebalance(TickRange memory position) external override {
        require(_isAdmin(msg.sender) || _isStrategy(msg.sender), ExceptionsLibrary.FORBIDDEN);
        require(Time.blockTimestampScaled() <= _termEndTimestampWad, ExceptionsLibrary.FORBIDDEN);

        TickRange memory oldPosition = trackedPositions[_currentPositionIndex];
        Position.Info memory oldPositionInfo = _voltzVaultHelper.getVaultPosition(oldPosition);

        // burn liquidity first, then unwind and exit existing position
        // this makes sure that we do not use our own liquidity to unwind ourselves
        _mintOrBurnLiquidity(oldPosition, oldPositionInfo._liquidity, false);
        int256 marginLeftInOldPosition = _unwindAndExitCurrentPosition(oldPosition, oldPositionInfo);

        _updateCurrentPosition(position);

        uint256 vaultBalance = IERC20(_vaultTokens[0]).balanceOf(address(this));
        _updateMargin(position, vaultBalance.toInt256());
        uint256 notionalLiquidityToMint = vaultBalance.mul(_leverageWad);
        _mintOrBurnLiquidityNotional(position, notionalLiquidityToMint.toInt256());

        updateTvl();

        emit PositionRebalance(oldPosition, marginLeftInOldPosition, position, vaultBalance, notionalLiquidityToMint);
    }

    /// @inheritdoc IVoltzVault
    function initialize(
        uint256 nft_,
        address[] memory vaultTokens_,
        address marginEngine_,
        address periphery_,
        address voltzVaultHelper_,
        InitializeParams memory initializeParams
    ) external override {
        require(vaultTokens_.length == 1, ExceptionsLibrary.INVALID_VALUE);

        IMarginEngine marginEngine__ = IMarginEngine(marginEngine_);
        _marginEngine = marginEngine__;

        address underlyingToken = address(marginEngine__.underlyingToken());
        require(vaultTokens_[0] == underlyingToken, ExceptionsLibrary.INVALID_VALUE);

        _initialize(vaultTokens_, nft_);

        IPeriphery periphery__ = IPeriphery(periphery_);
        _periphery = periphery__;

        IVAMM vamm__ = marginEngine__.vamm();
        _vamm = vamm__;

        _rateOracle = marginEngine__.rateOracle();
        _tickSpacing = vamm__.tickSpacing();
        _termEndTimestampWad = marginEngine__.termEndTimestampWad();

        require(Time.blockTimestampScaled() <= _termEndTimestampWad, ExceptionsLibrary.FORBIDDEN);

        _leverageWad = initializeParams.leverageWad;
        _marginMultiplierPostUnwindWad = initializeParams.marginMultiplierPostUnwindWad;
        _updateCurrentPosition(TickRange(initializeParams.tickLower, initializeParams.tickUpper));

        VoltzVaultHelper voltzVaultHelper__ = VoltzVaultHelper(voltzVaultHelper_);
        voltzVaultHelper__.initialize();
        _voltzVaultHelper = voltzVaultHelper__;

        emit VaultInitialized(
            marginEngine_,
            periphery_,
            voltzVaultHelper_,
            initializeParams.tickLower,
            initializeParams.tickUpper,
            initializeParams.leverageWad,
            initializeParams.marginMultiplierPostUnwindWad
        );
    }

    /// @inheritdoc IVoltzVault
    function settleVault(uint256 batchSize) external override returns (uint256 settledBatchSize) {
        uint256 from = _settledPositionsCount;
        if (batchSize == 0) {
            batchSize = trackedPositions.length - from;
        }

        uint256 to = from + batchSize;
        if (trackedPositions.length < to) {
            to = trackedPositions.length;
        }

        if (to <= from) {
            return 0;
        }

        for (uint256 i = from; i < to; i++) {
            settleVaultPositionAndWithdrawMargin(trackedPositions[i]);
        }

        settledBatchSize = to - from;
        _settledPositionsCount += settledBatchSize;

        emit VaultSettle(batchSize, from, to);
    }

    // -------------------  INTERNAL, PURE  -------------------

    /// @inheritdoc IntegrationVault
    function _isReclaimForbidden(address) internal pure override returns (bool) {
        return false;
    }

    // -------------------  INTERNAL, VIEW  -------------------

    /// @notice Checks whether a contract is the approved strategy for this vault
    /// @param addr The address of the contract to be checked
    /// @return Returns true if addr is the address of the strategy contract approved by the vault
    function _isStrategy(address addr) internal view returns (bool) {
        return _vaultGovernance.internalParams().registry.getApproved(_nft) == addr;
    }

    /// @notice Checks whether an address is the approved admin of the strategy
    /// @param addr The address to be checked
    /// @return Returns true if addr is the admin of the strategy
    function _isAdmin(address addr) internal view returns (bool) {
        return IDefaultAccessControl(_vaultGovernance.internalParams().registry.getApproved(_nft)).isAdmin(addr);
    }

    // -------------------  INTERNAL, MUTATING  -------------------

    /// @inheritdoc IntegrationVault
    function _push(uint256[] memory tokenAmounts, bytes memory)
        internal
        override
        returns (uint256[] memory actualTokenAmounts)
    {
        actualTokenAmounts = new uint256[](1);
        actualTokenAmounts[0] = tokenAmounts[0];
        TickRange memory currentPosition_ = trackedPositions[_currentPositionIndex];
        _updateMargin(currentPosition_, tokenAmounts[0].toInt256());

        uint256 notionalLiquidityToMint = tokenAmounts[0].mul(_leverageWad);
        _mintOrBurnLiquidityNotional(currentPosition_, notionalLiquidityToMint.toInt256());

        updateTvl();

        emit PushDeposit(tokenAmounts[0], notionalLiquidityToMint);
    }

    /// @inheritdoc IntegrationVault
    function _pull(
        address to,
        uint256[] memory tokenAmounts,
        bytes memory
    ) internal override returns (uint256[] memory actualTokenAmounts) {
        require(Time.blockTimestampScaled() > _termEndTimestampWad, ExceptionsLibrary.FORBIDDEN);

        actualTokenAmounts = new uint256[](1);

        uint256 vaultBalance = IERC20(_vaultTokens[0]).balanceOf(address(this));

        uint256 amountToWithdraw = tokenAmounts[0];
        if (vaultBalance < amountToWithdraw) {
            amountToWithdraw = vaultBalance;
        }

        if (amountToWithdraw == 0) {
            return actualTokenAmounts;
        }

        IERC20(_vaultTokens[0]).safeTransfer(to, amountToWithdraw);
        actualTokenAmounts[0] = amountToWithdraw;

        updateTvl();

        emit PullWithdraw(to, tokenAmounts[0], actualTokenAmounts[0]);
    }

    /// @notice Updates the margin of the currently active LP position
    /// @param currentPosition_ The current active position
    /// @param marginDelta Change in the margin account of the position
    function _updateMargin(TickRange memory currentPosition_, int256 marginDelta) internal {
        IPeriphery periphery_ = _periphery;

        if (marginDelta == 0) {
            return;
        }

        if (marginDelta > 0) {
            IERC20(_vaultTokens[0]).safeIncreaseAllowance(address(periphery_), marginDelta.toUint256());
        }

        periphery_.updatePositionMargin(
            _marginEngine,
            currentPosition_.tickLower,
            currentPosition_.tickUpper,
            marginDelta,
            false
        );

        if (marginDelta > 0) {
            IERC20(_vaultTokens[0]).safeApprove(address(periphery_), 0);
        }
    }

    /// @notice Mints or burns liquidity notional in the currently active LP position
    /// @param liquidityNotionalDelta The change in pool liquidity notional as a result of the position update
    function _mintOrBurnLiquidityNotional(TickRange memory currentPosition_, int256 liquidityNotionalDelta) internal {
        if (liquidityNotionalDelta != 0) {
            uint128 liquidity = _voltzVaultHelper.getLiquidityFromNotional(liquidityNotionalDelta);
            _mintOrBurnLiquidity(currentPosition_, liquidity, (liquidityNotionalDelta >= 0));
        }
    }

    /// @notice Mints or burns liquidity in the currently active LP position
    /// @param liquidity The change in pool liquidity as a result of the position update
    /// @param isMint true if mint, false if burn
    function _mintOrBurnLiquidity(
        TickRange memory currentPosition_,
        uint128 liquidity,
        bool isMint
    ) internal {
        if (liquidity > 0) {
            if (isMint) {
                _vamm.mint(address(this), currentPosition_.tickLower, currentPosition_.tickUpper, liquidity);
            } else {
                _vamm.burn(address(this), currentPosition_.tickLower, currentPosition_.tickUpper, liquidity);
            }
        }
    }

    /// @notice Updates the currently active LP position of the Vault
    /// @dev The function adds the new position to the trackedPositions
    /// @dev array (if not present already), and updates the currentPositionIndex,
    /// @dev mapping and aggregated variables accordingly.
    /// @param position The new current position of the Vault
    function _updateCurrentPosition(TickRange memory position) internal {
        Tick.checkTicks(position.tickLower, position.tickUpper);

        int24 tickSpacing = _tickSpacing;
        require(position.tickLower % tickSpacing == 0, ExceptionsLibrary.INVALID_VALUE);
        require(position.tickUpper % tickSpacing == 0, ExceptionsLibrary.INVALID_VALUE);

        bytes memory encodedPosition = abi.encode(position);
        if (_positionToIndexPlusOne[encodedPosition] == 0) {
            trackedPositions.push(position);
            _currentPositionIndex = trackedPositions.length - 1;
            _positionToIndexPlusOne[encodedPosition] = trackedPositions.length;
        } else {
            // we rebalance to some previous position
            // so we need to update the aggregate variables
            _currentPositionIndex = _positionToIndexPlusOne[encodedPosition] - 1;
            Position.Info memory currentPositionInfo_ = _voltzVaultHelper.getVaultPosition(position);
            _aggregatedInactiveFixedTokenBalance -= currentPositionInfo_.fixedTokenBalance;
            _aggregatedInactiveVariableTokenBalance -= currentPositionInfo_.variableTokenBalance;
            _aggregatedInactiveMargin -= currentPositionInfo_.margin;
        }
    }

    /// @notice Unwinds the currently active position and withdraws the maximum amount of funds possible
    /// @dev The function unwinds the currently active position and proceeds as follows:
    /// @dev 1. if variableTokenBalance != 0, withdraw all funds up to marginMultiplierPostUnwind * positionMarginRequirementInitial
    /// @dev 2. otherwise, if fixedTokenBalance > 0, withdraw everything
    /// @dev 3. otherwise, if fixedTokenBalance <= 0, withdraw everything up to positionMarginRequirementInitial
    /// @dev The unwound position is tracked only in cases 1 and 2
    /// @return marginLeftInOldPosition The margin left in the unwound position
    function _unwindAndExitCurrentPosition(TickRange memory currentPosition_, Position.Info memory currentPositionInfo_)
        internal
        returns (int256 marginLeftInOldPosition)
    {
        if (currentPositionInfo_.variableTokenBalance != 0) {
            bool _isFT = currentPositionInfo_.variableTokenBalance < 0;

            IVAMM.SwapParams memory _params = IVAMM.SwapParams({
                recipient: address(this),
                amountSpecified: currentPositionInfo_.variableTokenBalance,
                sqrtPriceLimitX96: _isFT ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1,
                tickLower: currentPosition_.tickLower,
                tickUpper: currentPosition_.tickUpper
            });

            try _vamm.swap(_params) returns (
                int256 _fixedTokenDelta,
                int256 _variableTokenDelta,
                uint256 _cumulativeFeeIncurred,
                int256,
                int256
            ) {
                currentPositionInfo_.fixedTokenBalance += _fixedTokenDelta;
                currentPositionInfo_.variableTokenBalance += _variableTokenDelta;
                currentPositionInfo_.margin -= _cumulativeFeeIncurred.toInt256();
            } catch Error(string memory reason) {
                emit UnwindFail(reason);
            } catch {
                emit UnwindFail("Unwind failed without reason");
            }
        }

        bool trackPosition;
        uint256 marginToKeep;
        (trackPosition, marginToKeep) = _voltzVaultHelper.getMarginToKeep(currentPositionInfo_);

        if (currentPositionInfo_.margin > 0) {
            if (marginToKeep > currentPositionInfo_.margin.toUint256()) {
                marginToKeep = currentPositionInfo_.margin.toUint256();
            }

            _updateMargin(currentPosition_, -(currentPositionInfo_.margin - marginToKeep.toInt256()));
            currentPositionInfo_.margin = marginToKeep.toInt256();
        }

        if (!trackPosition) {
            // no need to track it, so we remove it from the array
            _removePositionFromTrackedPositions(_currentPositionIndex);
        } else {
            // otherwise, the position is now a past tracked position
            // so we update the aggregated variables
            _aggregatedInactiveFixedTokenBalance += currentPositionInfo_.fixedTokenBalance;
            _aggregatedInactiveVariableTokenBalance += currentPositionInfo_.variableTokenBalance;
            _aggregatedInactiveMargin += currentPositionInfo_.margin;
        }

        return currentPositionInfo_.margin;
    }

    /// @notice Untracks position
    /// @dev Removes position from the trackedPositions array and
    /// @dev updates the mapping and aggregated variables accordingly
    function _removePositionFromTrackedPositions(uint256 positionIndex) internal {
        _positionToIndexPlusOne[abi.encode(trackedPositions[positionIndex])] = 0;
        if (positionIndex != trackedPositions.length - 1) {
            delete trackedPositions[positionIndex];
            trackedPositions[positionIndex] = trackedPositions[trackedPositions.length - 1];
            _positionToIndexPlusOne[abi.encode(trackedPositions[positionIndex])] = positionIndex + 1;
        }

        trackedPositions.pop();
    }
}
