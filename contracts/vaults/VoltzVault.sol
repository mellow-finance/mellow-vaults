// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.9;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../libraries/ExceptionsLibrary.sol";
import "./IntegrationVault.sol";
import "../interfaces/vaults/IVoltzVaultGovernance.sol";
import "../interfaces/vaults/IVoltzVault.sol";
import "../interfaces/external/voltz/utils/SqrtPriceMath.sol";
import "../interfaces/external/voltz/IPeriphery.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "hardhat/console.sol";

/// @notice Vault that interfaces Voltz protocol in the integration layer.
contract VoltzVault is IVoltzVault, IntegrationVault {
    using SafeERC20 for IERC20;
    using SafeCastUni for uint128;
    using SafeCastUni for int128;
    using SafeCastUni for uint256;
    using SafeCastUni for int256;

    IMarginEngine public _marginEngine;
    int24 _tickSpacing;

    OpenedPositions _openedPositions;
    TickRange _currentPosition;

    /// tvl needs to be updated before use
    uint256 _tvl;
    uint256 _lastTvlUpdateTimestamp;

    /// total margin of opened positions
    int256 _totalMargin;
    int256 _lastUpdatedCurrentPositionMargin;

    /// if the underlying pool is beyond maturity,
    /// the vault needs to be settled in order to close all positions
    bool _settled;

    // -------------------  EXTERNAL, VIEW  -------------------

    /// @inheritdoc IVault
    function tvl() public view returns (uint256[] memory minTokenAmounts, uint256[] memory maxTokenAmounts) {
        minTokenAmounts = new uint256[](1);
        maxTokenAmounts = new uint256[](1);

        if (_openedPositions.ranges.length == 0) {
            return (minTokenAmounts, maxTokenAmounts);
        }

        minTokenAmounts[0] = maxTokenAmounts[0] = _totalMargin.toUint256();
    }

    /// @inheritdoc IVoltzVault
    function updateTvl() external override {
        _updateCurrentPositionMargin();
        _lastTvlUpdateTimestamp = block.timestamp;
    }

    function _updateCurrentPositionMargin() internal {
        require(_openedPositions.ranges.length > 0, ExceptionsLibrary.FORBIDDEN);

        _totalMargin -= _lastUpdatedCurrentPositionMargin;

        Position.Info memory position = _marginEngine.getPosition(
            address(this),
            _currentPosition.low,
            _currentPosition.high
        );

        _lastUpdatedCurrentPositionMargin = position.margin;
        _totalMargin += _lastUpdatedCurrentPositionMargin;
    }

    function _updatePosition(TickRange memory positionTicks) internal {
        require(!_settled, ExceptionsLibrary.FORBIDDEN);

        Tick.checkTicks(positionTicks.low, positionTicks.high);
        require(positionTicks.low % _tickSpacing == 0, ExceptionsLibrary.INVALID_VALUE);
        require(positionTicks.high % _tickSpacing == 0, ExceptionsLibrary.INVALID_VALUE);

        if (_currentPosition.low == positionTicks.low && _currentPosition.high == positionTicks.high) {
            return;
        }

        {
            Position.Info memory position = _marginEngine.getPosition(
                address(this),
                _currentPosition.low,
                _currentPosition.high
            );
            require(position._liquidity == 0, ExceptionsLibrary.INVALID_VALUE);
        }

        _updateCurrentPositionMargin();

        _currentPosition = positionTicks;

        {
            Position.Info memory position = _marginEngine.getPosition(
                address(this),
                _currentPosition.low,
                _currentPosition.high
            );
            _lastUpdatedCurrentPositionMargin = position.margin;
        }

        if (!_openedPositions.initializedRange[abi.encode(_currentPosition)]) {
            _openedPositions.initializedRange[abi.encode(_currentPosition)] = true;
            _openedPositions.ranges.push(_currentPosition);
        }
    }

    function _settleVault() internal {
        _settled = true;
    }

    function periphery() public view returns (IPeriphery) {
        return IVoltzVaultGovernance(address(_vaultGovernance)).delayedProtocolParams().periphery;
    }

    function _closePositions(uint256 batch) internal {
        require(_settled, ExceptionsLibrary.FORBIDDEN);

        uint256 to = (_openedPositions.closing + batch < _openedPositions.ranges.length)
            ? _openedPositions.closing + batch
            : _openedPositions.ranges.length;

        IPeriphery periphery = periphery();

        for (uint256 i = _openedPositions.closing; i < to; i++) {
            if (
                _currentPosition.low == _openedPositions.ranges[i].low &&
                _currentPosition.high == _openedPositions.ranges[i].high
            ) {
                _updateCurrentPositionMargin();
            }

            periphery.settlePositionAndWithdrawMargin(
                _marginEngine, 
                address(this), 
                _openedPositions.ranges[i].low,
                _openedPositions.ranges[i].high
            );

            if (
                _currentPosition.low == _openedPositions.ranges[i].low &&
                _currentPosition.high == _openedPositions.ranges[i].high
            ) {
                _updateCurrentPositionMargin();
            }
        }
        _openedPositions.closing = to;
    }

    /// @inheritdoc IntegrationVault
    function supportsInterface(bytes4 interfaceId) public view override(IERC165, IntegrationVault) returns (bool) {
        return super.supportsInterface(interfaceId) || (interfaceId == type(IVoltzVault).interfaceId);
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
    function currentPosition() external view override returns (TickRange memory) {
        return _currentPosition;
    }

    /// @inheritdoc IVoltzVault
    function openedPositions() external view returns (TickRange[] memory) {
        return _openedPositions.ranges;
    }

    /// @inheritdoc IVoltzVault
    function numberOpenedPositions() external view returns (uint256) {
        return _openedPositions.ranges.length;
    }

    /// @inheritdoc IVoltzVault
    function closing() external view returns (uint256) {
        return _openedPositions.closing;
    }

    /// @inheritdoc IVoltzVault
    function isRangeInitialized(TickRange memory ticks) external view returns (bool) {
        return _openedPositions.initializedRange[abi.encode(ticks)];
    }

    /// @inheritdoc IVoltzVault
    function liquidityToNotional(uint128 liquidity) public view override returns (uint256 notional) {
        uint160 sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(_currentPosition.low);
        uint160 sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(_currentPosition.high);
        notional = (SqrtPriceMath.getAmount1Delta(sqrtRatioAX96, sqrtRatioBX96, int128(liquidity))).toUint256();
    }

    /// @inheritdoc IVoltzVault
    function notionalToLiquidity(uint256 notional) public view override returns (uint128 liquidity) {
        uint160 sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(_currentPosition.low);
        uint160 sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(_currentPosition.high);
        liquidity = (FullMath.mulDiv(notional, CommonLibrary.Q96, sqrtRatioBX96 - sqrtRatioAX96)).toUint128();
    }

    // -------------------  EXTERNAL, MUTATING  -------------------
    /// @inheritdoc IVoltzVault
    function initialize(
        uint256 nft_,
        address[] memory vaultTokens_,
        address marginEngine_,
        int24 initialTickLow_,
        int24 initialTickHigh_
    ) external {
        console.log("IVoltzVault");
        console.logBytes4(type(IVoltzVault).interfaceId);

        require(vaultTokens_.length == 1, ExceptionsLibrary.INVALID_VALUE);

        _marginEngine = IMarginEngine(marginEngine_);

        address underlyingToken = address(_marginEngine.underlyingToken());
        require(vaultTokens_[0] == underlyingToken, ExceptionsLibrary.INVALID_VALUE);

        _initialize(vaultTokens_, nft_);

        Tick.checkTicks(initialTickLow_, initialTickHigh_);
        IVAMM vamm_ = _marginEngine.vamm();
        _tickSpacing = vamm_.tickSpacing();

        require(initialTickLow_ % _tickSpacing == 0, ExceptionsLibrary.INVALID_VALUE);
        require(initialTickHigh_ % _tickSpacing == 0, ExceptionsLibrary.INVALID_VALUE);

        _currentPosition = TickRange(initialTickLow_, initialTickHigh_);
        _openedPositions.initializedRange[abi.encode(_currentPosition)] = true;
        _openedPositions.ranges.push(_currentPosition);

        _updateCurrentPositionMargin();
    }

    // -------------------  INTERNAL, VIEW  -------------------

    function _parseOptions(bytes memory options) internal pure returns (Options memory) {
        if (options.length == 0) {
            return Options({
                notionalForLiquidity: 0, 
                notionalForTrade: 0, 
                sqrtPriceLimitX96: 0,
                updatePosition: false,
                newTickLow: 0,
                newTickHigh: 0,
                closingPositions: false,
                batchForClosingPositions: 0
            });
        }

        require(options.length == 32 * 8, ExceptionsLibrary.INVALID_VALUE);
        return abi.decode(options, (Options));
    }

    function _isStrategy(address addr) internal view returns (bool) {
        return _vaultGovernance.internalParams().registry.getApproved(_nft) == addr;
    }

    function _isReclaimForbidden(address) internal pure override returns (bool) {
        return false;
    }

    // -------------------  INTERNAL, MUTATING  -------------------

    function _push(uint256[] memory tokenAmounts, bytes memory options)
        internal
        override
        returns (uint256[] memory actualTokenAmounts)
    {
        actualTokenAmounts = new uint256[](1);
        if (_currentPosition.low == 0 && _currentPosition.high == 0) {
            return actualTokenAmounts;
        }

        Options memory opts = _parseOptions(options);
        if (opts.updatePosition) {
            _updatePosition(TickRange(opts.newTickLow, opts.newTickHigh));
        }

        IPeriphery periphery = periphery();

        uint256 margin = tokenAmounts[0];
        if (margin > 0) {
            address token = _vaultTokens[0];
            IERC20(token).safeIncreaseAllowance(address(periphery), margin);

            periphery.updatePositionMargin(
                _marginEngine,
                _currentPosition.low,
                _currentPosition.high,
                margin.toInt256(),
                false
            );
            actualTokenAmounts[0] = margin;

            IERC20(token).safeApprove(address(periphery), 0);
        }

        _performOperations(opts);
        _updateCurrentPositionMargin();
    }

    function _pull(
        address to,
        uint256[] memory tokenAmounts,
        bytes memory options
    ) internal override returns (uint256[] memory actualTokenAmounts) {
        Options memory opts = _parseOptions(options);
        _performOperations(opts);

        if (opts.closingPositions) {
            _settleVault();
            _closePositions(opts.batchForClosingPositions);
        }

        actualTokenAmounts = new uint256[](1);
        address token = _vaultTokens[0];
        uint256 currentBalance = IERC20(token).balanceOf(address(this));

        IPeriphery periphery = periphery();

        if (tokenAmounts[0] > 0) {
            if (currentBalance > tokenAmounts[0] || _settled) {
                if (currentBalance > tokenAmounts[0]) {
                    IERC20(token).safeTransfer(to, tokenAmounts[0]);
                    actualTokenAmounts[0] += tokenAmounts[0];
                } else {
                    IERC20(token).safeTransfer(to, currentBalance);
                    actualTokenAmounts[0] += currentBalance;
                }
            } else {
                IERC20(token).safeTransfer(to, currentBalance);
                tokenAmounts[0] -= currentBalance;
                actualTokenAmounts[0] += currentBalance;
                currentBalance = 0;

                _updateCurrentPositionMargin();

                int256 amountToCover = _marginEngine.getPositionMarginRequirement(
                    address(this),
                    _currentPosition.low,
                    _currentPosition.high,
                    false
                ).toInt256();

                if (_lastUpdatedCurrentPositionMargin > amountToCover) {
                    uint256 maximumWithdrawal = (_lastUpdatedCurrentPositionMargin - amountToCover).toUint256() - 1;

                    if (maximumWithdrawal > tokenAmounts[0]) {
                        periphery.updatePositionMargin(
                            _marginEngine,
                            _currentPosition.low,
                            _currentPosition.high,
                            -tokenAmounts[0].toInt256(),
                            false
                        );
                        IERC20(token).safeTransfer(to, tokenAmounts[0]);
                        actualTokenAmounts[0] += tokenAmounts[0];
                        tokenAmounts[0] = 0;
                    } else {
                        periphery.updatePositionMargin(
                            _marginEngine,
                            _currentPosition.low,
                            _currentPosition.high,
                            -maximumWithdrawal.toInt256(),
                            false
                        );
                        IERC20(token).safeTransfer(to, maximumWithdrawal);
                        actualTokenAmounts[0] += maximumWithdrawal;
                        tokenAmounts[0] -= maximumWithdrawal;
                    }
                }
            }
        }

        _updateCurrentPositionMargin();
    }

    function _performOperations(Options memory opts) internal {
        IPeriphery periphery = periphery();

        if (opts.notionalForLiquidity != 0) {
            // burn liquidity
            if (opts.notionalForLiquidity < 0) {
                IPeriphery.MintOrBurnParams memory params = IPeriphery.MintOrBurnParams({
                    marginEngine: _marginEngine, 
                    tickLower: _currentPosition.low, 
                    tickUpper: _currentPosition.high, 
                    notional: (-opts.notionalForLiquidity).toUint256(),
                    isMint: false,
                    marginDelta: 0
                });

                periphery.mintOrBurn(params);
            }
            // mint liquidity
            else {
                IPeriphery.MintOrBurnParams memory params = IPeriphery.MintOrBurnParams({
                    marginEngine: _marginEngine, 
                    tickLower: _currentPosition.low, 
                    tickUpper: _currentPosition.high, 
                    notional: opts.notionalForLiquidity.toUint256(),
                    isMint: true,
                    marginDelta: 0
                });
                periphery.mintOrBurn(params);
            }
        }

        // trade
        if (opts.notionalForTrade != 0) {
            uint160 sqrtPriceLimitX96 = opts.sqrtPriceLimitX96;
            if (sqrtPriceLimitX96 == 0) {
                if (opts.notionalForTrade < 0) {
                    sqrtPriceLimitX96 = TickMath.MAX_SQRT_RATIO - 1;
                } else {
                    sqrtPriceLimitX96 = TickMath.MIN_SQRT_RATIO + 1;
                }
            }

            IPeriphery.SwapPeripheryParams memory params = IPeriphery.SwapPeripheryParams({
                marginEngine: _marginEngine,
                isFT: (opts.notionalForTrade < 0),
                notional: (opts.notionalForTrade < 0) ? (-opts.notionalForTrade).toUint256() : opts.notionalForTrade.toUint256(),
                sqrtPriceLimitX96: sqrtPriceLimitX96,
                tickLower: _currentPosition.low,
                tickUpper: _currentPosition.high,
                marginDelta: 0
            });

            periphery.swap(params);
        }
    }
}
