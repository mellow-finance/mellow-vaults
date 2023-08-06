// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../interfaces/vaults/IBalancerV2Vault.sol";
import "../interfaces/vaults/IBalancerV2VaultGovernance.sol";
import "../libraries/ExceptionsLibrary.sol";
import "./IntegrationVault.sol";

contract BalancerV2Vault is IBalancerV2Vault, IntegrationVault {
    using SafeERC20 for IERC20;

    uint256 public constant D9 = 10 ** 9;

    IManagedPool public pool;
    IBalancerVault public balancerVault;

    IStakingLiquidityGauge public stakingLiquidityGauge;
    IBalancerMinter public balancerMinter;

    /// @inheritdoc IVault
    function tvl() public view returns (uint256[] memory minTokenAmounts, uint256[] memory maxTokenAmounts) {
        bytes32 poolId = pool.getPoolId();
        (IBalancerERC20[] memory poolTokens, uint256[] memory amounts, ) = balancerVault.getPoolTokens(poolId);

        uint256 totalSupply = pool.getActualSupply();
        uint256 balance = IBalancerERC20(address(pool)).balanceOf(address(this));
        IStakingLiquidityGauge stakingLiquidityGauge_ = stakingLiquidityGauge;
        if (address(0) != address(stakingLiquidityGauge_)) {
            balance += stakingLiquidityGauge_.balanceOf(address(this));
        }

        minTokenAmounts = new uint256[](poolTokens.length);
        for (uint256 i = 0; i < minTokenAmounts.length; i++) {
            minTokenAmounts[i] = FullMath.mulDiv(amounts[i], balance, totalSupply);
        }

        maxTokenAmounts = minTokenAmounts;
    }

    /// @inheritdoc IntegrationVault
    function supportsInterface(bytes4 interfaceId) public view override(IERC165, IntegrationVault) returns (bool) {
        return super.supportsInterface(interfaceId) || (interfaceId == type(IBalancerV2Vault).interfaceId);
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
        pool = IManagedPool(pool_);
        balancerVault = IBalancerVault(balancerVault_);
        balancerMinter = IBalancerMinter(balancerMinter_);
        stakingLiquidityGauge = IStakingLiquidityGauge(stakingLiquidityGauge_);
        (IBalancerERC20[] memory poolTokens, , ) = balancerVault.getPoolTokens(pool.getPoolId());
        IERC20(address(pool)).safeApprove(address(stakingLiquidityGauge), type(uint256).max);

        require(vaultTokens_.length == poolTokens.length, ExceptionsLibrary.INVALID_VALUE);
        for (uint256 i = 0; i < poolTokens.length; i++) {
            require(address(poolTokens[i]) == vaultTokens_[i], ExceptionsLibrary.INVALID_TOKEN);
        }

        _initialize(vaultTokens_, nft_);
    }

    /// @inheritdoc IBalancerV2Vault
    function getPriceToUSDX96(IAggregatorV3 oracle, IAsset token) public view returns (uint256 priceX96) {
        (, int256 usdPrice, , , ) = oracle.latestRoundData();

        uint8 tokenDecimals = IERC20Metadata(address(token)).decimals();
        uint8 oracleDecimals = oracle.decimals();
        priceX96 = FullMath.mulDiv(2 ** 96 * 10 ** 6, uint256(usdPrice), 10 ** (oracleDecimals + tokenDecimals));
    }

    /// @inheritdoc IBalancerV2Vault
    function claimRewards() external returns (uint256 amount) {
        amount = balancerMinter.mint(address(this));

        IBalancerV2VaultGovernance.StrategyParams memory rewardSwapParams_ = IBalancerV2VaultGovernance(
            address(_vaultGovernance)
        ).strategyParams(_nft);

        int256[] memory limits = new int256[](rewardSwapParams_.assets.length);

        uint256 rewardToUSDCPriceX96 = getPriceToUSDX96(rewardSwapParams_.rewardOracle, rewardSwapParams_.assets[0]);
        uint256 underlyingToUSDCPriceX96 = getPriceToUSDX96(
            rewardSwapParams_.underlyingOracle,
            rewardSwapParams_.assets[limits.length - 1]
        );

        uint256 minAmountOut = FullMath.mulDiv(amount, rewardToUSDCPriceX96, underlyingToUSDCPriceX96);
        minAmountOut = FullMath.mulDiv(minAmountOut, D9 - rewardSwapParams_.slippageD, D9);

        limits[0] = int256(amount);
        limits[limits.length - 1] = -int256(minAmountOut);
        rewardSwapParams_.swaps[0].amount = amount;

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
        bytes memory
    ) internal override returns (uint256[] memory actualTokenAmounts) {
        bytes32 poolId = pool.getPoolId();
        (IBalancerERC20[] memory poolTokens, , ) = balancerVault.getPoolTokens(poolId);
        IAsset[] memory tokens = new IAsset[](poolTokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            tokens[i] = IAsset(address(poolTokens[i]));
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

        actualTokenAmounts = tokenAmounts;
        stakingLiquidityGauge.deposit(IBalancerERC20(address(pool)).balanceOf(address(this)), address(this));
    }

    function _pull(
        address to,
        uint256[] memory tokenAmounts,
        bytes memory
    ) internal override returns (uint256[] memory actualTokenAmounts) {
        actualTokenAmounts = new uint256[](tokenAmounts.length);

        bytes32 poolId = pool.getPoolId();
        (IBalancerERC20[] memory poolTokens, uint256[] memory amounts, ) = balancerVault.getPoolTokens(poolId);
        uint256 balance = stakingLiquidityGauge.balanceOf(address(this));
        uint256 liquidityToPull = 0;
        {
            uint256 totalSupply = pool.getActualSupply();
            for (uint256 i = 0; i < poolTokens.length; i++) {
                if (amounts[i] == 0) continue;
                uint256 lpAmount = FullMath.mulDiv(tokenAmounts[i], totalSupply, amounts[i]);
                if (liquidityToPull < lpAmount) {
                    liquidityToPull = lpAmount;
                }
            }

            if (liquidityToPull > balance) {
                liquidityToPull = balance;
            }

            for (uint256 i = 0; i < poolTokens.length; i++) {
                if (amounts[i] == 0) continue;
                actualTokenAmounts[i] = FullMath.mulDiv(amounts[i], liquidityToPull, totalSupply);
            }
        }

        stakingLiquidityGauge.withdraw(liquidityToPull);

        IAsset[] memory tokens = new IAsset[](poolTokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            tokens[i] = IAsset(address(poolTokens[i]));
        }

        balancerVault.exitPool(
            poolId,
            address(this),
            payable(to),
            IBalancerVault.ExitPoolRequest({
                assets: tokens,
                minAmountsOut: new uint256[](poolTokens.length),
                userData: abi.encode(
                    WeightedPoolUserData.ExitKind.EXACT_BPT_IN_FOR_TOKENS_OUT,
                    liquidityToPull,
                    uint256(0)
                ),
                toInternalBalance: false
            })
        );
    }
}
