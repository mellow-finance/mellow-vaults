// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.9;

import "../libraries/ExceptionsLibrary.sol";
import "./IntegrationVault.sol";

import "../interfaces/vaults/IVoltzVault.sol";

import "../utils/VoltzHelper.sol";

import "../interfaces/external/voltz/utils/Time.sol";
import "../interfaces/external/voltz/utils/Position.sol";
import "../interfaces/external/voltz/utils/TickMath.sol";

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
    VoltzHelper private _voltzHelper;

    /// @dev The margin engine of Voltz Protocol
    IMarginEngine public _marginEngine;
    /// @dev The vamm of Voltz Protocol
    IVAMM public _vamm;
    /// @dev The rate oracle of Voltz Protocol
    IRateOracle public _rateOracle;
    /// @dev The periphery of Voltz Protocol
    IPeriphery public _periphery;

    /// @dev The VAMM tick spacing
    int24 _tickSpacing;
    /// @dev The unix termStartTimestamp of the MarginEngine in Wad
    uint256 _termStartTimestampWad;
    /// @dev The unix termEndTimestamp of the MarginEngine in Wad
    uint256 _termEndTimestampWad;

    /// @dev The leverage used for LP positions on Voltz (in wad)
    uint256 _leverageWad;
    /// @dev The multiplier used to decide how much margin is left in partially unwound positions on Voltz (in wad)
    uint256 _marginMultiplierPostUnwindWad;
    /// @dev The lookback window used to compute the historical APY that estimates the APY from current to the end of Voltz pool (in seconds)
    uint256 _lookbackWindowInSeconds;
    /// @dev The decimal delta used to compute lower and upper limits of estimated APY: (1 +/- delta) * estimatedAPY (in wad)
    uint256 _estimatedAPYDecimalDeltaWad;

    /// @dev The minimum estimated TVL
    int256 _minTVL;
    /// @dev The maximum estimated TVL
    int256 _maxTVL;
    /// @dev The unix timestamp of the last TVL update
    uint256 _lastTvlUpdateTimestamp;

    /// @dev Array of Vault-owned positions on Voltz with strictly positive cashflow
    TickRange[] public trackedPositions;
    /// @dev Index into the trackedPositions array of the currently active LP position of the Vault
    uint256 _currentPositionIndex;
    /// @dev The amount of liquidity minted in the currently active LP position of the Vault
    uint256 _currentPositionLiquidity;
    /// @dev Maps a given Voltz position to its index into the trackedPositions array,
    /// @dev which is artifically 1-indexed by the mapping.
    mapping(bytes => uint256) positionToIndexPlusOne;
    /// @dev Number of positions settled and withdrawn from counting from the first position
    /// @dev in the trackedPositions array
    uint256 settledPositionsCount;

    /// @dev Sum of fixed token balances of all positions in the trackedPositions
    /// @dev array, apart from the balance of the currently active position
    int256 _aggregatedInactiveFixedTokenBalance;
    /// @dev Sum of variable token balances of all positions in the trackedPositions
    /// @dev array, apart from the balance of the currently active position
    int256 _aggregatedInactiveVariableTokenBalance;
    /// @dev Sum of margins of all positions in the trackedPositions array,
    /// @dev apart from the margin of the currently active position
    int256 _aggregatedInactiveMargin;

    // -------------------  PUBLIC, MUTATING  -------------------

    /// @inheritdoc IVoltzVault
    function updateTvl() public override returns (uint256[] memory minTokenAmounts, uint256[] memory maxTokenAmounts) {
        (_minTVL, _maxTVL) = _voltzHelper.calculateTVL(
            _aggregatedInactiveFixedTokenBalance,
            _aggregatedInactiveVariableTokenBalance,
            _aggregatedInactiveMargin
        );

        minTokenAmounts = new uint256[](1);
        maxTokenAmounts = new uint256[](1);

        if (_minTVL > 0) {
            minTokenAmounts[0] = _minTVL.toUint256();
        }

        if (_maxTVL > 0) {
            maxTokenAmounts[0] = _maxTVL.toUint256();
        }

        _lastTvlUpdateTimestamp = block.timestamp;
        emit TvlUpdate(_minTVL, _maxTVL, _lastTvlUpdateTimestamp);
    }

    /// @inheritdoc IVoltzVault
    function settleVaultPositionAndWithdrawMargin(TickRange memory position) public override {
        Position.Info memory positionInfo = _voltzHelper.getVaultPosition(position);

        if (!positionInfo.isSettled) {
            _marginEngine.settlePosition(address(this), position.tickLower, position.tickUpper);
        }

        positionInfo = _voltzHelper.getVaultPosition(position);

        if (positionInfo.margin > 0) {
            _marginEngine.updatePositionMargin(
                address(this),
                position.tickLower,
                position.tickUpper,
                -positionInfo.margin
            );
        }

        emit PositionSettledAndMarginWithdrawn(position.tickLower, position.tickUpper);
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

    /// @inheritdoc IVoltzVault
    function lookbackWindow() external view override returns (uint256) {
        return _lookbackWindowInSeconds;
    }

    /// @inheritdoc IVoltzVault
    function estimatedAPYDecimalDeltaWad() external view override returns (uint256) {
        return _estimatedAPYDecimalDeltaWad;
    }

    /// @inheritdoc IVault
    function tvl() public view override returns (uint256[] memory minTokenAmounts, uint256[] memory maxTokenAmounts) {
        minTokenAmounts = new uint256[](1);
        maxTokenAmounts = new uint256[](1);

        if (_minTVL > 0) {
            minTokenAmounts[0] = _minTVL.toUint256();
        }

        if (_maxTVL > 0) {
            maxTokenAmounts[0] = _maxTVL.toUint256();
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

    /// @inheritdoc IntegrationVault
    function supportsInterface(bytes4 interfaceId) public view override(IERC165, IntegrationVault) returns (bool) {
        return super.supportsInterface(interfaceId) || (interfaceId == type(IVoltzVault).interfaceId);
    }

    // -------------------  EXTERNAL, MUTATING  -------------------

    /// @inheritdoc IVoltzVault
    function setLeverageWad(uint256 leverageWad_) external override {
        require(_isApprovedOrOwner(msg.sender), ExceptionsLibrary.FORBIDDEN);
        _leverageWad = leverageWad_;
    }

    /// @inheritdoc IVoltzVault
    function setMarginMultiplierPostUnwindWad(uint256 marginMultiplierPostUnwindWad_) external override {
        require(_isApprovedOrOwner(msg.sender), ExceptionsLibrary.FORBIDDEN);
        _marginMultiplierPostUnwindWad = marginMultiplierPostUnwindWad_;
        _voltzHelper.setMarginMultiplierPostUnwindWad(marginMultiplierPostUnwindWad_);
    }

    /// @inheritdoc IVoltzVault
    function setLookbackWindow(uint256 lookbackWindowInSeconds_) external override {
        require(_isApprovedOrOwner(msg.sender), ExceptionsLibrary.FORBIDDEN);
        _lookbackWindowInSeconds = lookbackWindowInSeconds_;
        _voltzHelper.setLookbackWindow(lookbackWindowInSeconds_);
    }

    /// @inheritdoc IVoltzVault
    function setEstimatedAPYDecimalDeltaWad(uint256 estimatedAPYDecimalDeltaWad_) external override {
        require(_isApprovedOrOwner(msg.sender), ExceptionsLibrary.FORBIDDEN);
        _estimatedAPYDecimalDeltaWad = estimatedAPYDecimalDeltaWad_;
        _voltzHelper.setEstimatedAPYDecimalDeltaWad(estimatedAPYDecimalDeltaWad_);
    }

    /// @inheritdoc IVoltzVault
    function rebalance(TickRange memory position) external override {
        require(_isApprovedOrOwner(msg.sender) || _isStrategy(msg.sender), ExceptionsLibrary.FORBIDDEN);

        TickRange memory oldPosition = trackedPositions[_currentPositionIndex];

        // burn liquidity first, then unwind and exit existing position
        // this makes sure that we do not use our own liquidity to unwind ourselves
        _updateLiquidity(-_currentPositionLiquidity.toInt256());
        int256 marginLeftInOldPosition = _unwindAndExitCurrentPosition();

        _updateCurrentPosition(position);
        uint256 vaultBalance = IERC20(_vaultTokens[0]).balanceOf(address(this));
        _updateMargin(vaultBalance.toInt256());
        uint256 notionalLiquidityToMint = vaultBalance.mul(_leverageWad);
        _updateLiquidity(notionalLiquidityToMint.toInt256());

        updateTvl();

        emit PositionRebalance(
            oldPosition,
            marginLeftInOldPosition,
            trackedPositions[_currentPositionIndex],
            vaultBalance,
            notionalLiquidityToMint
        );
    }

    /// @inheritdoc IVoltzVault
    function initialize(
        uint256 nft_,
        address[] memory vaultTokens_,
        address marginEngine_,
        address periphery_,
        address voltzHelper_,
        InitializeParams memory initializeParams
    ) external override {
        require(vaultTokens_.length == 1, ExceptionsLibrary.INVALID_VALUE);

        _marginEngine = IMarginEngine(marginEngine_);

        address underlyingToken = address(_marginEngine.underlyingToken());
        require(vaultTokens_[0] == underlyingToken, ExceptionsLibrary.INVALID_VALUE);

        _initialize(vaultTokens_, nft_);

        _periphery = IPeriphery(periphery_);
        _vamm = _marginEngine.vamm();
        _rateOracle = _marginEngine.rateOracle();
        _tickSpacing = _vamm.tickSpacing();
        _termStartTimestampWad = _marginEngine.termStartTimestampWad();
        _termEndTimestampWad = _marginEngine.termEndTimestampWad();

        _leverageWad = initializeParams.leverageWad;
        _marginMultiplierPostUnwindWad = initializeParams.marginMultiplierPostUnwindWad;
        _lookbackWindowInSeconds = initializeParams.lookbackWindowInSeconds;
        _estimatedAPYDecimalDeltaWad = initializeParams.estimatedAPYDecimalDeltaWad;
        _updateCurrentPosition(TickRange(initializeParams.tickLower, initializeParams.tickUpper));

        _voltzHelper = VoltzHelper(voltzHelper_);

        emit VaultInitialized(
            marginEngine_,
            initializeParams.tickLower,
            initializeParams.tickUpper,
            initializeParams.leverageWad,
            initializeParams.marginMultiplierPostUnwindWad,
            initializeParams.lookbackWindowInSeconds,
            initializeParams.estimatedAPYDecimalDeltaWad
        );
    }

    /// @inheritdoc IVoltzVault
    function settleVault(uint256 batchSize) external override returns (uint256 settledBatchSize) {
        if (batchSize == 0) {
            batchSize = trackedPositions.length - settledPositionsCount;
        }

        uint256 from = settledPositionsCount;
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
        settledPositionsCount += settledBatchSize;

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

    // -------------------  INTERNAL, MUTATING  -------------------

    /// @inheritdoc IntegrationVault
    function _push(uint256[] memory tokenAmounts, bytes memory)
        internal
        override
        returns (uint256[] memory actualTokenAmounts)
    {
        actualTokenAmounts = new uint256[](1);
        actualTokenAmounts[0] = tokenAmounts[0];
        _updateMargin(tokenAmounts[0].toInt256());

        uint256 notionalLiquidityToMint = tokenAmounts[0].mul(_leverageWad);
        _updateLiquidity(notionalLiquidityToMint.toInt256());

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
    /// @param marginDelta Change in the margin account of the position
    function _updateMargin(int256 marginDelta) internal {
        if (marginDelta == 0) {
            return;
        }

        if (marginDelta > 0) {
            IERC20(_vaultTokens[0]).safeIncreaseAllowance(address(_periphery), marginDelta.toUint256());
        }

        _periphery.updatePositionMargin(
            _marginEngine,
            trackedPositions[_currentPositionIndex].tickLower,
            trackedPositions[_currentPositionIndex].tickUpper,
            marginDelta,
            false
        );

        if (marginDelta > 0) {
            IERC20(_vaultTokens[0]).safeApprove(address(_periphery), 0);
        }
    }

    /// @notice Updates the liquidity of the currently active LP position
    /// @param liquidityDelta The change in pool liquidity as a result of the position update
    function _updateLiquidity(int256 liquidityDelta) internal {
        if (liquidityDelta != 0) {
            _periphery.mintOrBurn(
                IPeriphery.MintOrBurnParams({
                    marginEngine: _marginEngine,
                    tickLower: trackedPositions[_currentPositionIndex].tickLower,
                    tickUpper: trackedPositions[_currentPositionIndex].tickUpper,
                    notional: (liquidityDelta < 0) ? (-liquidityDelta).toUint256() : liquidityDelta.toUint256(),
                    isMint: (liquidityDelta >= 0),
                    marginDelta: 0
                })
            );
            _currentPositionLiquidity = (_currentPositionLiquidity.toInt256() + liquidityDelta).toUint256();
        }
    }

    /// @notice Updates the currently active LP position of the Vault
    /// @dev The function adds the new position to the trackedPositions
    /// @dev array (if not present already), and updates the currentPositionIndex,
    /// @dev mapping and aggregated variables accordingly.
    /// @param position The new current position of the Vault
    function _updateCurrentPosition(TickRange memory position) internal {
        require(Time.blockTimestampScaled() <= _termEndTimestampWad, ExceptionsLibrary.FORBIDDEN);

        Tick.checkTicks(position.tickLower, position.tickUpper);
        require(position.tickLower % _tickSpacing == 0, ExceptionsLibrary.INVALID_VALUE);
        require(position.tickUpper % _tickSpacing == 0, ExceptionsLibrary.INVALID_VALUE);

        bytes memory encodedPosition = abi.encode(position);
        if (positionToIndexPlusOne[encodedPosition] == 0) {
            trackedPositions.push(position);
            _currentPositionIndex = trackedPositions.length - 1;
            positionToIndexPlusOne[encodedPosition] = trackedPositions.length;
        } else {
            // we rebalance to some previous position
            // so we need to update the aggregate variables
            _currentPositionIndex = positionToIndexPlusOne[encodedPosition] - 1;
            Position.Info memory currentPositionInfo_ = _voltzHelper.getVaultPosition(
                trackedPositions[_currentPositionIndex]
            );
            _aggregatedInactiveFixedTokenBalance -= currentPositionInfo_.fixedTokenBalance;
            _aggregatedInactiveVariableTokenBalance -= currentPositionInfo_.variableTokenBalance;
            _aggregatedInactiveMargin -= currentPositionInfo_.margin;
        }

        _currentPositionLiquidity = 0;
    }

    /// @notice Unwinds the currently active position and withdraws the maximum amount of funds possible
    /// @dev The function unwinds the currently active position and proceeds as follows:
    /// @dev 1. if variableTokenBalance != 0, withdraw all funds up to marginMultiplierPostUnwind * positionMarginRequirementInitial
    /// @dev 2. otherwise, if fixedTokenBalance > 0, withdraw everything
    /// @dev 3. otherwise, if fixedTokenBalance <= 0, withdraw everything up to positionMarginRequirementInitial
    /// @dev The unwound position is tracked only in cases 1 and 2
    /// @return marginLeftInOldPosition The margin left in the unwound position
    function _unwindAndExitCurrentPosition() internal returns (int256 marginLeftInOldPosition) {
        Position.Info memory currentPositionInfo_ = _voltzHelper.getVaultPosition(
            trackedPositions[_currentPositionIndex]
        );

        if (currentPositionInfo_.variableTokenBalance != 0) {
            bool _isFT = currentPositionInfo_.variableTokenBalance < 0;

            IVAMM.SwapParams memory _params = IVAMM.SwapParams({
                recipient: address(this),
                amountSpecified: currentPositionInfo_.variableTokenBalance,
                sqrtPriceLimitX96: _isFT ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1,
                tickLower: trackedPositions[_currentPositionIndex].tickLower,
                tickUpper: trackedPositions[_currentPositionIndex].tickUpper
            });

            (int256 _fixedTokenDelta, int256 _variableTokenDelta, uint256 _cumulativeFeeIncurred, , ) = _vamm.swap(
                _params
            );

            currentPositionInfo_.fixedTokenBalance += _fixedTokenDelta;
            currentPositionInfo_.variableTokenBalance += _variableTokenDelta;
            currentPositionInfo_.margin -= _cumulativeFeeIncurred.toInt256();
        }

        bool trackPosition;
        uint256 marginToKeep;
        (trackPosition, marginToKeep) = _voltzHelper.getMarginToKeep(currentPositionInfo_);

        if (currentPositionInfo_.margin > 0) {
            if (marginToKeep > currentPositionInfo_.margin.toUint256()) {
                marginToKeep = currentPositionInfo_.margin.toUint256();
            }

            _updateMargin(-(currentPositionInfo_.margin - marginToKeep.toInt256()));
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
        require(Time.blockTimestampScaled() <= _termEndTimestampWad, ExceptionsLibrary.FORBIDDEN);

        positionToIndexPlusOne[abi.encode(trackedPositions[positionIndex])] = 0;
        if (positionIndex != trackedPositions.length - 1) {
            delete trackedPositions[positionIndex];
            trackedPositions[positionIndex] = trackedPositions[trackedPositions.length - 1];
            positionToIndexPlusOne[abi.encode(trackedPositions[positionIndex])] = positionIndex + 1;
        }

        trackedPositions.pop();
    }
}
