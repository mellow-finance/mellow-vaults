// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../interfaces/vaults/IAuraVault.sol";
import "../interfaces/vaults/IAuraVaultGovernance.sol";
import "../libraries/ExceptionsLibrary.sol";
import "./IntegrationVault.sol";

contract AuraVault is IAuraVault, IntegrationVault {
    using SafeERC20 for IERC20;

    uint256 public constant D9 = 10**9;
    uint256 public constant Q96 = 2**96;

    IManagedPool public pool;
    IBalancerVault public balancerVault;

    IAuraBaseRewardPool public auraBaseRewardPool;
    IAuraBooster public auraBooster;

    // -------------------  EXTERNAL, VIEW  -------------------

    /// @inheritdoc IVault
    function tvl() public view returns (uint256[] memory minTokenAmounts, uint256[] memory maxTokenAmounts) {
        bytes32 poolId = pool.getPoolId();
        (IBalancerERC20[] memory poolTokens, uint256[] memory amounts, ) = balancerVault.getPoolTokens(poolId);
        minTokenAmounts = new uint256[](poolTokens.length - 1);

        uint256 totalSupply = pool.getActualSupply();
        uint256 j = 0;
        if (totalSupply > 0) {
            uint256 balance = auraBaseRewardPool.balanceOf(address(this));
            balance += IERC20(address(pool)).balanceOf(address(this));
            for (uint256 i = 0; i < poolTokens.length; i++) {
                if (address(poolTokens[i]) == address(pool)) continue;
                minTokenAmounts[j] = FullMath.mulDiv(amounts[i], balance, totalSupply);
                j++;
            }
        }

        maxTokenAmounts = minTokenAmounts;
    }

    /// @inheritdoc IntegrationVault
    function supportsInterface(bytes4 interfaceId) public view override(IERC165, IntegrationVault) returns (bool) {
        return super.supportsInterface(interfaceId) || (interfaceId == type(IAuraVault).interfaceId);
    }

    /// @inheritdoc IAuraVault
    function getPriceToUSDX96(IAggregatorV3 oracle, IAsset token) public view returns (uint256 priceX96) {
        (, int256 usdPrice, , , ) = oracle.latestRoundData();

        uint8 tokenDecimals = IERC20Metadata(address(token)).decimals();
        uint8 oracleDecimals = oracle.decimals();
        priceX96 = FullMath.mulDiv(2**96 * 10**6, uint256(usdPrice), 10**(oracleDecimals + tokenDecimals));
    }

    // -------------------  EXTERNAL, MUTATING  -------------------

    /// @inheritdoc IAuraVault
    function initialize(
        uint256 nft_,
        address[] memory vaultTokens_,
        address pool_,
        address balancerVault_,
        address auraBooster_,
        address auraBaseRewardPool_
    ) external {
        require(
            pool_ != address(0) &&
                balancerVault_ != address(0) &&
                auraBaseRewardPool_ != address(0) &&
                auraBooster_ != address(0),
            ExceptionsLibrary.ADDRESS_ZERO
        );
        pool = IManagedPool(pool_);
        balancerVault = IBalancerVault(balancerVault_);
        auraBooster = IAuraBooster(auraBooster_);
        auraBaseRewardPool = IAuraBaseRewardPool(auraBaseRewardPool_);
        (IBalancerERC20[] memory poolTokens, , ) = balancerVault.getPoolTokens(pool.getPoolId());
        require(vaultTokens_.length + 1 == poolTokens.length, ExceptionsLibrary.INVALID_VALUE);
        uint256 j = 0;
        for (uint256 i = 0; i < poolTokens.length; i++) {
            address poolToken = address(poolTokens[i]);
            if (poolToken == vaultTokens_[j]) {
                j++;
                IERC20(poolToken).safeApprove(address(balancerVault_), type(uint256).max);
            } else {
                require(poolToken == pool_, ExceptionsLibrary.INVALID_TOKEN);
            }
        }
        IERC20(pool_).safeApprove(address(auraBooster_), type(uint256).max);

        _initialize(vaultTokens_, nft_);
    }

    /// @inheritdoc IAuraVault
    function claimRewards() external returns (uint256 addedAmount) {
        auraBaseRewardPool.getReward();
        IAuraVaultGovernance.SwapParams[] memory swapParams = IAuraVaultGovernance(address(_vaultGovernance))
            .strategyParams(_nft)
            .tokensSwapParams;

        for (uint256 i = 0; i < swapParams.length; i++) {
            addedAmount += _swapRewardToken(swapParams[i]);
        }

        return addedAmount;
    }

    // -------------------  INTERNAL, VIEW  -------------------

    function _isReclaimForbidden(address) internal pure override returns (bool) {
        return false;
    }

    function _isStrategy(address addr) internal view returns (bool) {
        return _vaultGovernance.internalParams().registry.getApproved(_nft) == addr;
    }

    // -------------------  INTERNAL, MUTATING  -------------------

    function _swapRewardToken(IAuraVaultGovernance.SwapParams memory params) private returns (uint256 addedAmount) {
        address rewardToken = address(params.assets[0]);
        uint256 amount = IERC20(rewardToken).balanceOf(address(this));
        if (amount == 0) return 0;

        int256[] memory limits = new int256[](params.assets.length);

        uint256 rewardToUSDPriceX96 = getPriceToUSDX96(params.rewardOracle, params.assets[0]);
        uint256 underlyingToUSDPriceX96 = getPriceToUSDX96(params.underlyingOracle, params.assets[limits.length - 1]);

        uint256 minAmountOut = FullMath.mulDiv(amount, rewardToUSDPriceX96, underlyingToUSDPriceX96);
        minAmountOut = FullMath.mulDiv(minAmountOut, D9 - params.slippageD, D9);

        limits[0] = int256(amount);
        limits[limits.length - 1] = -int256(minAmountOut);
        params.swaps[0].amount = amount;

        IERC20(rewardToken).safeIncreaseAllowance(address(balancerVault), amount);
        /// throws BAL#507 in case of insufficient amount of tokenOut
        int256[] memory swappedAmounts = balancerVault.batchSwap(
            IBalancerVault.SwapKind.GIVEN_IN,
            params.swaps,
            params.assets,
            params.funds,
            limits,
            type(uint256).max
        );
        return uint256(-swappedAmounts[limits.length - 1]);
    }

    function _push(uint256[] memory tokenAmounts, bytes memory opts)
        internal
        override
        returns (uint256[] memory actualTokenAmounts)
    {
        bytes32 poolId = pool.getPoolId();
        IAsset[] memory tokens;
        uint256[] memory maxAmountsIn;
        {
            (IBalancerERC20[] memory poolTokens, , ) = balancerVault.getPoolTokens(poolId);
            maxAmountsIn = new uint256[](poolTokens.length);
            tokens = new IAsset[](poolTokens.length);
            uint256 j = 0;
            for (uint256 i = 0; i < poolTokens.length; i++) {
                tokens[i] = IAsset(address(poolTokens[i]));
                if (address(poolTokens[i]) == address(pool)) {
                    continue;
                } else {
                    maxAmountsIn[i] = tokenAmounts[j];
                    j++;
                }
            }
        }

        balancerVault.joinPool(
            poolId,
            address(this),
            address(this),
            IBalancerVault.JoinPoolRequest({
                assets: tokens,
                maxAmountsIn: maxAmountsIn,
                userData: abi.encode(StablePoolUserData.JoinKind.EXACT_TOKENS_IN_FOR_BPT_OUT, tokenAmounts, 0),
                fromInternalBalance: false
            })
        );

        uint256 liquidityAmount = IBalancerERC20(address(pool)).balanceOf(address(this));
        if (opts.length > 0) {
            require(liquidityAmount >= abi.decode(opts, (uint256)), ExceptionsLibrary.LIMIT_UNDERFLOW);
        }

        actualTokenAmounts = tokenAmounts;
        auraBooster.deposit(auraBaseRewardPool.pid(), liquidityAmount, true);
    }

    function _pull(
        address to,
        uint256[] memory tokenAmounts,
        bytes memory
    ) internal override returns (uint256[] memory actualTokenAmounts) {
        actualTokenAmounts = new uint256[](tokenAmounts.length);
        auraBaseRewardPool.withdrawAllAndUnwrap(false);

        bytes32 poolId = pool.getPoolId();
        (IBalancerERC20[] memory poolTokens, uint256[] memory amounts, ) = balancerVault.getPoolTokens(poolId);

        uint256 ratioX96 = 0;
        {
            uint256 j = 0;
            for (uint256 i = 0; i < poolTokens.length; i++) {
                if (address(pool) == address(poolTokens[i])) continue;
                uint256 currentRatioX96 = FullMath.mulDiv(tokenAmounts[j], Q96, amounts[i]);
                j++;
                if (ratioX96 < currentRatioX96) {
                    ratioX96 = currentRatioX96;
                }
            }
        }
        {
            uint256 j = 0;
            for (uint256 i = 0; i < poolTokens.length; i++) {
                if (address(pool) == address(poolTokens[i])) continue;
                actualTokenAmounts[j] = FullMath.mulDiv(ratioX96, amounts[i], Q96);
                j++;
            }
        }

        uint256[] memory minAmountsOut = new uint256[](poolTokens.length);
        IAsset[] memory tokens = new IAsset[](poolTokens.length);
        {
            uint256 j = 0;
            for (uint256 i = 0; i < poolTokens.length; i++) {
                tokens[i] = IAsset(address(poolTokens[i]));
                if (address(poolTokens[i]) == address(pool)) {
                    continue;
                }
                minAmountsOut[i] = actualTokenAmounts[j];
                j++;
            }
        }

        balancerVault.exitPool(
            poolId,
            address(this),
            payable(to),
            IBalancerVault.ExitPoolRequest({
                assets: tokens,
                minAmountsOut: minAmountsOut,
                userData: abi.encode(
                    StablePoolUserData.ExitKind.BPT_IN_FOR_EXACT_TOKENS_OUT,
                    actualTokenAmounts,
                    type(uint256).max
                ),
                toInternalBalance: false
            })
        );

        auraBooster.deposit(auraBaseRewardPool.pid(), IERC20(address(pool)).balanceOf(address(this)), true);
    }
}
