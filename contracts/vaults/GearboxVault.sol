// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.9;

import "./IntegrationVault.sol";
import "../utils/GearboxHelper.sol";
import "../interfaces/external/gearbox/helpers/IDegenDistributor.sol";

contract GearboxVault is IGearboxVault, IntegrationVault {
    using SafeERC20 for IERC20;

    uint256 public constant D9 = 10**9;
    uint256 public constant D7 = 10**7;

    GearboxHelper internal _helper;

    bytes32[] private _merkleProof;

    /// @inheritdoc IGearboxVault
    ICreditFacade public creditFacade;

    /// @inheritdoc IGearboxVault
    ICreditManagerV2 public creditManager;

    /// @inheritdoc IGearboxVault
    address public primaryToken;
    /// @inheritdoc IGearboxVault
    address public depositToken;

    /// @inheritdoc IGearboxVault
    int128 public primaryIndex;
    /// @inheritdoc IGearboxVault
    uint256 public poolId;
    /// @inheritdoc IGearboxVault
    address public convexOutputToken;

    /// @inheritdoc IGearboxVault
    uint256 public marginalFactorD9;

    /// @inheritdoc IGearboxVault
    uint256 public merkleIndex;

    /// @inheritdoc IGearboxVault
    uint256 public merkleTotalAmount;

    // -------------------  EXTERNAL, VIEW  -------------------

    /// @inheritdoc IVault
    function tvl() public view override returns (uint256[] memory minTokenAmounts, uint256[] memory maxTokenAmounts) {
        address creditAccount = getCreditAccount();

        address depositToken_ = depositToken;
        address primaryToken_ = primaryToken;
        address creditAccount_ = creditAccount;

        uint256 primaryTokenAmount = _helper.calculateClaimableRewards(creditAccount_, address(_vaultGovernance));

        if (primaryToken_ != depositToken_) {
            primaryTokenAmount += IERC20(primaryToken_).balanceOf(address(this));
        }

        if (creditAccount_ != address(0)) {
            (uint256 currentAllAssetsValue, ) = creditFacade.calcTotalValue(creditAccount_);
            (, , uint256 borrowAmountWithInterestAndFees) = creditManager.calcCreditAccountAccruedInterest(
                creditAccount_
            );

            if (currentAllAssetsValue >= borrowAmountWithInterestAndFees) {
                primaryTokenAmount += currentAllAssetsValue - borrowAmountWithInterestAndFees;
            }
        }

        minTokenAmounts = new uint256[](1);

        if (primaryToken_ == depositToken_) {
            minTokenAmounts[0] = primaryTokenAmount + IERC20(depositToken_).balanceOf(address(this));
        } else {
            IPriceOracleV2 oracle = IPriceOracleV2(creditManager.priceOracle());
            uint256 valueDeposit = oracle.convert(primaryTokenAmount, primaryToken_, depositToken_) +
                IERC20(depositToken_).balanceOf(address(this));

            minTokenAmounts[0] = valueDeposit;
        }

        maxTokenAmounts = minTokenAmounts;
    }

    /// @inheritdoc IntegrationVault
    function supportsInterface(bytes4 interfaceId) public view override(IERC165, IntegrationVault) returns (bool) {
        return IntegrationVault.supportsInterface(interfaceId) || interfaceId == type(IGearboxVault).interfaceId;
    }

    /// @inheritdoc IGearboxVault
    function getCreditAccount() public view returns (address) {
        return creditManager.creditAccounts(address(this));
    }

    /// @inheritdoc IGearboxVault
    function getAllAssetsOnCreditAccountValue() external view returns (uint256 currentAllAssetsValue) {
        address creditAccount = getCreditAccount();
        if (creditAccount == address(0)) {
            return 0;
        }
        (currentAllAssetsValue, ) = creditFacade.calcTotalValue(creditAccount);
    }

    /// @inheritdoc IGearboxVault
    function getClaimableRewardsValue() external view returns (uint256) {
        address creditAccount = getCreditAccount();
        if (creditAccount == address(0)) {
            return 0;
        }
        return _helper.calculateClaimableRewards(creditAccount, address(_vaultGovernance));
    }

    function getMerkleProof() external view returns (bytes32[] memory) {
        return _merkleProof;
    }

    // -------------------  EXTERNAL, MUTATING  -------------------

    /// @inheritdoc IGearboxVault
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
        marginalFactorD9 = params.initialMarginalValueD9;

        creditFacade = ICreditFacade(params.facade);
        creditManager = ICreditManagerV2(creditFacade.creditManager());

        _helper = GearboxHelper(helper_);
        _helper.setParameters(
            creditFacade,
            creditManager,
            params.curveAdapter,
            params.convexAdapter,
            params.primaryToken,
            vaultTokens_[0],
            _nft
        );

        (primaryIndex, convexOutputToken, poolId) = _helper.verifyInstances();
    }

    /// @inheritdoc IGearboxVault
    function openCreditAccount() external {
        require(_isApprovedOrOwner(msg.sender), ExceptionsLibrary.FORBIDDEN);
        address degenNft = creditFacade.degenNFT();

        if (degenNft != address(0)) {
            IDegenNFT degenContract = IDegenNFT(degenNft);
            IDegenDistributor distributor = IDegenDistributor(degenContract.minter());
            if (distributor.claimed(address(this)) < merkleTotalAmount) {
                distributor.claim(merkleIndex, address(this), merkleTotalAmount, _merkleProof);
            }
        }

        address creditAccount = getCreditAccount();
        _helper.openCreditAccount(creditAccount, address(_vaultGovernance), marginalFactorD9);

        if (depositToken != primaryToken) {
            creditFacade.enableToken(depositToken);
            _addDepositTokenAsCollateral();
        }
    }

    /// @inheritdoc IGearboxVault
    function adjustPosition() external {
        require(_isApprovedOrOwner(msg.sender), ExceptionsLibrary.FORBIDDEN);
        address creditAccount = getCreditAccount();

        if (creditAccount == address(0)) {
            return;
        }

        uint256 marginalFactorD9_ = marginalFactorD9;
        GearboxHelper helper_ = _helper;

        (uint256 expectedAllAssetsValue, uint256 currentAllAssetsValue) = helper_.calculateDesiredTotalValue(
            creditAccount,
            address(_vaultGovernance),
            marginalFactorD9_
        );
        helper_.adjustPosition(
            expectedAllAssetsValue,
            currentAllAssetsValue,
            address(_vaultGovernance),
            marginalFactorD9_,
            primaryIndex,
            poolId,
            convexOutputToken,
            creditAccount
        );
    }

    /// @inheritdoc IGearboxVault
    function setMerkleParameters(
        uint256 merkleIndex_,
        uint256 merkleTotalAmount_,
        bytes32[] memory merkleProof_
    ) public {
        require(_isApprovedOrOwner(msg.sender));
        merkleIndex = merkleIndex_;
        merkleTotalAmount = merkleTotalAmount_;
        _merkleProof = merkleProof_;
    }

    /// @inheritdoc IGearboxVault
    function updateTargetMarginalFactor(uint256 marginalFactorD9_) external {
        require(_isApprovedOrOwner(msg.sender));
        require(marginalFactorD9_ > D9, ExceptionsLibrary.INVALID_VALUE);

        address creditAccount_ = getCreditAccount();
        GearboxHelper helper_ = _helper;

        if (creditAccount_ == address(0)) {
            marginalFactorD9 = marginalFactorD9_;
            return;
        }

        marginalFactorD9 = marginalFactorD9_;
        (uint256 expectedAllAssetsValue, uint256 currentAllAssetsValue) = helper_.calculateDesiredTotalValue(
            creditAccount_,
            address(_vaultGovernance),
            marginalFactorD9_
        );

        helper_.adjustPosition(
            expectedAllAssetsValue,
            currentAllAssetsValue,
            address(_vaultGovernance),
            marginalFactorD9_,
            primaryIndex,
            poolId,
            convexOutputToken,
            creditAccount_
        );
        emit TargetMarginalFactorUpdated(tx.origin, msg.sender, marginalFactorD9_);
    }

    /// @inheritdoc IGearboxVault
    function multicall(MultiCall[] memory calls) external {
        require(msg.sender == address(_helper), ExceptionsLibrary.FORBIDDEN);
        creditFacade.multicall(calls);
    }

    /// @inheritdoc IGearboxVault
    function swap(
        ISwapRouter router,
        ISwapRouter.ExactOutputParams memory uniParams,
        address token,
        uint256 amount
    ) external {
        require(msg.sender == address(_helper), ExceptionsLibrary.FORBIDDEN);
        IERC20(token).safeIncreaseAllowance(address(router), amount);
        router.exactOutput(uniParams);
        IERC20(token).approve(address(router), 0);
    }

    /// @inheritdoc IGearboxVault
    function openCreditAccountInManager(uint256 currentPrimaryTokenAmount, uint16 referralCode) external {
        require(msg.sender == address(_helper), ExceptionsLibrary.FORBIDDEN);
        IERC20(primaryToken).safeIncreaseAllowance(address(creditManager), currentPrimaryTokenAmount);
        creditFacade.openCreditAccount(
            currentPrimaryTokenAmount,
            address(this),
            uint16((marginalFactorD9 - D9) / D7),
            referralCode
        );
        IERC20(primaryToken).approve(address(creditManager), 0);
    }

    // -------------------  INTERNAL, VIEW  -------------------

    function _isReclaimForbidden(address) internal pure override returns (bool) {
        return false;
    }

    // -------------------  INTERNAL, MUTATING  -------------------

    function _push(uint256[] memory tokenAmounts, bytes memory) internal override returns (uint256[] memory) {
        require(tokenAmounts.length == 1, ExceptionsLibrary.INVALID_LENGTH);
        address creditAccount = getCreditAccount();

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

        address depositToken_ = depositToken;
        address primaryToken_ = primaryToken;
        address creditAccount_ = getCreditAccount();
        GearboxHelper helper_ = _helper;

        if (creditAccount_ == address(0)) {
            actualTokenAmounts = helper_.pullFromAddress(tokenAmounts[0], address(_vaultGovernance));
            IERC20(depositToken_).safeTransfer(to, actualTokenAmounts[0]);
            return actualTokenAmounts;
        }
        uint256 amountToPull = tokenAmounts[0];

        helper_.claimRewards(address(_vaultGovernance), creditAccount_, convexOutputToken);
        helper_.withdrawFromConvex(
            IERC20(convexOutputToken).balanceOf(creditAccount_),
            address(_vaultGovernance),
            primaryIndex
        );

        (, , uint256 debtAmount) = creditManager.calcCreditAccountAccruedInterest(creditAccount_);
        uint256 underlyingBalance = IERC20(primaryToken_).balanceOf(creditAccount_);

        if (underlyingBalance < debtAmount + 1) {
            helper_.swapExactOutput(
                depositToken_,
                primaryToken_,
                debtAmount + 1 - underlyingBalance,
                0,
                address(_vaultGovernance),
                creditAccount_
            );
        }

        uint256 depositTokenBalance = IERC20(depositToken_).balanceOf(creditAccount_);
        if (depositTokenBalance < amountToPull && primaryToken_ != depositToken_) {
            helper_.swapExactOutput(
                primaryToken_,
                depositToken_,
                amountToPull - depositTokenBalance,
                debtAmount + 1,
                address(_vaultGovernance),
                creditAccount_
            );
        }

        MultiCall[] memory noCalls = new MultiCall[](0);
        creditFacade.closeCreditAccount(address(this), 0, false, noCalls);

        depositTokenBalance = IERC20(depositToken_).balanceOf(address(this));
        if (depositTokenBalance < amountToPull) {
            amountToPull = depositTokenBalance;
        }

        IERC20(depositToken_).safeTransfer(to, amountToPull);
        actualTokenAmounts = new uint256[](1);

        actualTokenAmounts[0] = amountToPull;
    }

    /// @notice Deposits all deposit tokens which are on the address of the vault into the credit account
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

    // --------------------------  EVENTS  --------------------------

    /// @notice Emitted when target marginal factor is updated
    /// @param origin Origin of the transaction (tx.origin)
    /// @param sender Sender of the call (msg.sender)
    /// @param newMarginalFactorD9 New marginal factor
    event TargetMarginalFactorUpdated(address indexed origin, address indexed sender, uint256 newMarginalFactorD9);
}
