// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.9;

import "../interfaces/external/quickswap/IAlgebraEternalFarming.sol";
import "../interfaces/external/quickswap/IFarmingCenter.sol";
import "../interfaces/external/quickswap/ISwapRouter.sol";
import "../interfaces/external/quickswap/PoolAddress.sol";
import "../interfaces/vaults/IQuickSwapVault.sol";
import "../interfaces/vaults/IQuickSwapVaultGovernance.sol";

import "../libraries/ExceptionsLibrary.sol";
import "../utils/QuickSwapHelper.sol";
import "./IntegrationVault.sol";

/// @notice Vault that interfaces QuickSwap protocol in the integration layer.
contract QuickSwapVault is IQuickSwapVault, IntegrationVault {
    using SafeERC20 for IERC20;
    uint256 public constant Q96 = 2**96;
    uint256 public constant D9 = 10**9;

    uint256 public positionNft;
    address public erc20Vault; // zero-vault

    IFarmingCenter public immutable farmingCenter;
    ISwapRouter public immutable swapRouter;
    INonfungiblePositionManager public immutable positionManager;
    QuickSwapHelper public immutable helper;

    // -------------------  EXTERNAL, MUTATING  -------------------

    constructor(
        INonfungiblePositionManager positionManager_,
        QuickSwapHelper helper_,
        ISwapRouter swapRouter_,
        IFarmingCenter farmingCenter_
    ) {
        positionManager = positionManager_;
        helper = helper_;
        swapRouter = swapRouter_;
        farmingCenter = farmingCenter_;
    }

    /// @inheritdoc IQuickSwapVault
    function initialize(
        uint256 nft_,
        address erc20Vault_,
        address[] memory vaultTokens_
    ) external {
        require(vaultTokens_.length == 2, ExceptionsLibrary.INVALID_VALUE);
        erc20Vault = erc20Vault_;
        _initialize(vaultTokens_, nft_);
    }

    /// @inheritdoc IERC721Receiver
    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes memory
    ) external returns (bytes4) {
        IFarmingCenter farmingCenter_ = farmingCenter;
        if (msg.sender == address(positionManager)) {
            require(_isStrategy(operator), ExceptionsLibrary.FORBIDDEN);
            (, , address token0, address token1, , , , , , , ) = positionManager.positions(tokenId);
            require(token0 == _vaultTokens[0] && token1 == _vaultTokens[1], ExceptionsLibrary.INVALID_TOKEN);

            uint256 positionNft_ = positionNft;
            if (positionNft_ != 0) {
                (, , , , , , uint128 liquidity, , , , ) = positionManager.positions(positionNft_);
                require(liquidity == 0, ExceptionsLibrary.INVALID_VALUE);
                (uint256 farmingNft, , , ) = farmingCenter_.deposits(positionNft_);
                require(farmingNft == 0, ExceptionsLibrary.INVALID_VALUE);
                positionManager.transferFrom(address(this), from, positionNft_);
            }

            positionNft_ = tokenId;
            (, , uint256 fromPositionNft) = farmingCenter_.l2Nfts(tokenId);
            require(fromPositionNft == positionNft_ && address(this) == operator, ExceptionsLibrary.FORBIDDEN);
            IIncentiveKey.IncentiveKey memory key_ = IQuickSwapVaultGovernance(address(_vaultGovernance))
                .delayedStrategyParams(_nft)
                .key;
            _enterFarming(key_);
            positionNft = positionNft_;
        } else {
            revert(ExceptionsLibrary.FORBIDDEN);
        }
        return this.onERC721Received.selector;
    }

    function burnFarmingPosition() public {
        _isApprovedOrOwner(msg.sender);
        uint256 positionNft_ = positionNft;
        IFarmingCenter farmingCenter_ = farmingCenter;
        IQuickSwapVaultGovernance.DelayedStrategyParams memory strategyParams = IQuickSwapVaultGovernance(
            address(_vaultGovernance)
        ).delayedStrategyParams(_nft);
        collectRewards();
        farmingCenter_.exitFarming(
            strategyParams.key,
            positionNft_,
            false // eternal farming
        );
        farmingCenter_.withdrawToken(positionNft_, address(this), "");
    }

    /// @dev collects all fees from positionNft and transfers to erc20Vault
    function collectFees() external nonReentrant returns (uint256[] memory collectedFees) {
        uint256 positionNft_ = positionNft;
        if (positionNft_ == 0) return new uint256[](2);
        collectedFees = new uint256[](2);
        // collect all fees from position
        collectedFees = new uint256[](2);
        (uint256 collectedFees0, uint256 collectedFees1) = farmingCenter.collect(
            INonfungiblePositionManager.CollectParams({
                tokenId: positionNft_,
                recipient: erc20Vault,
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            })
        );
        collectedFees[0] = collectedFees0;
        collectedFees[1] = collectedFees1;
    }

    /// @dev collects all rewards from farming position and transfers to erc20Vault
    function collectRewards() public returns (uint256 rewardTokenAmount, uint256 bonusRewardTokenAmount) {
        _isApprovedOrOwner(msg.sender);
        uint256 positionNft_ = positionNft;
        IFarmingCenter farmingCenter_ = farmingCenter;
        (uint256 farmingNft, , , ) = farmingCenter_.deposits(positionNft_);
        if (farmingNft != 0) {
            IQuickSwapVaultGovernance.DelayedStrategyParams memory strategyParams = IQuickSwapVaultGovernance(
                address(_vaultGovernance)
            ).delayedStrategyParams(_nft);
            IIncentiveKey.IncentiveKey memory key = strategyParams.key;
            (rewardTokenAmount, bonusRewardTokenAmount) = helper.calculateCollectableRewards(
                farmingCenter_.eternalFarming(),
                key,
                positionNft_
            );
            if (rewardTokenAmount + bonusRewardTokenAmount == 0) {
                // nothing to collect
                return (0, 0);
            }
            farmingCenter_.collectRewards(key, positionNft_);
            rewardTokenAmount = farmingCenter_.claimReward(key.rewardToken, address(erc20Vault), 0, type(uint256).max);
            bonusRewardTokenAmount = farmingCenter_.claimReward(
                key.bonusRewardToken,
                address(this),
                0,
                type(uint256).max
            );
            {
                uint256 amount = _swapTokenToUnderlying(
                    rewardTokenAmount,
                    strategyParams.key.rewardToken,
                    strategyParams.rewardTokenToUnderlying,
                    strategyParams.swapSlippageD
                );
                IERC20Minimal(strategyParams.rewardTokenToUnderlying).transfer(address(erc20Vault), amount);
            }
            {
                uint256 amount = _swapTokenToUnderlying(
                    bonusRewardTokenAmount,
                    key.bonusRewardToken,
                    strategyParams.bonusTokenToUnderlying,
                    strategyParams.swapSlippageD
                );
                IERC20Minimal(strategyParams.bonusTokenToUnderlying).transfer(address(erc20Vault), amount);
            }
        }
    }

    // -------------------   EXTERNAL, VIEW   -------------------

    /// @inheritdoc IVault
    function tvl() public view returns (uint256[] memory minTokenAmounts, uint256[] memory maxTokenAmounts) {
        minTokenAmounts = helper.calculateTvl(
            positionNft,
            IQuickSwapVaultGovernance(address(_vaultGovernance)).delayedStrategyParams(_nft),
            farmingCenter,
            _vaultTokens[0]
        );
        maxTokenAmounts = minTokenAmounts;
    }

    /// @inheritdoc IntegrationVault
    function supportsInterface(bytes4 interfaceId) public view override(IERC165, IntegrationVault) returns (bool) {
        return super.supportsInterface(interfaceId) || (interfaceId == type(IQuickSwapVault).interfaceId);
    }

    // -------------------  INTERNAL, VIEW  -------------------

    function _parseOptions(bytes memory options)
        internal
        view
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        if (options.length == 0) return (0, 0, block.timestamp + 1);
        require(options.length == 32 * 3, ExceptionsLibrary.INVALID_VALUE);
        return abi.decode(options, (uint256, uint256, uint256));
    }

    function _isStrategy(address addr) internal view returns (bool) {
        return _vaultGovernance.internalParams().registry.getApproved(_nft) == addr;
    }

    function _isReclaimForbidden(address) internal pure override returns (bool) {
        return false;
    }

    // -------------------  INTERNAL, MUTATING  -------------------

    function _swapTokenToUnderlying(
        uint256 amount,
        IERC20Minimal from,
        address to,
        uint256 swapSlippageD
    ) private returns (uint256 amountOut) {
        if (address(from) == to) return amount;
        address poolDeployer = positionManager.poolDeployer();
        IAlgebraPool pool = IAlgebraPool(
            PoolAddress.computeAddress(poolDeployer, PoolAddress.getPoolKey(address(from), to))
        );
        (uint160 sqrtPriceX96, , , , , , ) = pool.globalState();
        uint256 priceX96 = FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, Q96);
        if (pool.token0() == to) {
            priceX96 = FullMath.mulDiv(Q96, Q96, priceX96);
        }
        uint256 amountOutMinimum = FullMath.mulDiv(amount, priceX96, Q96);
        amountOutMinimum = FullMath.mulDiv(amountOutMinimum, swapSlippageD, D9);
        amountOut = swapRouter.exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: address(from),
                tokenOut: to,
                recipient: address(this),
                deadline: block.timestamp + 1,
                amountIn: amount,
                amountOutMinimum: amountOutMinimum,
                limitSqrtPrice: 0
            })
        );
    }

    function _enterFarming(IIncentiveKey.IncentiveKey memory key) private {
        farmingCenter.enterFarming(
            key,
            positionNft,
            0,
            false // eternal farming
        );
    }

    function _push(uint256[] memory tokenAmounts, bytes memory options)
        internal
        override
        returns (uint256[] memory actualTokenAmounts)
    {
        actualTokenAmounts = new uint256[](2);
        if (positionNft == 0) return actualTokenAmounts;

        (uint160 sqrtRatioX96, , , , , , ) = IQuickSwapVaultGovernance(address(_vaultGovernance))
            .delayedStrategyParams(_nft)
            .key
            .pool
            .globalState();
        uint128 liquidity = helper.tokenAmountsToLiquidity(positionNft, sqrtRatioX96, tokenAmounts[0], tokenAmounts[1]);
        if (liquidity == 0) return actualTokenAmounts;
        else {
            address[] memory tokens = _vaultTokens;
            for (uint256 i = 0; i < tokens.length; ++i) {
                IERC20(tokens[i]).safeIncreaseAllowance(address(positionManager), tokenAmounts[i]);
            }

            (uint256 amount0Min, uint256 amount1Min, uint256 deadline) = _parseOptions(options);
            (, uint256 amount0, uint256 amount1) = positionManager.increaseLiquidity(
                INonfungiblePositionManager.IncreaseLiquidityParams({
                    tokenId: positionNft,
                    amount0Desired: tokenAmounts[0],
                    amount1Desired: tokenAmounts[1],
                    amount0Min: amount0Min,
                    amount1Min: amount1Min,
                    deadline: deadline
                })
            );

            actualTokenAmounts[0] = amount0;
            actualTokenAmounts[1] = amount1;

            for (uint256 i = 0; i < tokens.length; ++i) {
                IERC20(tokens[i]).safeApprove(address(positionManager), 0);
            }
        }
    }

    function _pull(
        address to,
        uint256[] memory tokenAmounts,
        bytes memory options
    ) internal override returns (uint256[] memory actualTokenAmounts) {
        IFarmingCenter farmingCenter_ = farmingCenter;
        uint256 positionNft_ = positionNft;
        IIncentiveKey.IncentiveKey memory key = IQuickSwapVaultGovernance(address(_vaultGovernance))
            .delayedStrategyParams(_nft)
            .key;
        if (positionNft_ == 0) {
            return new uint256[](2);
        }
        (uint256 farmingNft, , , ) = farmingCenter_.deposits(positionNft_);

        if (farmingNft != 0) {
            burnFarmingPosition();
        }

        uint128 liquidityToPull;
        {
            (, , , , , , uint128 liquidity, , , , ) = positionManager.positions(positionNft);
            (uint160 sqrtRatioX96, , , , , , ) = key.pool.globalState();
            liquidityToPull = helper.tokenAmountsToMaxLiquidity(positionNft_, sqrtRatioX96, tokenAmounts);
            liquidityToPull = liquidity < liquidityToPull ? liquidity : liquidityToPull;
        }
        if (liquidityToPull != 0) {
            (uint256 amount0Min, uint256 amount1Min, uint256 deadline) = _parseOptions(options);
            positionManager.decreaseLiquidity(
                INonfungiblePositionManager.DecreaseLiquidityParams({
                    tokenId: positionNft,
                    liquidity: liquidityToPull,
                    amount0Min: amount0Min,
                    amount1Min: amount1Min,
                    deadline: deadline
                })
            );
        }
        (uint256 amount0Collected, uint256 amount1Collected) = positionManager.collect(
            INonfungiblePositionManager.CollectParams({
                tokenId: positionNft,
                recipient: to,
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            })
        );

        actualTokenAmounts[0] = amount0Collected > tokenAmounts[0] ? tokenAmounts[0] : amount0Collected;
        actualTokenAmounts[1] = amount1Collected > tokenAmounts[1] ? tokenAmounts[1] : amount1Collected;

        if (farmingNft != 0) {
            _enterFarming(key);
        }
    }
}
