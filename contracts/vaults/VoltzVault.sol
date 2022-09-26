// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.9;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../libraries/ExceptionsLibrary.sol";
import "./IntegrationVault.sol";
import "../interfaces/vaults/IVoltzVaultGovernance.sol";
import "../interfaces/vaults/IVoltzVault.sol";
import "../interfaces/external/voltz/utils/SqrtPriceMath.sol";
import "../interfaces/external/voltz/IPeriphery.sol";
import "../interfaces/external/voltz/utils/Time.sol";
import "../interfaces/external/voltz/utils/TickMath.sol";

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import "hardhat/console.sol";

/// @notice Vault that interfaces Voltz protocol in the integration layer.
contract VoltzVault is IVoltzVault, IntegrationVault {
    using SafeERC20 for IERC20;
    using SafeCastUni for uint128;
    using SafeCastUni for int128;
    using SafeCastUni for uint256;
    using SafeCastUni for int256;
    using PRBMathSD59x18 for int256;
    using PRBMathUD60x18 for uint256;

    IMarginEngine public _marginEngine;
    IRateOracle public _rateOracle;
    int24 _tickSpacing;
    uint256 _leverage;
    uint256 _k;
    uint256 _lookbackWindowInSeconds;
    uint256 _historicalAPYDeltaPercentageWad;

    /// tvl needs to be updated before use
    int256 _minTVL;
    int256 _maxTVL;
    uint256 _lastTvlUpdateTimestamp;

    TickRange _currentPosition;
    uint256 _currentPositionLiquidity;
    TickRange[] trackedPositions;

    uint256 public constant SECONDS_IN_YEAR_IN_WAD = 31536000e18;
    uint256 public constant ONE_HUNDRED_IN_WAD = 100e18;

    // -------------------  EXTERNAL, VIEW  -------------------

    /// @inheritdoc IVault
    function tvl() public view returns (uint256[] memory minTokenAmounts, uint256[] memory maxTokenAmounts) {
        minTokenAmounts = new uint256[](1);
        maxTokenAmounts = new uint256[](1);

        if (_minTVL > 0) {
            minTokenAmounts[0] = _minTVL.toUint256();
        }

        if (_maxTVL > 0) {
            maxTokenAmounts[0] = _maxTVL.toUint256();
        }
    }

    /// @inheritdoc IntegrationVault
    function supportsInterface(bytes4 interfaceId) public view override(IERC165, IntegrationVault) returns (bool) {
        return super.supportsInterface(interfaceId) || (interfaceId == type(IVoltzVault).interfaceId);
    }

    function periphery() public view returns (IPeriphery) {
        return IVoltzVaultGovernance(address(_vaultGovernance)).delayedProtocolParams().periphery;
    }

    /// @inheritdoc IVoltzVault
    function marginEngine() external view override returns (IMarginEngine) {
        return _marginEngine;
    }

    /// @inheritdoc IVoltzVault
    function vamm() external view override returns (IVAMM) {
        return _marginEngine.vamm();
    }

    /// @inheritdoc IVoltzVault
    function rateOracle() external view override returns (IRateOracle) {
        return _rateOracle;
    }

    function currentPosition() external view returns (TickRange memory) {
        return _currentPosition;
    }

    // -------------------  EXTERNAL, MUTATING  -------------------
    function rebalance(TickRange memory ticks) external override {
        // burn liquidity first, then unwind and exit existing position
        // this makes sure that we do not use our own liquidity to unwind ourselves
        _updateLiquidity(-_currentPositionLiquidity.toInt256());
        _unwindAndExitCurrentPosition();
        TickRange memory oldPosition = _currentPosition;

        _updateCurrentPosition(ticks);
        uint256 vaultBalance = IERC20(_vaultTokens[0]).balanceOf(address(this));
        _updateMargin(vaultBalance.toInt256());
        _updateLiquidity((vaultBalance * _k).toInt256());

        emit PositionRebalance(
            oldPosition,
            _currentPosition
        );
    }

    /// @inheritdoc IVoltzVault
    function initialize(
        uint256 nft_,
        address[] memory vaultTokens_,
        address marginEngine_,
        int24 initialTickLower,
        int24 initialTickUpper
    ) external {
        require(vaultTokens_.length == 1, ExceptionsLibrary.INVALID_VALUE);

        _marginEngine = IMarginEngine(marginEngine_);
        _rateOracle = _marginEngine.rateOracle();

        address underlyingToken = address(_marginEngine.underlyingToken());
        require(vaultTokens_[0] == underlyingToken, ExceptionsLibrary.INVALID_VALUE);

        _initialize(vaultTokens_, nft_);

        IVAMM vamm_ = _marginEngine.vamm();
        _tickSpacing = vamm_.tickSpacing();
        _leverage = 10;
        _k = 2;
        _lookbackWindowInSeconds = 1209600;
        _historicalAPYDeltaPercentageWad = 0;

        _updateCurrentPosition(TickRange(initialTickLower, initialTickUpper));

        emit VaultInitialized(
            marginEngine_,
            initialTickLower,
            initialTickUpper
        );
    }

    function updateTvl() external {
        uint256 timeInSecondsWad;

        uint256 termStartTimestampWad = _marginEngine.termStartTimestampWad();
        uint256 termEndTimestampWad = _marginEngine.termEndTimestampWad();
        uint256 termCurrentTimestampWad = Time.blockTimestampScaled();

        // Calculcate fixed factor
        timeInSecondsWad = termEndTimestampWad - termStartTimestampWad;
        uint256 fixedFactorValueWad = _accrualFact(timeInSecondsWad).div(ONE_HUNDRED_IN_WAD);

        // Calculate estimated variable factor between start and end
        uint256 variableFactorStartCurrentWad = _rateOracle.variableFactorNoCache(
            termStartTimestampWad, 
            termCurrentTimestampWad
        );
        uint256 lookbackWindowInSecondsWad = _lookbackWindowInSeconds.fromUint();
        uint256 historicalAPYWad = _rateOracle.getApyFromTo(
            (termCurrentTimestampWad - lookbackWindowInSecondsWad).toUint(), 
            termCurrentTimestampWad.toUint()
        );
        timeInSecondsWad = termEndTimestampWad - termCurrentTimestampWad;
        uint256 estimatedVariableFactorCurrentEndWad = historicalAPYWad.mul(_accrualFact(timeInSecondsWad));
        uint256 estimatedVariableFactorStartEndLowerWad = 
            variableFactorStartCurrentWad + 
                estimatedVariableFactorCurrentEndWad.mul(
                    PRBMathUD60x18.fromUint(1) - _historicalAPYDeltaPercentageWad
                );
        uint256 estimatedVariableFactorStartEndUpperWad = 
            variableFactorStartCurrentWad + 
                estimatedVariableFactorCurrentEndWad.mul(
                    PRBMathUD60x18.fromUint(1) + _historicalAPYDeltaPercentageWad
                );

        // Aggregate estimated settlement cashflows into TVL
        _minTVL = _estimateSettlementCashflow(
            _currentPosition,
            fixedFactorValueWad,
            estimatedVariableFactorStartEndLowerWad
        );
        _maxTVL = _estimateSettlementCashflow(
            _currentPosition,
            fixedFactorValueWad,
            estimatedVariableFactorStartEndUpperWad
        );
        
        for (uint256 i = 0; i < trackedPositions.length; i++) {
            _minTVL += _estimateSettlementCashflow(
                trackedPositions[i],
                fixedFactorValueWad,
                estimatedVariableFactorStartEndLowerWad
            );

            _maxTVL += _estimateSettlementCashflow(
                trackedPositions[i],
                fixedFactorValueWad,
                estimatedVariableFactorStartEndUpperWad
            );
        }

        _lastTvlUpdateTimestamp = block.timestamp;

        emit TvlUpdate(
            _minTVL,
            _maxTVL,
            _lastTvlUpdateTimestamp
        );
    }

    // -------------------  INTERNAL, VIEW  -------------------

    function _isStrategy(address addr) internal view returns (bool) {
        return _vaultGovernance.internalParams().registry.getApproved(_nft) == addr;
    }

    function _isReclaimForbidden(address) internal pure override returns (bool) {
        return false;
    }

    function _estimateSettlementCashflow(
        TickRange memory position,
        uint256 fixedFactorValueWad,
        uint256 estimatedVariableFactorStartEndWad
    ) internal returns (int256) {
        Position.Info memory positionInfo = _marginEngine.getPosition(
            address(this),
            position.tickLower,
            position.tickUpper
        );

        // Fixed Cashflow
        int256 fixedTokenBalanceWad = positionInfo.fixedTokenBalance.fromInt();
        int256 fixedCashflowBalanceWad = fixedTokenBalanceWad.mul(int256(fixedFactorValueWad));
        int256 fixedCashflowBalance = fixedCashflowBalanceWad.toInt();
 
        // Variable Cashflow
        int256 variableTokenBalanceWad = positionInfo.variableTokenBalance.fromInt();
        int256 variableCashflowBalanceWad = variableTokenBalanceWad.mul(int256(estimatedVariableFactorStartEndWad));
        int256 variableCashflowBalance = variableCashflowBalanceWad.toInt();

        return fixedCashflowBalance + variableCashflowBalance + positionInfo.margin;
    }

    // -------------------  INTERNAL, MUTATING  -------------------

    function _push(uint256[] memory tokenAmounts, bytes memory options)
        internal
        override
        returns (uint256[] memory actualTokenAmounts)
    {
        actualTokenAmounts = new uint256[](1);
        actualTokenAmounts[0] = tokenAmounts[0];
        _updateMargin(tokenAmounts[0].toInt256());
        _updateLiquidity(tokenAmounts[0].toInt256() * _leverage.toInt256());

        emit PushDeposit(
            tokenAmounts[0],
            tokenAmounts[0] * _leverage
        );
    }

    function _pull(
        address to,
        uint256[] memory tokenAmounts,
        bytes memory options
    ) internal override returns (uint256[] memory actualTokenAmounts) {
        actualTokenAmounts = new uint256[](1);
        uint256 termEndTimestampWad = _marginEngine.termEndTimestampWad();
         if (termEndTimestampWad > Time.blockTimestampScaled()) {
            return actualTokenAmounts;
        }

        IPeriphery periphery = periphery();
        periphery.settlePositionAndWithdrawMargin(
            _marginEngine, 
            address(this), 
            _currentPosition.tickLower, 
            _currentPosition.tickUpper
        );

        for (uint256 i = 0; i < trackedPositions.length; i++) {
            periphery.settlePositionAndWithdrawMargin(
                _marginEngine, 
                address(this), 
                trackedPositions[i].tickLower, 
                trackedPositions[i].tickUpper
            );
        }

        uint256 vaultBalance = IERC20(_vaultTokens[0]).balanceOf(address(this));

        uint256 amountToWithdraw = tokenAmounts[0];
        if (vaultBalance < amountToWithdraw) {
            amountToWithdraw = vaultBalance;
        }

        IERC20(_vaultTokens[0]).safeTransfer(to, amountToWithdraw);
        actualTokenAmounts[0] = amountToWithdraw;

        emit PullWithdraw(
            tokenAmounts[0],
            actualTokenAmounts[0]
        );
    }

    function _updateMargin(int256 marginDelta) internal {
        if (marginDelta == 0) {
            return;
        }

        IPeriphery periphery = periphery();

        if (marginDelta > 0) {
            IERC20(_vaultTokens[0]).safeIncreaseAllowance(address(periphery), marginDelta.toUint256());
        }

        periphery.updatePositionMargin(
            _marginEngine,
            _currentPosition.tickLower,
            _currentPosition.tickUpper,
            marginDelta,
            false
        );

        if (marginDelta > 0) {
            IERC20(_vaultTokens[0]).safeApprove(address(periphery), 0);
        }
    }

    function _updateLiquidity(int256 liquidityDelta) internal {
         IPeriphery periphery = periphery();
        if (liquidityDelta != 0) {
            IPeriphery.MintOrBurnParams memory params;
            // burn liquidity
            if (liquidityDelta < 0) {
                params = IPeriphery.MintOrBurnParams({
                    marginEngine: _marginEngine, 
                    tickLower: _currentPosition.tickLower, 
                    tickUpper: _currentPosition.tickUpper, 
                    notional: (-liquidityDelta).toUint256(),
                    isMint: false,
                    marginDelta: 0
                }); 
            }
            // mint liquidity
            else {
                params = IPeriphery.MintOrBurnParams({
                    marginEngine: _marginEngine, 
                    tickLower: _currentPosition.tickLower, 
                    tickUpper: _currentPosition.tickUpper, 
                    notional: liquidityDelta.toUint256(),
                    isMint: true,
                    marginDelta: 0
                });
            }

            periphery.mintOrBurn(params);
            _currentPositionLiquidity = (_currentPositionLiquidity.toInt256() + liquidityDelta).toUint256();
        }
    }

    function _updateCurrentPosition(TickRange memory ticks) internal {
        Tick.checkTicks(ticks.tickLower, ticks.tickUpper);
        require(ticks.tickLower % _tickSpacing == 0, ExceptionsLibrary.INVALID_VALUE);
        require(ticks.tickUpper % _tickSpacing == 0, ExceptionsLibrary.INVALID_VALUE);

        _currentPosition = ticks;
    }

    /// @notice Divide a given time in seconds by the number of seconds in a year
    /// @param timeInSecondsAsWad A time in seconds in Wad (i.e. scaled up by 10^18)
    /// @return timeInYearsWad An annualised factor of timeInSeconds, also in Wad
    function _accrualFact(uint256 timeInSecondsAsWad)
        internal
        pure
        returns (uint256 timeInYearsWad)
    {
        timeInYearsWad = timeInSecondsAsWad.div(SECONDS_IN_YEAR_IN_WAD);
    }
    
    function _unwindAndExitCurrentPosition() internal {
        Position.Info memory _currentPositionInfo = _marginEngine.getPosition(
            address(this),
            _currentPosition.tickLower,
            _currentPosition.tickUpper
        );

        if (_currentPositionInfo.variableTokenBalance != 0) {
            bool _isFT = _currentPositionInfo.variableTokenBalance < 0;

            IVAMM.SwapParams memory _params = IVAMM.SwapParams({
                recipient: address(this),
                amountSpecified: _currentPositionInfo.variableTokenBalance,
                sqrtPriceLimitX96: _isFT
                    ? TickMath.MIN_SQRT_RATIO + 1
                    : TickMath.MAX_SQRT_RATIO - 1,
                tickLower: _currentPosition.tickLower,
                tickUpper: _currentPosition.tickUpper
            });

            IVAMM _vamm = _marginEngine.vamm();

            _vamm.swap(_params);
        } 

        _currentPositionInfo = _marginEngine.getPosition(
            address(this),
            _currentPosition.tickLower,
            _currentPosition.tickUpper
        );

        uint256 positionMarginRequirementInitial = _marginEngine.getPositionMarginRequirement(
            address(this),
            _currentPosition.tickLower,
            _currentPosition.tickUpper,
            false
        );

        int256 marginToWithdraw;
        if (_currentPositionInfo.variableTokenBalance != 0) {
            // keep k * initial margin requirement, withdraw the rest
            // need to track to redeem the rest at maturity
            marginToWithdraw = _currentPositionInfo.margin - (_k * positionMarginRequirementInitial).toInt256();
            trackedPositions.push(_currentPosition);
        } else if (_currentPositionInfo.fixedTokenBalance > 0) {
            // withdraw all margin
            // need to track to redeem ft cashflow at maturity
            marginToWithdraw = _currentPositionInfo.margin;
            trackedPositions.push(_currentPosition);
        } else if (_currentPositionInfo.fixedTokenBalance < 0) {
            // withdraw everything up to amount that covers negative ft
            // no need to track for later settlement
            // int256 fixedTokenBalanceWad = _currentPositionInfo.fixedTokenBalance.fromInt();
            // uint256 timeInSecondsWad = _marginEngine.termEndTimestampWad() - _marginEngine.termStartTimestampWad();
            // uint256 fixedFactorValueWad = _accrualFact(timeInSecondsWad).div(ONE_HUNDRED_IN_WAD);

            // fixed cashflow is negative
            // int256 fixedCashflowBalanceWad = fixedTokenBalanceWad.mul(int256(fixedFactorValueWad));
            // int256 fixedCashflowBalance = fixedCashflowBalanceWad.toInt();

            // marginToWithdraw = _currentPositionInfo.margin + fixedCashflowBalance;

            // since vt = 0, margin requirement initial is equal to fixed cashflow
            marginToWithdraw = _currentPositionInfo.margin - positionMarginRequirementInitial.toInt256() - 1;
        }

        if (_currentPositionInfo.margin - marginToWithdraw <= positionMarginRequirementInitial.toInt256()) {
            marginToWithdraw = _currentPositionInfo.margin - positionMarginRequirementInitial.toInt256() - 1;
        }

        if (marginToWithdraw > _currentPositionInfo.margin) {
            marginToWithdraw = _currentPositionInfo.margin;
        }

        if (marginToWithdraw > 0) {
            _updateMargin(-marginToWithdraw);
        }
    }
}
