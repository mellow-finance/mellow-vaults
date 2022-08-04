// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.9;

import "../interfaces/external/perp/IPerpInternalVault.sol";
import "../interfaces/external/perp/IClearingHouse.sol";
import "../interfaces/external/perp/IBaseToken.sol";
import "../interfaces/external/perp/IAccountBalance.sol";
import "./IntegrationVault.sol";
import "../interfaces/vaults/IPerpFuturesVault.sol";
import "../libraries/ExceptionsLibrary.sol";
import "../libraries/external/FullMath.sol";
import "../interfaces/vaults/IPerpVaultGovernance.sol";

// FUTURE: CHECK SECURITY & SLIPPAGE EVERYWHERE
// check liquidation scenario
contract PerpFuturesVault is IPerpFuturesVault, IntegrationVault {
    using SafeERC20 for IERC20;

    address public baseToken;
    IPerpInternalVault public vault;
    IClearingHouse public clearingHouse;
    IAccountBalance public accountBalance;

    uint256 public constant DENOMINATOR = 10**9;
    uint256 public constant Q96 = 2**96;
    
    uint256 public leverageMultiplierD; // leverage using by usd 
    bool isLongBaseToken; // true if we long base token, false else
    address public usdc;

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
        require(leverageMultiplierD_ <= DENOMINATOR * (maxProtocolLeverage - 1)); // leverage more than 10x isn't available on Perp (exactly 10x may be subject to precision failures)

        leverageMultiplierD = leverageMultiplierD_;
        isLongBaseToken = isLongBaseToken_;
        address[] memory vaultTokens_ = new address[](1);
        vaultTokens_[0] = params.usdcAddress;
        _initialize(vaultTokens_, nft_);

        vault = params.vault;
        clearingHouse = params.clearingHouse;
        accountBalance = params.accountBalance;
        usdc = params.usdcAddress;

        baseToken = baseToken_;
    }

    function tvl() public view returns (uint256[] memory minTokenAmounts, uint256[] memory maxTokenAmounts) {
        uint256 usdcValue = getAccountValue();
        minTokenAmounts = new uint256[](1);
        maxTokenAmounts = new uint256[](1);

        minTokenAmounts[0] = usdcValue;
        maxTokenAmounts[0] = usdcValue;
    }

    function getAccountValue() public view returns (uint256) {
        int256 usdcValue = clearingHouse.getAccountValue(address(this));
        if (usdcValue < 0) {
            return 0;
        }
        return uint256(usdcValue);
    }

    function updateLeverage(uint256 newLeverageMultiplierD_, bool isLongBaseToken_, uint256 deadline) external {
        require(_isApprovedOrOwner(msg.sender));

        IPerpVaultGovernance.DelayedProtocolParams memory params = IPerpVaultGovernance(address(_vaultGovernance))
            .delayedProtocolParams();
        uint256 maxProtocolLeverage = params.maxProtocolLeverage;
        require(newLeverageMultiplierD_ <= DENOMINATOR * (maxProtocolLeverage - 1));

        leverageMultiplierD = newLeverageMultiplierD_;
        isLongBaseToken = isLongBaseToken_;

        uint256 vaultCapital = getAccountValue();
        uint256 capitalToUse = FullMath.mulDiv(vaultCapital, leverageMultiplierD, DENOMINATOR);

        _adjustPosition(capitalToUse, deadline);
    }

    function adjustPosition(uint256 deadline) external {
        require(_isApprovedOrOwner(msg.sender));

        uint256 vaultCapital = getAccountValue();
        uint256 capitalToUse = FullMath.mulDiv(vaultCapital, leverageMultiplierD, DENOMINATOR);

        _adjustPosition(capitalToUse, deadline);
    }

    function closePosition(uint256 deadline) external {
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

    function supportsInterface(bytes4 interfaceId) public view override(IERC165, IntegrationVault) returns (bool) {
        return super.supportsInterface(interfaceId) || (interfaceId == type(IPerpFuturesVault).interfaceId);
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

        Options memory opts = _parseOptions(options);

        uint256 vaultCapital = getAccountValue();
        uint256 capitalToUse = FullMath.mulDiv(vaultCapital, leverageMultiplierD, DENOMINATOR);

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

        uint256 futureCapital = vaultCapital - usdcAmount;
        uint256 capitalToUse = FullMath.mulDiv(futureCapital, leverageMultiplierD, DENOMINATOR);

        Options memory opts = _parseOptions(options);
        _adjustPosition(capitalToUse, opts.deadline);
        

        vault.withdraw(usdc, usdcAmount);

        IERC20(usdc).safeTransfer(to, usdcAmount);
        actualTokenAmounts = new uint256[](1);
        actualTokenAmounts[0] = usdcAmount;
    }

    function _adjustPosition(uint256 capitalToUse, uint256 deadline) internal {
        int256 positionSize = accountBalance.getTakerPositionSize(address(this), baseToken);
        if (isLongBaseToken) {
            if (int256(capitalToUse) > positionSize) {
                _makeAdjustment(true, uint256(int256(capitalToUse) - positionSize), deadline);
            }
            else {
                _makeAdjustment(false, uint256(positionSize - int256(capitalToUse)), deadline);
            }
        }
        else {
            if (-int256(capitalToUse) < positionSize) {
                _makeAdjustment(true, uint256(positionSize + int256(capitalToUse)), deadline);
            }
            else {
                _makeAdjustment(false, uint256(-positionSize - int256(capitalToUse)), deadline);
            }
        }
    }

    function _makeAdjustment(bool longBaseTokenInAdjustment, uint256 amount, uint256 deadline) internal {
        if (amount == 0) {
            return;
        }
        clearingHouse.openPosition(IClearingHouse.OpenPositionParams({
            baseToken: baseToken,
            isBaseToQuote: !longBaseTokenInAdjustment,
            isExactInput: true,
            amount: amount,
            oppositeAmountBound: 0,
            deadline: deadline,
            sqrtPriceLimitX96: 0,
            referralCode: 0
        }));
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
