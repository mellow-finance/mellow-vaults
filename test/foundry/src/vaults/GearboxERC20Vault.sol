// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import "./IntegrationVault.sol";

import "../libraries/ExceptionsLibrary.sol";
import "../interfaces/vaults/IERC20Vault.sol";
import "../interfaces/vaults/IGearboxERC20Vault.sol";
import "../interfaces/vaults/IGearboxVault.sol";
import "../interfaces/external/gearbox/helpers/curve/ICurvePool.sol";
import "../interfaces/external/gearbox/helpers/IPoolService.sol";
import "../interfaces/external/gearbox/helpers/ICreditAccount.sol";

/// @notice Vault that stores ERC20 tokens.
contract GearboxERC20Vault is IGearboxERC20Vault, IntegrationVault {

    uint256 public constant EMPTY = 0;
    uint256 public constant PARTIAL = 1; 
    uint256 public constant FULL = 2;  

    uint256 public constant D9 = 10**9;
    uint256 public constant D27 = 10**27;
    uint256 public constant Q96 = 2**96;

    uint256 public constant MAX_LENGTH = 126;

    using SafeERC20 for IERC20;
    
    /// @inheritdoc IGearboxERC20Vault
    address[] public subvaultsList;

    /// @inheritdoc IGearboxERC20Vault
    uint256[] public limitsList;
    
    /// @inheritdoc IGearboxERC20Vault
    uint256 public subvaultsStatusMask;

    /// @inheritdoc IGearboxERC20Vault
    uint256 public totalDeposited;

    /// @inheritdoc IGearboxERC20Vault
    address public curveAdapter;

    /// @inheritdoc IGearboxERC20Vault
    address public convexAdapter;

    /// @inheritdoc IGearboxERC20Vault
    uint256 public totalLimit;

    /// @inheritdoc IGearboxERC20Vault
    uint256 public totalConvexLpTokens;

    /// @inheritdoc IGearboxERC20Vault
    uint256 public cumulativeSumRAY;

    /// @inheritdoc IGearboxERC20Vault
    uint256 public totalBorrowedAmount;

    /// @inheritdoc IGearboxERC20Vault
    uint256 public totalEarnedCRV;
    /// @inheritdoc IGearboxERC20Vault
    uint256 public cumulativeSumCRV;
    /// @inheritdoc IGearboxERC20Vault
    uint256 public cumulativeSubCRV;

    /// @inheritdoc IGearboxERC20Vault
    uint256 public totalEarnedLDO;
    /// @inheritdoc IGearboxERC20Vault
    uint256 public cumulativeSumLDO;
    /// @inheritdoc IGearboxERC20Vault
    uint256 public cumulativeSubLDO;

    // -------------------  EXTERNAL, VIEW  -------------------

    /// @inheritdoc IGearboxERC20Vault
    function calculatePoolsFeeD() external view returns (uint256) {
        uint256 mask = subvaultsStatusMask;
        if (mask == 0) {
            return 0;
        }

        uint256 index = 0;
        while (mask & 3 == 0) {
            mask >>= 2;
            index += 1;
        }

        return IGearboxVault(subvaultsList[index]).calculatePoolsFeeD();
    }

    /// @inheritdoc IVault
    function tvl() public view returns (uint256[] memory minTokenAmounts, uint256[] memory maxTokenAmounts) {
        minTokenAmounts = new uint256[](1);

        IERC20 token = IERC20(_vaultTokens[0]);
        minTokenAmounts[0] = totalDeposited;

        if (subvaultsList.length == 0) {
            return (minTokenAmounts, minTokenAmounts);
        }

        IGearboxVault sampleVault = IGearboxVault(subvaultsList[0]);
        ICreditManagerV2 creditManager = sampleVault.creditManager();
        GearboxHelper helper = sampleVault.helper();
        IGearboxVaultGovernance.DelayedProtocolParams memory protocolParams = IGearboxVaultGovernance(address(sampleVault.vaultGovernance())).delayedProtocolParams();
        IPriceOracleV2 oracle = helper.oracle();
        address primaryToken = sampleVault.primaryToken();
        address depositToken = address(token);
        IOracle mellowOracle = helper.mellowOracle();

        uint256 totalPrimaryTokenAmount;

        {

            if (depositToken != primaryToken) {
                for (uint256 i = 0; i < subvaultsList.length; ++i) {
                    address ca = IGearboxVault(subvaultsList[i]).getCreditAccount();
                    if (ca != address(0)) {
                        minTokenAmounts[0] += token.balanceOf(ca);
                    }
                    minTokenAmounts[0] += token.balanceOf(subvaultsList[i]);
                }
            }

            for (uint256 i = 0; i < subvaultsList.length; ++i) {
                totalPrimaryTokenAmount += IERC20(primaryToken).balanceOf(subvaultsList[i]);
            }


        }

        {

            totalPrimaryTokenAmount += helper.calcTotalWithdraw(totalConvexLpTokens);

        }

        {
        
            uint256 totalBorrowedWithInterest = FullMath.mulDiv(cumulativeSumRAY, IPoolService(creditManager.pool()).calcLinearCumulative_RAY(), D27);
            (uint16 feeInterest, , , ,) = creditManager.fees();
            if (totalBorrowedWithInterest > totalBorrowedAmount) {
                totalPrimaryTokenAmount -= FullMath.mulDiv(totalBorrowedWithInterest - totalBorrowedAmount, uint256(feeInterest), 10000);
            }

            totalPrimaryTokenAmount -= totalBorrowedWithInterest;

        }

        {

            uint256 totalCRV = totalEarnedCRV;
            uint256 rewardPerToken = IConvexV1BaseRewardPoolAdapter(convexAdapter).rewardPerToken();
            totalCRV += (cumulativeSumCRV * rewardPerToken - cumulativeSubCRV) / 10**18;
            totalPrimaryTokenAmount += oracle.convert(totalCRV, protocolParams.crv, primaryToken);
            {
                uint256 totalCVX = helper.calculateEarnedCvxAmountByEarnedCrvAmount(totalCRV, protocolParams.cvx);
                totalPrimaryTokenAmount += oracle.convert(totalCVX, protocolParams.cvx, primaryToken);
            }

        }

            {

            IBaseRewardPool underlyingContract = IBaseRewardPool(creditManager.adapterToContract(convexAdapter));
            if (underlyingContract.extraRewardsLength() > 0) {
                IBaseRewardPool rewardsContract = IBaseRewardPool(underlyingContract.extraRewards(0));
                uint256 rewardPerTokenLDO = rewardsContract.rewardPerToken();
                uint256 totalLDO = totalEarnedLDO + (cumulativeSumLDO * rewardPerTokenLDO - cumulativeSubLDO) / 10**18;

                (uint256[] memory pricesX96, ) = mellowOracle.priceX96(address(rewardsContract.rewardToken()), primaryToken, 0x20);
                if (pricesX96.length != 0) {
                    totalPrimaryTokenAmount += FullMath.mulDiv(totalLDO, pricesX96[0], Q96);
                }
            }

        }

        if (depositToken != primaryToken) {
            minTokenAmounts[0] += oracle.convert(totalPrimaryTokenAmount, primaryToken, depositToken);
        }
        else {
            minTokenAmounts[0] += totalPrimaryTokenAmount;
        }


        maxTokenAmounts = minTokenAmounts;
    }

    // -------------------  EXTERNAL, MUTATING  -------------------
    /// @inheritdoc IGearboxERC20Vault
    function initialize(uint256 nft_, address[] memory vaultTokens_) external {
        _initialize(vaultTokens_, nft_);
    }

     /// @inheritdoc IGearboxERC20Vault
    function adjustAllPositions() external {
        require(_isApprovedOrOwner(msg.sender), ExceptionsLibrary.FORBIDDEN);

        for (uint256 i = 0; i < subvaultsList.length; ++i) {
            address vault = subvaultsList[i];
            _adjustParameters(vault, -1);
            IGearboxVault(vault).adjustPosition();
            _adjustParameters(vault, 1);
        }
    }

    /// @inheritdoc IGearboxERC20Vault
    function addSubvault(address addr, uint256 limit) external {

        require(_isApprovedOrOwner(msg.sender), ExceptionsLibrary.FORBIDDEN);

        IVaultRegistry registry = _vaultGovernance.internalParams().registry;
        require(registry.ownerOf(IVault(addr).nft()) == registry.ownerOf(_nft), ExceptionsLibrary.FORBIDDEN);

        IGearboxVault vault = IGearboxVault(addr);
        uint256 currentTvl = _getTvl(addr);

        require(currentTvl == 0, ExceptionsLibrary.INVALID_STATE);

        if (subvaultsList.length > 0) {
            bool statusGeneric = (IGearboxVault(subvaultsList[0]).primaryToken() == IGearboxVault(subvaultsList[0]).depositToken());
            bool statusNew = (vault.primaryToken() == vault.depositToken());
            require(statusGeneric == statusNew, ExceptionsLibrary.INVARIANT);
        }

        require(subvaultsList.length < MAX_LENGTH, ExceptionsLibrary.INVALID_LENGTH);

        uint256 marginalFactorD9 = vault.marginalFactorD9();
        uint256 supposedBorrow = FullMath.mulDiv(limit, marginalFactorD9 - D9, D9);
        (uint256 minBorrow, uint256 maxBorrow) = vault.creditFacade().limits();
        require(supposedBorrow > minBorrow && supposedBorrow < maxBorrow, ExceptionsLibrary.INVALID_VALUE);

        subvaultsList.push(addr);
        limitsList.push(limit);

        totalLimit += limit;

        _makeSorted();
    }

    /// @inheritdoc IGearboxERC20Vault
    function changeLimit(uint256 index, uint256 limit) public {
        require(_isApprovedOrOwner(msg.sender) || msg.sender == address(this), ExceptionsLibrary.FORBIDDEN);
        require(index < subvaultsList.length, ExceptionsLibrary.INVALID_TARGET);
        uint256 status = (subvaultsStatusMask & (3 << (2 * index))) >> (2 * index);
        require(status == EMPTY || msg.sender == address(this), ExceptionsLibrary.FORBIDDEN);

        IGearboxVault vault = IGearboxVault(subvaultsList[index]);

        _adjustParameters(subvaultsList[index], -1);

        uint256 marginalFactorD9 = vault.marginalFactorD9();
        uint256 supposedBorrow = FullMath.mulDiv(limit, marginalFactorD9 - D9, D9);
        (uint256 minBorrow, uint256 maxBorrow) = vault.creditFacade().limits();
        require(supposedBorrow > minBorrow && supposedBorrow < maxBorrow, ExceptionsLibrary.INVALID_VALUE);

        totalLimit += limit;
        totalLimit -= limitsList[index];

        limitsList[index] = limit;
        
        _makeSorted();
        _adjustParameters(subvaultsList[index], 1);
    }

    /// @inheritdoc IGearboxERC20Vault
    function changeLimitAndFactor(uint256 index, uint256 limit, uint256 factor) external {
        require(_isApprovedOrOwner(msg.sender), ExceptionsLibrary.FORBIDDEN);

        IGearboxVault vault = IGearboxVault(subvaultsList[index]);
        _adjustParameters(subvaultsList[index], -1);
        vault.updateTargetMarginalFactor(factor);

        GearboxERC20Vault(address(this)).changeLimit(index, limit);
        _adjustParameters(subvaultsList[index], 1);
    }

    /// @inheritdoc IGearboxERC20Vault
    function distributeDeposits() external {

        require(_isApprovedOrOwner(msg.sender), ExceptionsLibrary.FORBIDDEN);
        if (totalDeposited == 0) {
            return;
        }

        uint256 vaultCount = subvaultsList.length;
        uint256 mask = subvaultsStatusMask;
        uint256 remainingDeposited = totalDeposited;

        uint256 specialVault = 0;

        for (uint256 i = 0; i < vaultCount; ++i) {
            uint256 status = (mask & (3 << (2 * i))) >> (2 * i);
            if (status == PARTIAL) {
                specialVault = i + 1;
            }
        }

        if (specialVault != 0) {
            (mask, remainingDeposited) = _depositTo(specialVault - 1, mask, remainingDeposited, PARTIAL);
        }

        for (uint256 i = 0; i < vaultCount && totalDeposited > 0; ++i) {
            uint256 status = (mask & (3 << (2 * i))) >> (2 * i);
            if (status == EMPTY) {
                (mask, remainingDeposited) = _depositTo(i, mask, remainingDeposited, status);
            }
        }

        totalDeposited = remainingDeposited;
        subvaultsStatusMask = mask;
    }

    /// @inheritdoc IGearboxERC20Vault
    function withdraw(uint256 tvlBefore, uint256 shareD27) external returns (uint256 withdrawn) {

        IVaultRegistry registry = _vaultGovernance.internalParams().registry;
        require(registry.ownerOf(_nft) == msg.sender, ExceptionsLibrary.FORBIDDEN);

        uint256 vaultCount = subvaultsList.length;

        uint256 toWithdraw = FullMath.mulDiv(tvlBefore, shareD27, D27);
        uint256 claimed = 0;
        uint256 mask = subvaultsStatusMask;

        if (totalDeposited >= toWithdraw) {
            totalDeposited -= toWithdraw;
            return toWithdraw;
        }

        toWithdraw -= totalDeposited;


        for (uint256 helpI = 0; helpI < 2 * vaultCount && toWithdraw > 0; ++helpI) {

            uint256 i = helpI;
            if (helpI >= vaultCount) {
                i = 2*vaultCount - helpI - 1;
            }

            if (helpI < vaultCount && limitsList[i] < toWithdraw) {
                continue;
            }
            
            uint256 status = (mask & (3 << (2 * i))) >> (2 * i);
            if (status == EMPTY) {
                continue;
            }

            if (status == PARTIAL) {
                uint256 partialVaultTvl = _getTvl(subvaultsList[i]);
                if (helpI < vaultCount && partialVaultTvl < toWithdraw) {
                    continue;
                }
            }

            mask ^= (status << (2 * i));

            _adjustParameters(subvaultsList[i], -1);
            IGearboxVault(subvaultsList[i]).closeCreditAccount();

            uint256 vaultTvl = _getTvl(subvaultsList[i]);
            IGearboxVault(subvaultsList[i]).claim();

            claimed += vaultTvl;

            if (vaultTvl <= toWithdraw) {
                toWithdraw -= vaultTvl;
            }

            else {
                toWithdraw = 0;
            }
        }

        (uint256[] memory newTvlMin, ) = tvl();

        uint256 newTvl = newTvlMin[0] + claimed;
        uint256 loss = 0;

        if (newTvl < tvlBefore) {
            loss = tvlBefore - newTvl;
        }

        subvaultsStatusMask = mask;
        totalDeposited = 0;

        uint256 finalWithdraw = FullMath.mulDiv(tvlBefore, shareD27, D27) - loss;
        totalDeposited = totalDeposited + claimed - finalWithdraw;

        return finalWithdraw;

    }

    /// @inheritdoc IGearboxERC20Vault
    function setAdapters(address curveAdapter_, address convexAdapter_) external {
        require(_isApprovedOrOwner(msg.sender), ExceptionsLibrary.FORBIDDEN);

        curveAdapter = curveAdapter_;
        convexAdapter = convexAdapter_;
    }

    // -------------------  INTERNAL, VIEW  -----------------------
    function _isReclaimForbidden(address token) internal view override returns (bool) {
        uint256 len = _vaultTokens.length;
        for (uint256 i = 0; i < len; ++i) {
            if (token == _vaultTokens[i]) {
                return true;
            }
        }
        return false;
    }

    function _getTvl(address vault) internal view returns (uint256) {
        (uint256[] memory vaultTvls, ) = IGearboxVault(vault).tvl();
        return vaultTvls[0];
    }

    // -------------------  INTERNAL, MUTATING  -------------------

    function _push(uint256[] memory tokenAmounts, bytes memory)
        internal
        override
        returns (uint256[] memory actualTokenAmounts)
    {
        totalDeposited += tokenAmounts[0];
        return tokenAmounts;
    }

    function _pull(
        address to,
        uint256[] memory tokenAmounts,
        bytes memory options
    ) internal override returns (uint256[] memory actualTokenAmounts) {
        actualTokenAmounts = new uint256[](tokenAmounts.length);
        uint256[] memory pushTokenAmounts = new uint256[](tokenAmounts.length);
        address[] memory tokens = _vaultTokens;
        IVaultRegistry registry = _vaultGovernance.internalParams().registry;
        address owner = registry.ownerOf(_nft);

        for (uint256 i = 0; i < tokenAmounts.length; ++i) {
            IERC20 vaultToken = IERC20(tokens[i]);
            uint256 balance = vaultToken.balanceOf(address(this));
            uint256 amount = tokenAmounts[i] < balance ? tokenAmounts[i] : balance;
            IERC20(tokens[i]).safeTransfer(to, amount);
            actualTokenAmounts[i] = amount;
            if (owner != to) {
                // this will equal to amounts pulled + any accidental prior balances on `to`;
                pushTokenAmounts[i] = IERC20(tokens[i]).balanceOf(to);
            }
        }
        if (owner != to) {
            // if we pull as a strategy, make sure everything is pushed
            IIntegrationVault(to).push(tokens, pushTokenAmounts, options);
            // any accidental prior balances + push leftovers
            uint256[] memory reclaimed = IIntegrationVault(to).reclaimTokens(tokens);
            for (uint256 i = 0; i < tokenAmounts.length; i++) {
                // equals to exactly how much is pushed
                actualTokenAmounts[i] = actualTokenAmounts[i] >= reclaimed[i]
                    ? actualTokenAmounts[i] - reclaimed[i]
                    : 0;
            }
        }
    }

    function _adjustParameters(address addr, int256 sign) internal {

        IGearboxVault vault = IGearboxVault(addr);
        GearboxHelper helper = vault.helper();

        ICreditAccount ca = ICreditAccount(vault.getCreditAccount());
        if (address(ca) == address(0)) {
            return;
        }
        IConvexV1BaseRewardPoolAdapter convexAdapterContract = IConvexV1BaseRewardPoolAdapter(convexAdapter);

        totalConvexLpTokens = uint256(int256(totalConvexLpTokens) + sign * int256(IERC20(helper.convexOutputToken()).balanceOf(address(ca))));

        uint256 borrowedAmount = ca.borrowedAmount();
        totalBorrowedAmount = uint256(int256(totalBorrowedAmount) + sign * int256(borrowedAmount));
        cumulativeSumRAY = uint256(int256(cumulativeSumRAY) + sign * int256(FullMath.mulDiv(borrowedAmount, D27, ca.cumulativeIndexAtOpen())));

        totalEarnedCRV = uint256(int256(totalEarnedCRV) + sign * int256(convexAdapterContract.rewards(address(ca))));
        cumulativeSumCRV = uint256(int256(cumulativeSumCRV) + sign * int256(convexAdapterContract.balanceOf(address(ca))));
        cumulativeSubCRV = uint256(int256(cumulativeSubCRV) + sign * int256(convexAdapterContract.balanceOf(address(ca)) * convexAdapterContract.userRewardPerTokenPaid(address(ca))));

        IBaseRewardPool underlyingContract = IBaseRewardPool(vault.creditManager().adapterToContract(convexAdapter));
        if (underlyingContract.extraRewardsLength() > 0) {
            IBaseRewardPool rewardsContract = IBaseRewardPool(underlyingContract.extraRewards(0));
            totalEarnedLDO = uint256(int256(totalEarnedLDO) + sign * int256(rewardsContract.rewards(address(ca))));
            cumulativeSumLDO = uint256(int256(cumulativeSumLDO) + sign * int256(rewardsContract.balanceOf(address(ca))));
            cumulativeSubLDO = uint256(int256(cumulativeSubLDO) + sign * int256(rewardsContract.balanceOf(address(ca)) * rewardsContract.userRewardPerTokenPaid(address(ca))));
        }
    }

    function _depositTo(uint256 index, uint256 mask, uint256 amount, uint256 status) internal returns (uint256, uint256) {

        IGearboxVault vault = IGearboxVault(subvaultsList[index]);

        _adjustParameters(subvaultsList[index], -1);

        if (status == EMPTY) {
            (uint256 minBorrowingLimit, ) = vault.creditFacade().limits();
            uint256 minimalNecessaryAmount = FullMath.mulDiv(minBorrowingLimit, D9, (vault.marginalFactorD9() - D9)) + 1;
            if (amount < minimalNecessaryAmount) {
                return (mask, amount);
            }
        }

        else {
            mask ^= (PARTIAL << (2 * index));
        }

        uint256 vaultTvl = _getTvl(subvaultsList[index]);
        uint256 limit = limitsList[index];

        if (vaultTvl >= limit) {
            return (mask, amount);
        }

        uint256 toDeposit = limit - vaultTvl;
        if (amount < toDeposit) {
            toDeposit = amount;
        }

        IERC20(_vaultTokens[0]).safeTransfer(address(vault), toDeposit);
        vault.manualPush();
        if (status == EMPTY) {
            vault.openCreditAccount(curveAdapter, convexAdapter);
        }

        vault.adjustPosition();

        _adjustParameters(subvaultsList[index], 1);
        if (toDeposit == limit - vaultTvl) {
            mask |= (FULL << (2 * index));
            return (mask, amount - toDeposit);
        }

        mask |= (PARTIAL << (2 * index));
        return (mask, 0);
    }


    function _makeSorted() internal {
        uint256 len = subvaultsList.length;
        for (uint256 i = 1; i < len; ++i) {
            if (limitsList[i] < limitsList[i - 1]) {
                (limitsList[i - 1], limitsList[i]) = (limitsList[i], limitsList[i - 1]);
                (subvaultsList[i - 1], subvaultsList[i]) = (subvaultsList[i], subvaultsList[i - 1]);
            }
        }

        for (uint256 i = len; i > 1; --i) {
            if (limitsList[i - 1] < limitsList[i - 2]) {
                (limitsList[i - 1], limitsList[i - 2]) = (limitsList[i - 2], limitsList[i - 1]);
                (subvaultsList[i - 1], subvaultsList[i - 2]) = (subvaultsList[i - 2], subvaultsList[i - 1]);
            }
        }
    }

    /// @inheritdoc IntegrationVault
    function supportsInterface(bytes4 interfaceId) public view override(IERC165, IntegrationVault) returns (bool) {
        return super.supportsInterface(interfaceId) || (interfaceId == type(IGearboxERC20Vault).interfaceId) || (interfaceId == type(IERC20Vault).interfaceId);
    }
}
