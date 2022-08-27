// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.9;

import "../interfaces/external/perp/IPerpInternalVault.sol";
import "../interfaces/external/perp/IClearingHouse.sol";
import "../interfaces/external/perp/IBaseToken.sol";
import "../interfaces/external/perp/IIndexPrice.sol";
import "../interfaces/external/perp/IClearingHouseConfig.sol";
import "../interfaces/external/perp/IMarketRegistry.sol";
import "../interfaces/external/perp/IAccountBalance.sol";
import "./IntegrationVault.sol";
import "../interfaces/vaults/IPerpFuturesVault.sol";
import "../libraries/ExceptionsLibrary.sol";
import "../libraries/external/FullMath.sol";
import "../libraries/CommonLibrary.sol";
import "../interfaces/external/univ3/IUniswapV3Pool.sol";
import "../interfaces/vaults/IPerpVaultGovernance.sol";
import "hardhat/console.sol";

// FUTURE: CHECK SECURITY & SLIPPAGE EVERYWHERE
// check liquidation scenario
contract PerpFuturesVault is IPerpFuturesVault, IntegrationVault {
    using SafeERC20 for IERC20;

    /// @inheritdoc IPerpFuturesVault
    address public baseToken;
    /// @inheritdoc IPerpFuturesVault
    IPerpInternalVault public vault;
    /// @inheritdoc IPerpFuturesVault
    IClearingHouse public clearingHouse;
    /// @inheritdoc IPerpFuturesVault
    IAccountBalance public accountBalance;
    IMarketRegistry public marketRegistry;

    uint256 public constant DENOMINATOR = 10**9;
    uint256 public constant DECIMALS_DIFFERENCE = 10**12;
    uint256 public constant Q96 = 2**96;

    /// @notice leverageMultiplierD The vault capital leverage multiplier (multiplied by DENOMINATOR). Your real capital is C and your virtual capital is C * leverageMultiplier (a user will be trading the virtual asset)
    uint256 public leverageMultiplierD; // leverage using by usd
    /// @notice Returns true if the user`s base token position is a long one, else - false
    bool isLongBaseToken; // true if we long base token, false else
    /// @inheritdoc IPerpFuturesVault
    address public usdc;

    // -------------------  EXTERNAL, VIEW  -------------------

    /// @inheritdoc IVault
    function tvl() public view returns (uint256[] memory minTokenAmounts, uint256[] memory maxTokenAmounts) {
        uint256 usdValue = _getAccountValue();
        int256 deltaBetweenSpotAndOracleTvls = _deltaBetweenSpotAndOracleTvl();

        minTokenAmounts = new uint256[](1);
        maxTokenAmounts = new uint256[](1);

        if (deltaBetweenSpotAndOracleTvls > 0) {
            minTokenAmounts[0] = usdValue;
            maxTokenAmounts[0] = usdValue + uint256(deltaBetweenSpotAndOracleTvls);
        } else {
            if (uint256(-deltaBetweenSpotAndOracleTvls) <= usdValue) {
                minTokenAmounts[0] = usdValue - uint256(-deltaBetweenSpotAndOracleTvls);
            }
            maxTokenAmounts[0] = usdValue;
        }

        minTokenAmounts[0] = minTokenAmounts[0] / DECIMALS_DIFFERENCE;
        maxTokenAmounts[0] = maxTokenAmounts[0] / DECIMALS_DIFFERENCE;
    }

    /// @inheritdoc IPerpFuturesVault
    function getPositionSize() public view returns (int256) {
        return accountBalance.getTotalPositionSize(address(this), baseToken);
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public view override(IERC165, IntegrationVault) returns (bool) {
        return super.supportsInterface(interfaceId) || (interfaceId == type(IPerpFuturesVault).interfaceId);
    }

    // -------------------  EXTERNAL, MUTATING  -------------------

    /// @inheritdoc IPerpFuturesVault
    function initialize(
        uint256 nft_,
        address baseToken_,
        uint256 leverageMultiplierD_,
        bool isLongBaseToken_
    ) external {
        require(IBaseToken(baseToken_).isOpen(), ExceptionsLibrary.INVALID_TOKEN);
        IPerpVaultGovernance.DelayedProtocolParams memory params = IPerpVaultGovernance(address(msg.sender))
            .delayedProtocolParams();
        uint256 maxProtocolLeverage = params.maxProtocolLeverage;
        require(leverageMultiplierD_ <= DENOMINATOR * (maxProtocolLeverage - 1), ExceptionsLibrary.INVALID_VALUE); // leverage more than 10x isn't available on Perp (exactly 10x may be subject to precision failures)

        leverageMultiplierD = leverageMultiplierD_;
        isLongBaseToken = isLongBaseToken_;
        address[] memory vaultTokens_ = new address[](1);
        vaultTokens_[0] = params.usdcAddress;
        _initialize(vaultTokens_, nft_);

        vault = params.vault;
        marketRegistry = params.marketRegistry;

        clearingHouse = IClearingHouse(vault.getClearingHouse());
        accountBalance = IAccountBalance(vault.getAccountBalance());

        usdc = params.usdcAddress;
        baseToken = baseToken_;
    }

    /// @inheritdoc IPerpFuturesVault
    function updateLeverage(
        uint256 newLeverageMultiplierD_,
        bool isLongBaseToken_,
        uint256 deadline,
        uint256 oppositeAmountBound
    ) external {
        require(_isApprovedOrOwner(msg.sender));

        IPerpVaultGovernance.DelayedProtocolParams memory params = IPerpVaultGovernance(address(_vaultGovernance))
            .delayedProtocolParams();
        uint256 maxProtocolLeverage = params.maxProtocolLeverage;
        require(newLeverageMultiplierD_ <= DENOMINATOR * (maxProtocolLeverage - 1), ExceptionsLibrary.INVALID_VALUE);

        leverageMultiplierD = newLeverageMultiplierD_;
        isLongBaseToken = isLongBaseToken_;

        uint256 vaultCapital = _getAccountValue();
        uint256 capitalToUse = FullMath.mulDiv(vaultCapital, leverageMultiplierD, DENOMINATOR);

        _adjustPosition(capitalToUse, deadline, oppositeAmountBound);
        emit UpdatedLeverage(tx.origin, msg.sender, newLeverageMultiplierD_, isLongBaseToken_);
    }

    /// @inheritdoc IPerpFuturesVault
    function adjustPosition(uint256 deadline, uint256 oppositeAmountBound) external {
        require(_isApprovedOrOwner(msg.sender));

        uint256 vaultCapital = _getAccountValue();
        uint256 capitalToUse = FullMath.mulDiv(vaultCapital, leverageMultiplierD, DENOMINATOR);

        _adjustPosition(capitalToUse, deadline, oppositeAmountBound);
        emit AdjustedPosition(tx.origin, msg.sender);
    }

    /// @inheritdoc IPerpFuturesVault
    function closePosition(uint256 deadline, uint256 oppositeAmountBound) external {
        require(_isApprovedOrOwner(msg.sender));

        int256 positionValueUSD = accountBalance.getTotalPositionValue(address(this), baseToken);
        if (positionValueUSD == 0) {
            return;
        }
        clearingHouse.closePosition(
            IClearingHouse.ClosePositionParams({
                baseToken: baseToken,
                sqrtPriceLimitX96: 0,
                oppositeAmountBound: oppositeAmountBound,
                deadline: deadline,
                referralCode: 0
            })
        );
        emit ClosedPosition(tx.origin, msg.sender);
    }

    // -------------------  INTERNAL, MUTATING  -------------------

    /// @notice Push token amounts to the vault
    /// @param tokenAmounts Token amounts (nominated in USDC weis)
    /// @param options Encoded options for the vault
    /// @return actualTokenAmounts Actual pushed token amounts (nominated in USDC weis)
    function _push(uint256[] memory tokenAmounts, bytes memory options)
        internal
        override
        returns (uint256[] memory actualTokenAmounts)
    {
        require(tokenAmounts.length == 1, ExceptionsLibrary.INVALID_LENGTH);

        uint256 usdcAmount = tokenAmounts[0];
        if (usdcAmount == 0) {
            return new uint256[](1);
        }

        IERC20(usdc).safeIncreaseAllowance(address(vault), usdcAmount);
        vault.deposit(usdc, usdcAmount);
        IERC20(usdc).safeApprove(address(vault), 0);

        actualTokenAmounts = new uint256[](1);
        actualTokenAmounts[0] = usdcAmount;

        Options memory opts = _parseOptions(options);

        uint256 vaultCapital = _getAccountValue();
        uint256 capitalToUse = FullMath.mulDiv(vaultCapital, leverageMultiplierD, DENOMINATOR);

        _adjustPosition(capitalToUse, opts.deadline, opts.oppositeAmountBound);
    }

    /// @notice Pulls token amounts from the vault
    /// @param to Recepient address
    /// @param tokenAmounts Token amounts (nominated in USDC weis)
    /// @param options Encoded options for the vault
    /// @return actualTokenAmounts Actual pulled token amounts (nominated in USDC weis)
    function _pull(
        address to,
        uint256[] memory tokenAmounts,
        bytes memory options
    ) internal override returns (uint256[] memory actualTokenAmounts) {
        require(tokenAmounts.length == 1, ExceptionsLibrary.INVALID_LENGTH);

        uint256 usdcAmount = tokenAmounts[0];
        if (usdcAmount == 0) {
            return new uint256[](1);
        }
        uint256 vaultCapital = _getAccountValue();

        uint256 futureCapital = 0;
        if (usdcAmount * DECIMALS_DIFFERENCE < vaultCapital) {
            futureCapital = vaultCapital - usdcAmount * DECIMALS_DIFFERENCE;
        }

        uint256 capitalToUse = FullMath.mulDiv(futureCapital, leverageMultiplierD, DENOMINATOR);

        Options memory opts = _parseOptions(options);
        _adjustPosition(capitalToUse, opts.deadline, opts.oppositeAmountBound);

        uint256 freeCollateral = vault.getFreeCollateral(address(this));
        if (usdcAmount > freeCollateral) {
            usdcAmount = freeCollateral;
        }

        vault.withdraw(usdc, usdcAmount);

        IERC20(usdc).safeTransfer(to, usdcAmount);
        actualTokenAmounts = new uint256[](1);
        actualTokenAmounts[0] = usdcAmount;
    }

    /// @notice Adjusts the current position to the capitalToUse by making comparison with the takerPositionSize
    /// @param capitalToUse The new position capital to be used after adjustment (nominated in USDC weis)
    /// @param deadline The restriction on when the transaction should be executed, otherwise, it fails
    function _adjustPosition(
        uint256 capitalToUse,
        uint256 deadline,
        uint256 oppositeAmountBound
    ) internal {
        int256 positionValueUSD = accountBalance.getTotalPositionValue(address(this), baseToken);
        if (isLongBaseToken) {
            if (int256(capitalToUse) > positionValueUSD) {
                _makeAdjustment(true, uint256(int256(capitalToUse) - positionValueUSD), deadline, oppositeAmountBound);
            } else {
                _makeAdjustment(false, uint256(positionValueUSD - int256(capitalToUse)), deadline, oppositeAmountBound);
            }
        } else {
            if (-int256(capitalToUse) < positionValueUSD) {
                _makeAdjustment(false, uint256(positionValueUSD + int256(capitalToUse)), deadline, oppositeAmountBound);
            } else {
                _makeAdjustment(true, uint256(-positionValueUSD - int256(capitalToUse)), deadline, oppositeAmountBound);
            }
        }
    }

    /// @notice Makes the actual position capital adjustment by "longing" / "shorting" the baseToken
    /// @dev The call to ClearingHouse is performed only if the amount is not zero
    /// @param longBaseTokenInAdjustment True if "longing" the base token, if "shorting" - false
    /// @param amount The amount of token to push into the position
    /// @param deadline The restriction on when the transaction should be executed, otherwise, it fails
    function _makeAdjustment(
        bool longBaseTokenInAdjustment,
        uint256 amount,
        uint256 deadline,
        uint256 oppositeAmountBound
    ) internal {
        if (amount == 0) {
            return;
        }
        (uint256 deltaBase, ) = clearingHouse.openPosition(
            IClearingHouse.OpenPositionParams({
                baseToken: baseToken,
                isBaseToQuote: !longBaseTokenInAdjustment,
                isExactInput: longBaseTokenInAdjustment,
                amount: amount,
                oppositeAmountBound: oppositeAmountBound,
                deadline: deadline,
                sqrtPriceLimitX96: 0,
                referralCode: 0
            })
        );

        emit TradePassed(tx.origin, msg.sender, deltaBase);
    }

    /// @notice A helper function which parses an encoded instance of Options struct or any other byes array
    /// @param options Bytes array of the encoded options
    /// @return Options memory Options struct
    function _parseOptions(bytes memory options) internal view returns (Options memory) {
        if (options.length == 0) return Options({deadline: block.timestamp + 600, oppositeAmountBound: 0});

        require(options.length == 64, ExceptionsLibrary.INVALID_VALUE);
        return abi.decode(options, (Options));
    }

    function _isReclaimForbidden(address addr) internal view override returns (bool) {
        if (addr == usdc) {
            return true;
        }
        return false;
    }

    function _deltaBetweenSpotAndOracleTvl() internal view returns (int256 delta) {
        int256 positionSize = accountBalance.getTotalPositionSize(address(this), baseToken);
        uint256 oraclePriceX10_18 = _getOraclePriceX10_18();
        uint256 spotPriceX10_18 = _getSpotPriceX10_18();

        if (oraclePriceX10_18 < spotPriceX10_18) {
            if (positionSize > 0) {
                return
                    int256(
                        FullMath.mulDiv(uint256(positionSize), spotPriceX10_18 - oraclePriceX10_18, CommonLibrary.D18)
                    );
            }
            return
                -int256(
                    FullMath.mulDiv(uint256(-positionSize), spotPriceX10_18 - oraclePriceX10_18, CommonLibrary.D18)
                );
        } else {
            if (positionSize > 0) {
                return
                    -int256(
                        FullMath.mulDiv(uint256(positionSize), oraclePriceX10_18 - spotPriceX10_18, CommonLibrary.D18)
                    );
            }
            return
                int256(FullMath.mulDiv(uint256(-positionSize), oraclePriceX10_18 - spotPriceX10_18, CommonLibrary.D18));
        }
    }

    function _getOraclePriceX10_18() internal view returns (uint256 priceX10_18) {
        return
            IBaseToken(baseToken).isClosed()
                ? IBaseToken(baseToken).getClosedPrice()
                : IIndexPrice(baseToken).getIndexPrice(
                    IClearingHouseConfig(accountBalance.getClearingHouseConfig()).getTwapInterval()
                );
    }

    function _getSpotPriceX10_18() internal view returns (uint256 priceX10_18) {
        IUniswapV3Pool pool = IUniswapV3Pool(marketRegistry.getPool(baseToken));
        (uint160 sqrtPriceX96, , , , , , ) = pool.slot0();
        uint256 priceX96 = FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, CommonLibrary.Q96);
        return FullMath.mulDiv(priceX96, CommonLibrary.D18, CommonLibrary.Q96);
    }

    function _getAccountValue() public view returns (uint256) {
        int256 usdValue = clearingHouse.getAccountValue(address(this));
        if (usdValue < 0) {
            return 0;
        }
        return uint256(usdValue);
    }

    // --------------------------  EVENTS  --------------------------

    /// @notice Emitted when the vault capital leverage multiplier is updated (multiplied by DENOMINATOR)
    /// @param origin Origin of the transaction (tx.origin)
    /// @param sender Sender of the call (msg.sender)
    /// @param newLeverageMultiplierD The new vault capital leverage multiplier (multiplied by DENOMINATOR)
    /// @param isLongBaseToken True if the user`s base token position is a long one, else - false
    event UpdatedLeverage(
        address indexed origin,
        address indexed sender,
        uint256 newLeverageMultiplierD,
        bool isLongBaseToken
    );

    /// @notice Emitted when the current position is closed
    /// @param origin Origin of the transaction (tx.origin)
    /// @param sender Sender of the call (msg.sender)
    event ClosedPosition(address indexed origin, address indexed sender);

    /// @notice Emitted when the current position is closed
    /// @param origin Origin of the transaction (tx.origin)
    /// @param sender Sender of the call (msg.sender)
    /// @param amount Amount of base token come through the trade
    event TradePassed(address indexed origin, address indexed sender, uint256 amount);

    /// @notice Emitted when the current position`s capital is adjusted
    /// @param origin Origin of the transaction (tx.origin)
    /// @param sender Sender of the call (msg.sender)
    event AdjustedPosition(address indexed origin, address indexed sender);
}