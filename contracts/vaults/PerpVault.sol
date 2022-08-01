// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.9;

import "../interfaces/external/perp/IPerpInternalVault.sol";
import "../interfaces/external/perp/IClearingHouse.sol";
import "../interfaces/external/perp/IBaseToken.sol";
import "../interfaces/external/perp/IAccountBalance.sol";
import "./IntegrationVault.sol";
import "../interfaces/vaults/IPerpVault.sol";
import "../libraries/ExceptionsLibrary.sol";
import "../libraries/external/TickMath.sol";
import "../libraries/external/LiquidityAmounts.sol";
import "../libraries/external/FullMath.sol";
import "../interfaces/external/univ3/IUniswapV3Pool.sol";
import "../interfaces/external/univ3/IUniswapV3Factory.sol";
import "../interfaces/vaults/IPerpVaultGovernance.sol";

// FUTURE: CHECK SECURITY & SLIPPAGE EVERYWHERE
// check liquidation scenario
contract PerpVault is IPerpVault, IntegrationVault {
    using SafeERC20 for IERC20;

    address public baseToken;
    IPerpInternalVault public vault;
    IClearingHouse public clearingHouse;
    IUniswapV3Pool public pool;
    IAccountBalance public accountBalance;

    uint256 public constant DENOMINATOR = 10**9;
    uint256 public constant Q96 = 2**96;

    bool public isPositionOpened;
    uint256 public leverageMultiplierD;
    address public usdc;

    PositionInfo private _position;

    function initialize(
        uint256 nft_,
        address baseToken_,
        uint256 leverageMultiplierD_
    ) external {
        require(IBaseToken(baseToken_).isOpen(), ExceptionsLibrary.INVALID_TOKEN);
        IPerpVaultGovernance.DelayedProtocolParams memory params = IPerpVaultGovernance(address(_vaultGovernance))
            .delayedProtocolParams();
        uint256 maxProtocolLeverage = params.maxProtocolLeverage;

        require(leverageMultiplierD_ <= DENOMINATOR * (maxProtocolLeverage - 1)); // leverage more than 10x isn't available on Perp (exactly 10x may be subject to precision failures)

        leverageMultiplierD = leverageMultiplierD_;
        address[] memory vaultTokens_ = new address[](1);
        vaultTokens_[0] = params.usdcAddress;
        _initialize(vaultTokens_, nft_);

        vault = params.vault;
        clearingHouse = params.clearingHouse;
        accountBalance = params.accountBalance;
        usdc = params.usdcAddress;

        baseToken = baseToken_;

        pool = IUniswapV3Pool(
            IUniswapV3Factory(params.uniV3FactoryAddress).getPool(params.vusdcAddress, baseToken_, 3000)
        );
    }

    function position() public view returns (PositionInfo memory) {
        return _position;
    }

    function tvl() public view returns (uint256[] memory minTokenAmounts, uint256[] memory maxTokenAmounts) {
        uint256 usdcValue = getAccountValue();
        minTokenAmounts = new uint256[](1);
        maxTokenAmounts = new uint256[](1);

        minTokenAmounts[0] = usdcValue;
        maxTokenAmounts[0] = usdcValue;
    }

    function openUniPosition(
        int24 lowerTick,
        int24 upperTick,
        uint256[] memory minVTokenAmounts, /*maybe not needed*/ /*usdc, base token*/
        uint256 deadline
    ) external returns (uint128 liquidityAdded) {
        require(!isPositionOpened, ExceptionsLibrary.DUPLICATE);
        require(_isStrategy(msg.sender), ExceptionsLibrary.FORBIDDEN);

        uint256 vaultCapital = getAccountValue();
        require(vaultCapital > 0, ExceptionsLibrary.VALUE_ZERO);

        uint256 capitalToUse = FullMath.mulDiv(vaultCapital, leverageMultiplierD, DENOMINATOR);
        uint256 amountUsdcPerLiquidityUnitD;
        uint256 expectedVUsdc;
        uint256 expectedSecondToken;

        {
            (uint160 sqrtRatioX96, , , , , , ) = pool.slot0();
            uint160 sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(lowerTick);
            uint160 sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(upperTick);

            amountUsdcPerLiquidityUnitD = _calculatePositionCapital(
                uint128(DENOMINATOR),
                sqrtRatioX96,
                sqrtRatioAX96,
                sqrtRatioBX96
            );

            uint256 liquidityWanted = FullMath.mulDiv(capitalToUse, DENOMINATOR, amountUsdcPerLiquidityUnitD);
            (expectedVUsdc, expectedSecondToken) = LiquidityAmounts.getAmountsForLiquidity(
                sqrtRatioX96,
                sqrtRatioAX96,
                sqrtRatioBX96,
                uint128(liquidityWanted)
            );
        }

        IClearingHouse.AddLiquidityResponse memory response = clearingHouse.addLiquidity(
            IClearingHouse.AddLiquidityParams({
                baseToken: baseToken,
                base: expectedSecondToken,
                quote: expectedVUsdc,
                lowerTick: lowerTick,
                upperTick: upperTick,
                minBase: minVTokenAmounts[1],
                minQuote: minVTokenAmounts[0],
                useTakerBalance: false,
                deadline: deadline
            })
        );

        isPositionOpened = true;
        _position = PositionInfo({lowerTick: lowerTick, upperTick: upperTick, liquidity: uint128(response.liquidity)});
        liquidityAdded = uint128(response.liquidity);
    }

    function closeUniPosition(
        uint256[] memory minVTokenAmounts, /*maybe not needed*/
        uint256 deadline
    ) external {
        require(isPositionOpened, ExceptionsLibrary.NOT_FOUND);
        require(_isStrategy(msg.sender), ExceptionsLibrary.FORBIDDEN);

        PositionInfo memory currentPosition = _position;

        clearingHouse.removeLiquidity(
            IClearingHouse.RemoveLiquidityParams({
                baseToken: baseToken,
                lowerTick: currentPosition.lowerTick,
                upperTick: currentPosition.upperTick,
                liquidity: currentPosition.liquidity,
                minBase: minVTokenAmounts[1],
                minQuote: minVTokenAmounts[0],
                deadline: deadline
            })
        );

        _closePermanentPositions(deadline);
        isPositionOpened = false;
    }

    function getAccountValue() public view returns (uint256) {
        int256 usdcValue = clearingHouse.getAccountValue(address(this));
        if (usdcValue < 0) {
            return 0;
        }
        return uint256(usdcValue);
    }

    function updateLeverage(uint256 newLeverageMultiplierD_, uint256 deadline) external {
        require(_isApprovedOrOwner(msg.sender));

        IPerpVaultGovernance.DelayedProtocolParams memory params = IPerpVaultGovernance(address(_vaultGovernance))
            .delayedProtocolParams();
        uint256 maxProtocolLeverage = params.maxProtocolLeverage;
        require(newLeverageMultiplierD_ <= DENOMINATOR * (maxProtocolLeverage - 1));

        leverageMultiplierD = newLeverageMultiplierD_;

        uint256 vaultCapital = getAccountValue();
        uint256 capitalToUse = FullMath.mulDiv(vaultCapital, leverageMultiplierD, DENOMINATOR);

        _adjustPosition(capitalToUse, deadline);
    }

    function supportsInterface(bytes4 interfaceId) public view override(IERC165, IntegrationVault) returns (bool) {
        return super.supportsInterface(interfaceId) || (interfaceId == type(IPerpVault).interfaceId);
    }

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

        if (!isPositionOpened) {
            return actualTokenAmounts;
        }

        uint256 vaultCapital = getAccountValue();
        uint256 capitalToUse = FullMath.mulDiv(vaultCapital, leverageMultiplierD, DENOMINATOR);

        Options memory opts = _parseOptions(options);
        _adjustPosition(capitalToUse, opts.deadline);
    }

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
        uint256 vaultCapital = getAccountValue();
        require(vaultCapital >= usdcAmount, ExceptionsLibrary.LIMIT_OVERFLOW);

        if (isPositionOpened) {
            uint256 futureCapital = vaultCapital - usdcAmount;
            uint256 capitalToUse = FullMath.mulDiv(futureCapital, leverageMultiplierD, DENOMINATOR);

            Options memory opts = _parseOptions(options);
            _adjustPosition(capitalToUse, opts.deadline);
        }

        vault.withdraw(usdc, usdcAmount);

        IERC20(usdc).safeTransfer(to, usdcAmount);
        actualTokenAmounts = new uint256[](1);
        actualTokenAmounts[0] = usdcAmount;
    }

    function _adjustPosition(uint256 capitalToUse, uint256 deadline) internal {
        PositionInfo memory currentPosition = _position;

        (uint160 sqrtRatioX96, , , , , , ) = pool.slot0();
        uint160 sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(currentPosition.lowerTick);
        uint160 sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(currentPosition.upperTick);

        uint256 usdcCapital = _calculatePositionCapital(
            currentPosition.liquidity,
            sqrtRatioX96,
            sqrtRatioAX96,
            sqrtRatioBX96
        );
        _makePositionMarginallyCorrect(
            usdcCapital,
            capitalToUse,
            currentPosition.liquidity,
            currentPosition.lowerTick,
            currentPosition.upperTick,
            sqrtRatioX96,
            sqrtRatioAX96,
            sqrtRatioBX96,
            deadline
        );
    }

    function _isStrategy(address addr) internal view returns (bool) {
        return _vaultGovernance.internalParams().registry.getApproved(_nft) == addr;
    }

    function _closePermanentPositions(uint256 deadline) internal {
        int256 positionSize = accountBalance.getTakerPositionSize(address(this), baseToken);
        if (positionSize == 0) {
            return;
        }
        clearingHouse.closePosition(
            IClearingHouse.ClosePositionParams({
                baseToken: baseToken,
                sqrtPriceLimitX96: 0,
                oppositeAmountBound: 0,
                deadline: deadline,
                referralCode: 0
            })
        );
    }

    function _calculatePositionCapital(
        uint128 liquidity,
        uint160 sqrtRatioX96,
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96
    ) internal pure returns (uint256) {
        uint256 priceX96 = FullMath.mulDiv(sqrtRatioX96, sqrtRatioX96, Q96);

        (uint256 amountVUsdcPerLiquidityUnitD, uint256 amountVSecondTokenPerLiquidityUnitD) = LiquidityAmounts
            .getAmountsForLiquidity(sqrtRatioX96, sqrtRatioAX96, sqrtRatioBX96, uint128(DENOMINATOR));
        uint256 amountUsdcPerLiquidityUnitD = amountVUsdcPerLiquidityUnitD +
            FullMath.mulDiv(amountVSecondTokenPerLiquidityUnitD, Q96, priceX96);

        return FullMath.mulDiv(amountUsdcPerLiquidityUnitD, liquidity, DENOMINATOR);
    }

    function _makePositionMarginallyCorrect(
        uint256 capital,
        uint256 desiredCapital,
        uint128 liquidity,
        int24 lowerTick,
        int24 upperTick,
        uint160 sqrtRatioX96,
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint256 deadline
    ) internal {
        uint128 newLiquidity = uint128(FullMath.mulDiv(liquidity, desiredCapital, capital));
        if (liquidity < newLiquidity) {
            uint128 delta = newLiquidity - liquidity;
            (uint256 amountUsdc, uint256 amountBase) = LiquidityAmounts.getAmountsForLiquidity(
                sqrtRatioX96,
                sqrtRatioAX96,
                sqrtRatioBX96,
                delta
            );
            IClearingHouse.AddLiquidityResponse memory response = clearingHouse.addLiquidity(
                IClearingHouse.AddLiquidityParams({
                    baseToken: baseToken,
                    base: amountBase,
                    quote: amountUsdc,
                    lowerTick: lowerTick,
                    upperTick: upperTick,
                    minBase: 0,
                    minQuote: 0,
                    useTakerBalance: false,
                    deadline: deadline
                })
            );
            _position.liquidity += uint128(response.liquidity);
        } else {
            uint128 delta = liquidity - newLiquidity;
            clearingHouse.removeLiquidity(
                IClearingHouse.RemoveLiquidityParams({
                    baseToken: baseToken,
                    lowerTick: lowerTick,
                    upperTick: upperTick,
                    liquidity: delta,
                    minBase: 0,
                    minQuote: 0,
                    deadline: deadline
                })
            );

            _closePermanentPositions(deadline);
            if (newLiquidity == 0) {
                isPositionOpened = false;
            }
            _position.liquidity = newLiquidity;
        }
    }

    function _parseOptions(bytes memory options) internal view returns (Options memory) {
        if (options.length == 0) return Options({deadline: block.timestamp + 600});

        require(options.length == 32, ExceptionsLibrary.INVALID_VALUE);
        return abi.decode(options, (Options));
    }

    function _isReclaimForbidden(address addr) internal view override returns (bool) {
        if (addr == usdc) {
            return true;
        }
        return false;
    }
}
