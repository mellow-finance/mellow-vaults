// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.9;

import "./IntegrationVault.sol";
import "../interfaces/external/gearbox/ICreditFacade.sol";
import "../interfaces/external/gearbox/helpers/ICreditManagerV2.sol";
import "../interfaces/external/gearbox/helpers/IPriceOracle.sol";
import "../interfaces/external/gearbox/ICurveV1Adapter.sol";
import "../interfaces/external/gearbox/IConvexV1BoosterAdapter.sol";
import "../libraries/ExceptionsLibrary.sol";
import "../interfaces/vaults/IGearboxVault.sol";
import "../interfaces/vaults/IGearboxVaultGovernance.sol";

contract GearboxVault is IGearboxVault, IntegrationVault {
    using SafeERC20 for IERC20;

    uint256 public constant DENOMINATOR = 10**9;

    ICreditFacade private _creditFacade;
    ICreditManagerV2 private _creditManager;

    address public creditAccount;

    address public primaryToken;
    address public curveAdapter;
    address public convexAdapter;
    int128 primaryIndex;

    uint256 targetHealthFactorD;

    function tvl() public view override returns (uint256[] memory minTokenAmounts, uint256[] memory maxTokenAmounts) {
        (uint256 total, ) = _creditFacade.calcTotalValue(creditAccount);
        (, , uint256 borrowAmountWithInterestAndFees) = _creditManager.calcCreditAccountAccruedInterest(creditAccount);
        uint256 len = _vaultTokens.length;

        minTokenAmounts = new uint256[](len);
        maxTokenAmounts = new uint256[](len);

        minTokenAmounts[0] = total - borrowAmountWithInterestAndFees;
        maxTokenAmounts[0] = total - borrowAmountWithInterestAndFees;
    }

    function initialize(
        uint256 nft_,
        address[] memory collateralTokens_,
        address curveAdapter_,
        address convexAdapter_,
        address facade_,
        uint256 convexPoolId_,
        uint256 targetHealthFactorD_,
        bytes memory options
    ) external {
        uint256 maxCollateralTokensPerVault = IGearboxVaultGovernance(address(_vaultGovernance))
            .delayedProtocolParams()
            .maxCollateralTokensPerVault;

        require(collateralTokens_.length <= maxCollateralTokensPerVault, ExceptionsLibrary.INVALID_LENGTH);
        require(targetHealthFactorD_ > DENOMINATOR, ExceptionsLibrary.INVALID_VALUE);

        _initialize(collateralTokens_, nft_);

        primaryToken = collateralTokens_[0];
        curveAdapter = curveAdapter_;
        convexAdapter = convexAdapter_;

        ICreditFacade creditFacade = ICreditFacade(facade_);
        ICreditManagerV2 creditManager = ICreditManagerV2(creditFacade.creditManager());

        _creditFacade = creditFacade;
        _creditManager = creditManager;

        _verifyInstances(convexPoolId_, collateralTokens_);
        uint256 amount = _pullExistentials[0];

        uint256 referralCode = 0;
        if (options.length > 0) {
            referralCode = abi.decode(options, (uint256));
        }

        creditFacade.openCreditAccount(amount, address(this), 0, uint16(referralCode));
        creditAccount = creditManager.getCreditAccountOrRevert(address(this));
    }

    function _push(uint256[] memory tokenAmounts, bytes memory options)
        internal
        override
        returns (uint256[] memory actualTokenAmounts)
    {
        ICreditFacade creditFacade = _creditFacade;

        (uint256 previousTotal, ) = _creditFacade.calcTotalValue(creditAccount);
        address[] memory vaultTokens = _vaultTokens;

        address creditFacadeAddress = address(creditFacade);
        uint256 callsAmount = 0;

        for (uint256 i = 0; i < tokenAmounts.length; ++i) {
            uint256 amount = tokenAmounts[i];
            if (amount > 0) {
                IERC20(vaultTokens[i]).safeIncreaseAllowance(creditFacadeAddress, amount);
                callsAmount += 1;
            }
        }

        MultiCall[] memory calls = new MultiCall[](callsAmount);
        uint256 pointer = 0;

        for (uint256 i = 0; i < tokenAmounts.length; ++i) {
            uint256 amount = tokenAmounts[i];
            if (amount > 0) {
                calls[pointer] = MultiCall({
                    target: address(creditFacade),
                    callData: abi.encodeWithSelector(
                        ICreditFacade.addCollateral.selector,
                        address(this),
                        vaultTokens[i],
                        amount
                    )
                });
                pointer += 1;
            }
        }

        creditFacade.multicall(calls);

        actualTokenAmounts = tokenAmounts;
        (uint256 total, ) = _creditFacade.calcTotalValue(creditAccount);
        _adjustPosition(total, previousTotal);
    }

    function _pull(
        address to,
        uint256[] memory tokenAmounts,
        bytes memory options
    ) internal override returns (uint256[] memory actualTokenAmounts) {
        IPriceOracleV2 oracle = IPriceOracleV2(_creditManager.priceOracle());
        uint256 underlyingToPull = 0;
        (uint256 total, ) = _creditFacade.calcTotalValue(creditAccount);
        address[] memory vaultTokens = _vaultTokens;

        for (uint256 i = 0; i < tokenAmounts.length; ++i) {
            uint256 amount = tokenAmounts[i];
            address token = vaultTokens[i];
            if (amount > 0) {
                uint256 valueUsd = oracle.convertToUSD(amount, token);
                underlyingToPull += oracle.convertFromUSD(valueUsd, primaryToken);
            }
        }

        if (underlyingToPull > total) {
            underlyingToPull = total;
        }

        _adjustPosition(total - underlyingToPull, total);
    }

    function _verifyInstances(uint256 convexPoolId, address[] memory collateralTokens) internal {
        ICreditFacade creditFacade = _creditFacade;
        ICurveV1Adapter curveAdapter_ = ICurveV1Adapter(curveAdapter);
        IConvexV1BoosterAdapter convexAdapter_ = IConvexV1BoosterAdapter(convexAdapter);

        require(creditFacade.isTokenAllowed(primaryToken), ExceptionsLibrary.INVALID_TOKEN);

        for (uint256 i = 0; i < collateralTokens.length; ++i) {
            creditFacade.enableToken(collateralTokens[i]);
        }

        bool havePrimaryTokenInCurve = false;

        for (uint256 i = 0; i < 4; ++i) {
            address tokenI = curveAdapter_.coins(i);
            if (tokenI == primaryToken) {
                primaryIndex = int128(int256(i));
                havePrimaryTokenInCurve = true;
            }
        }

        require(havePrimaryTokenInCurve, ExceptionsLibrary.INVALID_TOKEN);

        address lpToken = curveAdapter_.lp_token();
        IBooster.PoolInfo memory poolInfo = convexAdapter_.poolInfo(convexPoolId);
        require(lpToken == poolInfo.lptoken, ExceptionsLibrary.INVALID_TARGET);
    }

    function supportsInterface(bytes4 interfaceId) public view override(IERC165, IntegrationVault) returns (bool) {
        return IntegrationVault.supportsInterface(interfaceId) || interfaceId == type(IGearboxVault).interfaceId;
    }

    function updateTargetHealthFactor(uint256 targetHealthFactorD_) external {
        require(_isApprovedOrOwner(msg.sender));
        require(targetHealthFactorD_ > DENOMINATOR, ExceptionsLibrary.INVALID_VALUE);

        (uint256 total, ) = _creditFacade.calcTotalValue(creditAccount);
        _adjustPosition(total, total);
    }

    function _isReclaimForbidden(address token) internal view override returns (bool) {
        return false;
    }

    function _adjustPosition(uint256 underlyingWant, uint256 underlyingCurrent) internal {
        ICreditFacade creditFacade = _creditFacade;

        if (underlyingWant > underlyingCurrent) {
            uint256 delta = underlyingWant - underlyingCurrent;
            MultiCall[] memory calls = new MultiCall[](2);
            calls[0] = MultiCall({
                target: address(creditFacade),
                callData: abi.encodeWithSelector(ICreditFacade.increaseDebt.selector, delta)
            });

            calls[1] = MultiCall({
                target: curveAdapter,
                callData: abi.encodeWithSelector(
                    ICurveV1Adapter.add_liquidity_one_coin.selector,
                    delta,
                    primaryIndex,
                    0
                )
            });

            creditFacade.multicall(calls);
        }
    }
}
