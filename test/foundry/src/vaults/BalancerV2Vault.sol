// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../interfaces/vaults/IBalancerV2Vault.sol";
import "../interfaces/vaults/IBalancerV2VaultGovernance.sol";
import "../libraries/ExceptionsLibrary.sol";
import "./IntegrationVault.sol";

contract BalancerV2Vault is IBalancerV2Vault, IntegrationVault {
    using SafeERC20 for IERC20;

    uint256 public constant D9 = 10 ** 9;
    uint256 public constant Q96 = 2 ** 96;

    IManagedPool public pool;
    IBalancerVault public balancerVault;

    IStakingLiquidityGauge public stakingLiquidityGauge;
    IBalancerMinter public balancerMinter;

    // -------------------  EXTERNAL, VIEW  -------------------

    // TODO: add claim from stakingLiquidityGauge reward tokens

    /// @inheritdoc IVault
    function tvl() public view returns (uint256[] memory minTokenAmounts, uint256[] memory maxTokenAmounts) {
        bytes32 poolId = pool.getPoolId();
        (IBalancerERC20[] memory poolTokens, uint256[] memory amounts, ) = balancerVault.getPoolTokens(poolId);
        minTokenAmounts = new uint256[](poolTokens.length);

        uint256 totalSupply = pool.getActualSupply();
        if (totalSupply > 0) {
            uint256 balance = stakingLiquidityGauge.balanceOf(address(this));
            balance += IERC20(address(pool)).balanceOf(address(this));
            for (uint256 i = 0; i < poolTokens.length; i++) {
                minTokenAmounts[i] = FullMath.mulDiv(amounts[i], balance, totalSupply);
            }
        }

        maxTokenAmounts = minTokenAmounts;
    }

    /// @inheritdoc IntegrationVault
    function supportsInterface(bytes4 interfaceId) public view override(IERC165, IntegrationVault) returns (bool) {
        return super.supportsInterface(interfaceId) || (interfaceId == type(IBalancerV2Vault).interfaceId);
    }

    /// @inheritdoc IBalancerV2Vault
    function getPriceToUSDX96(IAggregatorV3 oracle, IAsset token) public view returns (uint256 priceX96) {
        (, int256 usdPrice, , , ) = oracle.latestRoundData();

        uint8 tokenDecimals = IERC20Metadata(address(token)).decimals();
        uint8 oracleDecimals = oracle.decimals();
        priceX96 = FullMath.mulDiv(2 ** 96 * 10 ** 6, uint256(usdPrice), 10 ** (oracleDecimals + tokenDecimals));
    }

    // -------------------  EXTERNAL, MUTATING  -------------------

    /// @inheritdoc IBalancerV2Vault
    function initialize(
        uint256 nft_,
        address[] memory vaultTokens_,
        address pool_,
        address balancerVault_,
        address stakingLiquidityGauge_,
        address balancerMinter_
    ) external {
        require(
            pool_ != address(0) &&
                balancerVault_ != address(0) &&
                stakingLiquidityGauge_ != address(0) &&
                balancerMinter_ != address(0),
            ExceptionsLibrary.ADDRESS_ZERO
        );
        pool = IManagedPool(pool_);
        balancerVault = IBalancerVault(balancerVault_);
        balancerMinter = IBalancerMinter(balancerMinter_);
        stakingLiquidityGauge = IStakingLiquidityGauge(stakingLiquidityGauge_);
        (IBalancerERC20[] memory poolTokens, , ) = balancerVault.getPoolTokens(pool.getPoolId());
        require(vaultTokens_.length == poolTokens.length, ExceptionsLibrary.INVALID_VALUE);
        for (uint256 i = 0; i < poolTokens.length; i++) {
            require(address(poolTokens[i]) == vaultTokens_[i], ExceptionsLibrary.INVALID_TOKEN);
            IERC20(address(poolTokens[i])).safeApprove(address(balancerVault_), type(uint256).max);
        }
        IERC20(address(pool)).safeApprove(address(stakingLiquidityGauge), type(uint256).max);

        _initialize(vaultTokens_, nft_);
    }

    /// @inheritdoc IBalancerV2Vault
    function claimRewards() external returns (uint256 amount) {
        amount = balancerMinter.mint(address(stakingLiquidityGauge));
        if (amount == 0) {
            return 0;
        }

        IBalancerV2VaultGovernance.StrategyParams memory rewardSwapParams_ = IBalancerV2VaultGovernance(
            address(_vaultGovernance)
        ).strategyParams(_nft);

        int256[] memory limits = new int256[](rewardSwapParams_.assets.length);

        uint256 rewardToUSDPriceX96 = getPriceToUSDX96(rewardSwapParams_.rewardOracle, rewardSwapParams_.assets[0]);
        uint256 underlyingToUSDPriceX96 = getPriceToUSDX96(
            rewardSwapParams_.underlyingOracle,
            rewardSwapParams_.assets[limits.length - 1]
        );

        uint256 minAmountOut = FullMath.mulDiv(amount, rewardToUSDPriceX96, underlyingToUSDPriceX96);
        minAmountOut = FullMath.mulDiv(minAmountOut, D9 - rewardSwapParams_.slippageD, D9);

        limits[0] = int256(amount);
        limits[limits.length - 1] = -int256(minAmountOut);
        rewardSwapParams_.swaps[0].amount = amount;

        IERC20(address(rewardSwapParams_.assets[0])).safeIncreaseAllowance(address(balancerVault), amount);
        /// throws BAL#507 in case of insufficient amount of tokenOut
        int256[] memory swappedAmounts = balancerVault.batchSwap(
            IBalancerVault.SwapKind.GIVEN_IN,
            rewardSwapParams_.swaps,
            rewardSwapParams_.assets,
            rewardSwapParams_.funds,
            limits,
            type(uint256).max
        );
        return uint256(-swappedAmounts[limits.length - 1]);
    }

    // -------------------  INTERNAL, VIEW  -------------------

    function _isReclaimForbidden(address) internal pure override returns (bool) {
        return false;
    }

    // -------------------  INTERNAL, MUTATING  -------------------

    function _push(
        uint256[] memory tokenAmounts,
        bytes memory opts
    ) internal override returns (uint256[] memory actualTokenAmounts) {
        bytes32 poolId = pool.getPoolId();
        address[] memory vaultTokens_ = _vaultTokens;
        IAsset[] memory tokens = new IAsset[](vaultTokens_.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            tokens[i] = IAsset(vaultTokens_[i]);
        }

        balancerVault.joinPool(
            poolId,
            address(this),
            address(this),
            IBalancerVault.JoinPoolRequest({
                assets: tokens,
                maxAmountsIn: tokenAmounts,
                userData: abi.encode(WeightedPoolUserData.JoinKind.EXACT_TOKENS_IN_FOR_BPT_OUT, tokenAmounts, 0),
                fromInternalBalance: false
            })
        );

        uint256 liquidityAmount = IBalancerERC20(address(pool)).balanceOf(address(this));
        if (opts.length > 0) {
            require(liquidityAmount >= abi.decode(opts, (uint256)), ExceptionsLibrary.LIMIT_UNDERFLOW);
        }
        actualTokenAmounts = tokenAmounts;
        stakingLiquidityGauge.deposit(liquidityAmount, address(this));
    }

    function _pull(
        address to,
        uint256[] memory tokenAmounts,
        bytes memory opts
    ) internal override returns (uint256[] memory actualTokenAmounts) {
        actualTokenAmounts = new uint256[](tokenAmounts.length);
        stakingLiquidityGauge.withdraw(stakingLiquidityGauge.balanceOf(address(this)));

        bytes32 poolId = pool.getPoolId();
        (IBalancerERC20[] memory poolTokens, uint256[] memory amounts, ) = balancerVault.getPoolTokens(poolId);

        uint256 ratioX96 = 0;
        IAsset[] memory tokens = new IAsset[](poolTokens.length);
        {
            for (uint256 i = 0; i < tokens.length; i++) {
                tokens[i] = IAsset(address(poolTokens[i]));
                uint256 currentRatioX96 = FullMath.mulDiv(tokenAmounts[i], Q96, amounts[i]);
                if (ratioX96 < currentRatioX96) {
                    ratioX96 = currentRatioX96;
                }
            }
        }
        for (uint256 i = 0; i < actualTokenAmounts.length; i++) {
            actualTokenAmounts[i] = FullMath.mulDiv(ratioX96, amounts[i], Q96);
        }

        balancerVault.exitPool(
            poolId,
            address(this),
            payable(to),
            IBalancerVault.ExitPoolRequest({
                assets: tokens,
                minAmountsOut: actualTokenAmounts,
                userData: abi.encode(
                    WeightedPoolUserData.ExitKind.BPT_IN_FOR_EXACT_TOKENS_OUT,
                    actualTokenAmounts,
                    type(uint256).max
                ),
                toInternalBalance: false
            })
        );

        stakingLiquidityGauge.deposit(IERC20(address(pool)).balanceOf(address(this)), address(this));
    }
}
