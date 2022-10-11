// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.9;

import "./IntegrationVault.sol";
import "../interfaces/external/gearbox/helpers/convex/IBaseRewardPool.sol";
import "../interfaces/external/gearbox/IUniversalAdapter.sol";
import "../interfaces/vaults/IGearboxVault.sol";
import "../utils/GearboxHelper.sol";

contract GearboxVault is IGearboxVault, IntegrationVault {
    using SafeERC20 for IERC20;

    uint256 public constant D9 = 10**9;
    uint256 public constant D27 = 10**27;
    uint256 public constant D18 = 10**18;
    uint256 public constant D7 = 10**7;

    GearboxHelper internal _helper;

    ICreditFacade public creditFacade;
    ICreditManagerV2 public creditManager;

    address public creditAccount;

    address public primaryToken;
    address public depositToken;
    address public curveAdapter;
    address public convexAdapter;

    int128 primaryIndex;
    uint256 poolId;
    address convexOutputToken;

    uint256 marginalFactorD9;

    function tvl() public view override returns (uint256[] memory minTokenAmounts, uint256[] memory maxTokenAmounts) {
        uint256 primaryTokenAmount = _helper.calculateClaimableRewards(creditAccount, address(_vaultGovernance));

        if (primaryToken != depositToken) {
            primaryTokenAmount += IERC20(primaryToken).balanceOf(address(this));
        }

        if (creditAccount != address(0)) {
            (uint256 currentAllAssetsValue, ) = creditFacade.calcTotalValue(creditAccount);
            (, , uint256 borrowAmountWithInterestAndFees) = creditManager.calcCreditAccountAccruedInterest(
                creditAccount
            );

            if (currentAllAssetsValue >= borrowAmountWithInterestAndFees) {
                primaryTokenAmount += currentAllAssetsValue - borrowAmountWithInterestAndFees;
            }
        }

        minTokenAmounts = new uint256[](1);

        if (primaryToken == depositToken) {
            minTokenAmounts[0] = primaryTokenAmount + IERC20(depositToken).balanceOf(address(this));
        } else {
            IPriceOracleV2 oracle = IPriceOracleV2(creditManager.priceOracle());
            uint256 valueDeposit = oracle.convert(primaryTokenAmount, primaryToken, depositToken) +
                IERC20(depositToken).balanceOf(address(this));

            minTokenAmounts[0] = valueDeposit;
        }

        maxTokenAmounts = minTokenAmounts;
    }

    function initialize(
        uint256 nft_,
        address[] memory vaultTokens_,
        address helper_
    ) external {
        require(vaultTokens_.length == 1, ExceptionsLibrary.INVALID_LENGTH);

        _initialize(vaultTokens_, nft_);

        IGearboxVaultGovernance.DelayedProtocolPerVaultParams memory params = IGearboxVaultGovernance(
            address(_vaultGovernance)
        ).delayedProtocolPerVaultParams(nft_);
        primaryToken = params.primaryToken;
        depositToken = vaultTokens_[0];
        curveAdapter = params.curveAdapter;
        convexAdapter = params.convexAdapter;
        marginalFactorD9 = params.initialMarginalValueD9;

        creditFacade = ICreditFacade(params.facade);
        creditManager = ICreditManagerV2(creditFacade.creditManager());

        _helper = GearboxHelper(helper_);
        _helper.setParameters(creditFacade, creditManager, curveAdapter, convexAdapter, primaryToken, depositToken);

        (primaryIndex, convexOutputToken, poolId) = _helper.verifyInstances();
    }

    function openCreditAccount() external {
        _openCreditAccount();
    }

    function adjustPosition() external {
        require(_isApprovedOrOwner(msg.sender), ExceptionsLibrary.FORBIDDEN);
        (uint256 expectedAllAssetsValue, uint256 currentAllAssetsValue) = _helper.calculateDesiredTotalValue(
            creditAccount,
            address(_vaultGovernance),
            marginalFactorD9
        );
        _adjustPosition(expectedAllAssetsValue, currentAllAssetsValue);
    }

    function _push(uint256[] memory tokenAmounts, bytes memory) internal override returns (uint256[] memory) {
        require(tokenAmounts.length == 1, ExceptionsLibrary.INVALID_LENGTH);

        if (creditAccount != address(0)) {
            _addDepositTokenAsCollateral();
        }

        return tokenAmounts;
    }

    function _pull(
        address to,
        uint256[] memory tokenAmounts,
        bytes memory
    ) internal override returns (uint256[] memory actualTokenAmounts) {
        require(tokenAmounts.length == 1, ExceptionsLibrary.INVALID_LENGTH);
        if (creditAccount != address(0)) {
            actualTokenAmounts = _helper.pullFromAddress(tokenAmounts[0], address(_vaultGovernance));
            IERC20(depositToken).safeTransfer(to, actualTokenAmounts[0]);
            return actualTokenAmounts;
        }
        uint256 amountToPull = tokenAmounts[0];

        _helper.claimRewards(address(_vaultGovernance), creditAccount);
        _helper.withdrawFromConvex(
            IERC20(convexOutputToken).balanceOf(creditAccount),
            address(_vaultGovernance),
            poolId,
            primaryIndex
        );

        (, , uint256 debtAmount) = creditManager.calcCreditAccountAccruedInterest(creditAccount);
        uint256 underlyingBalance = IERC20(primaryToken).balanceOf(creditAccount);
        if (underlyingBalance < debtAmount + 1) {
            _helper.swapExactOutput(
                depositToken,
                primaryToken,
                debtAmount + 1 - underlyingBalance,
                0,
                address(_vaultGovernance),
                creditAccount
            );
        }

        uint256 depositTokenBalance = IERC20(depositToken).balanceOf(creditAccount);
        if (depositTokenBalance < amountToPull && primaryToken != depositToken) {
            _helper.swapExactOutput(
                primaryToken,
                depositToken,
                amountToPull - depositTokenBalance,
                debtAmount + 1,
                address(_vaultGovernance),
                creditAccount
            );
        }

        MultiCall[] memory noCalls = new MultiCall[](0);
        creditFacade.closeCreditAccount(address(this), 0, false, noCalls);

        depositTokenBalance = IERC20(depositToken).balanceOf(address(this));
        if (depositTokenBalance < amountToPull) {
            amountToPull = depositTokenBalance;
        }

        creditAccount = address(0);

        IERC20(depositToken).safeTransfer(to, amountToPull);
        actualTokenAmounts = new uint256[](1);

        actualTokenAmounts[0] = amountToPull;
    }

    function _openCreditAccount() internal {
        require(creditAccount == address(0), ExceptionsLibrary.DUPLICATE);

        ICreditFacade creditFacade_ = creditFacade;

        (uint256 minBorrowingLimit, ) = creditFacade_.limits();
        uint256 currentPrimaryTokenAmount = IERC20(primaryToken).balanceOf(address(this));

        IGearboxVaultGovernance.DelayedProtocolParams memory protocolParams = IGearboxVaultGovernance(
            address(_vaultGovernance)
        ).delayedProtocolParams();

        if (depositToken != primaryToken && currentPrimaryTokenAmount < minBorrowingLimit) {
            ISwapRouter router = ISwapRouter(protocolParams.uniswapRouter);
            uint256 amountInMaximum = _helper.calculateAmountInMaximum(
                depositToken,
                primaryToken,
                minBorrowingLimit - currentPrimaryTokenAmount,
                protocolParams.minSlippageD9
            );
            require(IERC20(depositToken).balanceOf(address(this)) >= amountInMaximum, ExceptionsLibrary.INVARIANT);

            ISwapRouter.ExactOutputParams memory uniParams = ISwapRouter.ExactOutputParams({
                path: abi.encodePacked(depositToken, uint24(500), primaryToken),
                recipient: address(this),
                deadline: block.timestamp + 900,
                amountOut: minBorrowingLimit - currentPrimaryTokenAmount,
                amountInMaximum: amountInMaximum
            });
            router.exactOutput(uniParams);

            currentPrimaryTokenAmount = IERC20(primaryToken).balanceOf(address(this));
        }

        require(currentPrimaryTokenAmount >= minBorrowingLimit, ExceptionsLibrary.LIMIT_UNDERFLOW);

        IERC20(primaryToken).safeIncreaseAllowance(address(creditManager), currentPrimaryTokenAmount);
        creditFacade_.openCreditAccount(
            currentPrimaryTokenAmount,
            address(this),
            uint16((marginalFactorD9 - D9) / D7),
            protocolParams.referralCode
        );
        IERC20(primaryToken).approve(address(creditManager), 0);

        creditAccount = creditManager.getCreditAccountOrRevert(address(this));

        if (depositToken != primaryToken) {
            creditFacade_.enableToken(depositToken);
            _addDepositTokenAsCollateral();
        }
    }

    function supportsInterface(bytes4 interfaceId) public view override(IERC165, IntegrationVault) returns (bool) {
        return IntegrationVault.supportsInterface(interfaceId) || interfaceId == type(IGearboxVault).interfaceId;
    }

    function updateTargetMarginalFactor(uint256 marginalFactorD9_) external {
        require(_isApprovedOrOwner(msg.sender));
        require(marginalFactorD9_ >= D9, ExceptionsLibrary.INVALID_VALUE);

        if (creditAccount == address(0)) {
            marginalFactorD9 = marginalFactorD9_;
            return;
        }

        (, uint256 currentAllAssetsValue) = _helper.calculateDesiredTotalValue(
            creditAccount,
            address(_vaultGovernance),
            marginalFactorD9
        );
        marginalFactorD9 = marginalFactorD9_;
        (uint256 expectedAllAssetsValue, ) = _helper.calculateDesiredTotalValue(
            creditAccount,
            address(_vaultGovernance),
            marginalFactorD9
        );

        _adjustPosition(expectedAllAssetsValue, currentAllAssetsValue);
    }

    function _isReclaimForbidden(address) internal pure override returns (bool) {
        return false;
    }

    function _addDepositTokenAsCollateral() internal {
        ICreditFacade creditFacade_ = creditFacade;
        MultiCall[] memory calls = new MultiCall[](1);
        address creditManagerAddress = address(creditManager);

        address token = depositToken;
        uint256 amount = IERC20(token).balanceOf(address(this));

        IERC20(token).safeIncreaseAllowance(creditManagerAddress, amount);

        calls[0] = MultiCall({
            target: address(creditFacade_),
            callData: abi.encodeWithSelector(ICreditFacade.addCollateral.selector, address(this), token, amount)
        });

        creditFacade_.multicall(calls);
        IERC20(token).approve(creditManagerAddress, 0);
    }

    function _adjustPosition(uint256 expectedAllAssetsValue, uint256 currentAllAssetsValue) internal {
        _helper.claimRewards(address(_vaultGovernance), creditAccount);

        IGearboxVaultGovernance.DelayedProtocolParams memory protocolParams = IGearboxVaultGovernance(
            address(_vaultGovernance)
        ).delayedProtocolParams();
        ICreditFacade creditFacade_ = creditFacade;

        _helper.checkNecessaryDepositExchange(
            FullMath.mulDiv(expectedAllAssetsValue, D9, marginalFactorD9),
            address(_vaultGovernance),
            creditAccount
        );
        uint256 currentPrimaryTokenAmount = IERC20(primaryToken).balanceOf(creditAccount);

        if (expectedAllAssetsValue >= currentAllAssetsValue) {
            uint256 delta = expectedAllAssetsValue - currentAllAssetsValue;

            MultiCall memory increaseDebtCall = MultiCall({
                target: address(creditFacade_),
                callData: abi.encodeWithSelector(ICreditFacade.increaseDebt.selector, delta)
            });

            _helper.depositToConvex(increaseDebtCall, protocolParams, poolId, primaryIndex);
        } else {
            uint256 delta = currentAllAssetsValue - expectedAllAssetsValue;

            if (currentPrimaryTokenAmount >= delta) {
                MultiCall memory decreaseDebtCall = MultiCall({
                    target: address(creditFacade_),
                    callData: abi.encodeWithSelector(ICreditFacade.decreaseDebt.selector, delta)
                });

                _helper.depositToConvex(decreaseDebtCall, protocolParams, poolId, primaryIndex);
            } else {
                uint256 convexAmountToWithdraw = _helper.calcConvexTokensToWithdraw(
                    delta - currentPrimaryTokenAmount,
                    creditAccount,
                    convexOutputToken
                );
                _helper.withdrawFromConvex(convexAmountToWithdraw, address(_vaultGovernance), poolId, primaryIndex);

                currentPrimaryTokenAmount = IERC20(primaryToken).balanceOf(creditAccount);
                if (currentPrimaryTokenAmount < delta) {
                    delta = currentPrimaryTokenAmount;
                }

                MultiCall[] memory decreaseCall = new MultiCall[](1);
                decreaseCall[0] = MultiCall({
                    target: address(creditFacade_),
                    callData: abi.encodeWithSelector(ICreditFacade.decreaseDebt.selector, delta)
                });

                creditFacade_.multicall(decreaseCall);
            }
        }
    }

    function multicall(MultiCall[] memory calls) external {
        require(msg.sender == address(_helper), ExceptionsLibrary.FORBIDDEN);
        creditFacade.multicall(calls);
    }

    function swap(ISwapRouter router, ISwapRouter.ExactOutputParams memory uniParams) external {
        require(msg.sender == address(_helper), ExceptionsLibrary.FORBIDDEN);
        router.exactOutput(uniParams);
    }
}
