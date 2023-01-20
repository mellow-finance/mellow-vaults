// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.9;

import "../interfaces/vaults/IQuickSwapVault.sol";
import "../interfaces/vaults/IQuickSwapVaultGovernance.sol";

import "../libraries/ExceptionsLibrary.sol";
import "../libraries/external/FullMath.sol";

import "./IntegrationVault.sol";

/// @notice Vault that interfaces QuickSwap protocol in the integration layer.
contract QuickSwapVault is IQuickSwapVault, IntegrationVault {
    using SafeERC20 for IERC20;
    uint256 public constant Q96 = 2**96;
    uint256 public constant D9 = 10**9;

    /// @inheritdoc IQuickSwapVault
    uint256 public positionNft;
    /// @inheritdoc IQuickSwapVault
    address public erc20Vault;

    /// @inheritdoc IQuickSwapVault
    address public immutable dQuickToken;
    /// @inheritdoc IQuickSwapVault
    address public immutable quickToken;

    /// @inheritdoc IQuickSwapVault
    IFarmingCenter public immutable farmingCenter;
    /// @inheritdoc IQuickSwapVault
    IAlgebraSwapRouter public immutable swapRouter;
    /// @inheritdoc IQuickSwapVault
    IAlgebraNonfungiblePositionManager public immutable positionManager;
    /// @inheritdoc IQuickSwapVault
    IAlgebraFactory public immutable factory;
    /// @inheritdoc IQuickSwapVault
    IQuickSwapHelper public immutable helper;

    // -------------------  EXTERNAL, MUTATING  -------------------

    constructor(
        IAlgebraNonfungiblePositionManager positionManager_,
        IQuickSwapHelper helper_,
        IAlgebraSwapRouter swapRouter_,
        IFarmingCenter farmingCenter_,
        address dQuickToken_,
        address quickToken_
    ) {
        positionManager = positionManager_;
        factory = IAlgebraFactory(positionManager.factory());
        helper = helper_;
        swapRouter = swapRouter_;
        farmingCenter = farmingCenter_;
        dQuickToken = dQuickToken_;
        quickToken = quickToken_;
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
        for (uint256 i = 0; i < 2; i++) {
            IERC20(vaultTokens_[i]).safeIncreaseAllowance(address(positionManager), type(uint256).max);
        }
    }

    /// @inheritdoc IERC721Receiver
    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes memory
    ) external returns (bytes4) {
        IFarmingCenter farmingCenter_ = farmingCenter;
        require(msg.sender == address(positionManager), ExceptionsLibrary.FORBIDDEN);

        if (operator == address(farmingCenter_)) {
            require(tokenId == positionNft, ExceptionsLibrary.FORBIDDEN);
            return this.onERC721Received.selector;
        }
        require(_isStrategy(operator), ExceptionsLibrary.FORBIDDEN);

        (, , address token0, address token1, , , , , , , ) = positionManager.positions(tokenId);
        require(token0 == _vaultTokens[0] && token1 == _vaultTokens[1], ExceptionsLibrary.INVALID_TOKEN);

        uint256 positionNft_ = positionNft;
        if (positionNft_ != 0) {
            (, , , , , , uint128 liquidity, , , , ) = positionManager.positions(positionNft_);
            require(liquidity == 0, ExceptionsLibrary.INVALID_VALUE);
            (uint256 farmingNft, , , ) = farmingCenter_.deposits(positionNft_);
            require(farmingNft == 0, ExceptionsLibrary.INVALID_VALUE);
            positionManager.safeTransferFrom(address(this), from, positionNft_);
        }
        _openFarmingPosition(tokenId, farmingCenter_);
        positionNft = tokenId;
        return this.onERC721Received.selector;
    }

    /// @inheritdoc IQuickSwapVault
    function openFarmingPosition(uint256 nft, IFarmingCenter farmingCenter_) public {
        require(_isStrategy(msg.sender), ExceptionsLibrary.FORBIDDEN);
        _openFarmingPosition(nft, farmingCenter_);
    }

    /// @inheritdoc IQuickSwapVault
    function burnFarmingPosition(uint256 nft, IFarmingCenter farmingCenter_) public {
        require(_isStrategy(msg.sender), ExceptionsLibrary.FORBIDDEN);
        _burnFarmingPosition(nft, farmingCenter_);
    }

    /// @inheritdoc IQuickSwapVault
    function collectEarnings() external returns (uint256[] memory collectedFees) {
        uint256 positionNft_ = positionNft;
        if (positionNft_ == 0) return new uint256[](2);
        collectedFees = new uint256[](2);
        address erc20Vault_ = erc20Vault;
        (collectedFees[0], collectedFees[1]) = farmingCenter.collect(
            IAlgebraNonfungiblePositionManager.CollectParams({
                tokenId: positionNft_,
                recipient: erc20Vault_,
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            })
        );
        emit CollectedEarnings(tx.origin, msg.sender, erc20Vault_, collectedFees[0], collectedFees[1]);
    }

    /// @inheritdoc IQuickSwapVault
    function collectRewards() public returns (uint256[] memory collectedRewards) {
        IQuickSwapVaultGovernance.DelayedStrategyParams memory strategyParams = delayedStrategyParams();
        uint256 positionNft_ = positionNft;
        IFarmingCenter farmingCenter_ = farmingCenter;
        (uint256 farmingNft, , , ) = farmingCenter_.deposits(positionNft_);
        collectedRewards = new uint256[](2);
        if (farmingNft == 0) {
            return collectedRewards;
        }
        IIncentiveKey.IncentiveKey memory key = strategyParams.key;
        (uint256 rewardTokenAmount, uint256 bonusRewardTokenAmount) = helper.calculateCollectableRewards(
            farmingCenter_.eternalFarming(),
            key,
            positionNft_
        );
        if (rewardTokenAmount + bonusRewardTokenAmount == 0) {
            // nothing to collect
            return collectedRewards;
        }
        farmingCenter_.collectRewards(key, positionNft_);
        rewardTokenAmount = farmingCenter_.claimReward(key.rewardToken, address(this), 0, type(uint256).max);
        bonusRewardTokenAmount = farmingCenter_.claimReward(key.bonusRewardToken, address(this), 0, type(uint256).max);
        address erc20Vault_ = erc20Vault;
        {
            collectedRewards[0] = _swapTokenToUnderlying(
                rewardTokenAmount,
                address(key.rewardToken),
                strategyParams.rewardTokenToUnderlying,
                strategyParams.swapSlippageD
            );
            if (collectedRewards[0] > 0) {
                IERC20(strategyParams.rewardTokenToUnderlying).safeTransfer(erc20Vault_, collectedRewards[0]);
            }
        }
        {
            collectedRewards[1] = _swapTokenToUnderlying(
                bonusRewardTokenAmount,
                address(key.bonusRewardToken),
                strategyParams.bonusTokenToUnderlying,
                strategyParams.swapSlippageD
            );
            if (collectedRewards[1] > 0) {
                IERC20(strategyParams.bonusTokenToUnderlying).safeTransfer(erc20Vault_, collectedRewards[1]);
            }
        }

        address token0 = _vaultTokens[0];
        uint256 collectedToken0 = 0;
        uint256 collectedToken1 = 0;
        if (strategyParams.rewardTokenToUnderlying == token0) {
            collectedToken0 += collectedRewards[0];
        } else {
            collectedToken1 += collectedRewards[0];
        }

        if (strategyParams.bonusTokenToUnderlying == token0) {
            collectedToken0 += collectedRewards[1];
        } else {
            collectedToken1 += collectedRewards[1];
        }

        emit CollectedRewards(tx.origin, msg.sender, erc20Vault_, collectedToken0, collectedToken1);
    }

    // -------------------   EXTERNAL, VIEW   -------------------

    /// @inheritdoc IVault
    function tvl() public view returns (uint256[] memory minTokenAmounts, uint256[] memory maxTokenAmounts) {
        minTokenAmounts = helper.calculateTvl(positionNft, delayedStrategyParams(), farmingCenter, _vaultTokens[0]);
        maxTokenAmounts = minTokenAmounts;
    }

    /// @inheritdoc IntegrationVault
    function supportsInterface(bytes4 interfaceId) public view override(IERC165, IntegrationVault) returns (bool) {
        return super.supportsInterface(interfaceId) || (interfaceId == type(IQuickSwapVault).interfaceId);
    }

    /// @inheritdoc IQuickSwapVault
    function delayedStrategyParams()
        public
        view
        returns (IQuickSwapVaultGovernance.DelayedStrategyParams memory params)
    {
        params = IQuickSwapVaultGovernance(address(_vaultGovernance)).delayedStrategyParams(_nft);
    }

    // -------------------  INTERNAL, MUTATING  -------------------

    /// @dev swaps amount of token `from` to token `to`
    /// @param amount amount to be swapped
    /// @param from src token
    /// @param to dst token
    /// @param swapSlippageD slippage protection for swap
    function _swapTokenToUnderlying(
        uint256 amount,
        address from,
        address to,
        uint256 swapSlippageD
    ) private returns (uint256 amountOut) {
        if (from == to || amount == 0) return amount;
        if (from == dQuickToken) {
            // unstake dQUICK to QUICK token
            IDragonLair(dQuickToken).leave(amount);
            from = quickToken;
            amount = IERC20(quickToken).balanceOf(address(this));
            if (from == to || amount == 0) return amount;
        }
        IAlgebraPool pool = IAlgebraPool(factory.poolByPair(from, to));
        (uint160 sqrtPriceX96, , , , , , ) = pool.globalState();
        uint256 priceX96 = FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, Q96);
        if (pool.token0() == to) {
            priceX96 = FullMath.mulDiv(Q96, Q96, priceX96);
        }
        uint256 amountOutMinimum = FullMath.mulDiv(amount, priceX96, Q96);
        amountOutMinimum = FullMath.mulDiv(amountOutMinimum, D9 - swapSlippageD, D9);
        IERC20(from).safeApprove(address(swapRouter), type(uint256).max);
        amountOut = swapRouter.exactInputSingle(
            IAlgebraSwapRouter.ExactInputSingleParams({
                tokenIn: from,
                tokenOut: to,
                recipient: address(this),
                deadline: block.timestamp + 1,
                amountIn: amount,
                amountOutMinimum: amountOutMinimum,
                limitSqrtPrice: 0
            })
        );
    }

    function _push(uint256[] memory tokenAmounts, bytes memory options)
        internal
        override
        returns (uint256[] memory actualTokenAmounts)
    {
        actualTokenAmounts = new uint256[](2);
        uint256 positionNft_ = positionNft;
        if (positionNft_ == 0) return actualTokenAmounts;
        (uint160 sqrtRatioX96, , , , , , ) = delayedStrategyParams().key.pool.globalState();
        uint128 liquidity = helper.tokenAmountsToLiquidity(positionNft_, sqrtRatioX96, tokenAmounts);
        if (liquidity == 0) return actualTokenAmounts;
        (uint256 amount0Min, uint256 amount1Min, uint256 deadline) = _parseOptions(options);
        (, actualTokenAmounts[0], actualTokenAmounts[1]) = positionManager.increaseLiquidity(
            IAlgebraNonfungiblePositionManager.IncreaseLiquidityParams({
                tokenId: positionNft_,
                amount0Desired: tokenAmounts[0],
                amount1Desired: tokenAmounts[1],
                amount0Min: amount0Min,
                amount1Min: amount1Min,
                deadline: deadline
            })
        );
    }

    function _pull(
        address to,
        uint256[] memory tokenAmounts,
        bytes memory options
    ) internal override returns (uint256[] memory actualTokenAmounts) {
        IFarmingCenter farmingCenter_ = farmingCenter;
        uint256 positionNft_ = positionNft;
        if (positionNft_ == 0) {
            return new uint256[](2);
        }

        (uint256 farmingNft, , , ) = farmingCenter_.deposits(positionNft_);
        if (farmingNft != 0) {
            _burnFarmingPosition(positionNft_, farmingCenter_);
        }

        (uint160 sqrtRatioX96, , , , , , ) = delayedStrategyParams().key.pool.globalState();
        uint128 liquidityToPull = helper.calculateLiquidityToPull(positionNft_, sqrtRatioX96, tokenAmounts);

        if (liquidityToPull != 0) {
            (uint256 amount0Min, uint256 amount1Min, uint256 deadline) = _parseOptions(options);
            positionManager.decreaseLiquidity(
                IAlgebraNonfungiblePositionManager.DecreaseLiquidityParams({
                    tokenId: positionNft,
                    liquidity: liquidityToPull,
                    amount0Min: amount0Min,
                    amount1Min: amount1Min,
                    deadline: deadline
                })
            );
        }
        (uint256 amount0Collected, uint256 amount1Collected) = positionManager.collect(
            IAlgebraNonfungiblePositionManager.CollectParams({
                tokenId: positionNft,
                recipient: to,
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            })
        );
        actualTokenAmounts = new uint256[](2);
        actualTokenAmounts[0] = amount0Collected > tokenAmounts[0] ? tokenAmounts[0] : amount0Collected;
        actualTokenAmounts[1] = amount1Collected > tokenAmounts[1] ? tokenAmounts[1] : amount1Collected;

        if (farmingNft != 0) {
            _openFarmingPosition(positionNft_, farmingCenter_);
        }
    }

    function _openFarmingPosition(uint256 nft, IFarmingCenter farmingCenter_) private {
        positionManager.safeTransferFrom(address(this), address(farmingCenter_), nft);
        farmingCenter_.enterFarming(
            delayedStrategyParams().key,
            nft,
            0,
            false // eternal farming
        );
    }

    function _burnFarmingPosition(uint256 nft, IFarmingCenter farmingCenter_) private {
        collectRewards();
        farmingCenter_.exitFarming(
            delayedStrategyParams().key,
            nft,
            false // eternal farming
        );
        farmingCenter_.withdrawToken(nft, address(this), "");
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

    /// @notice Emitted when earnings are collected
    /// @param origin Origin of the transaction (tx.origin)
    /// @param sender Sender of the call (msg.sender)
    /// @param to Receiver of the fees
    /// @param amount0 Amount of token0 collected
    /// @param amount1 Amount of token1 collected
    event CollectedEarnings(
        address indexed origin,
        address indexed sender,
        address indexed to,
        uint256 amount0,
        uint256 amount1
    );

    /// @notice Emitted when rewards are collected
    /// @param origin Origin of the transaction (tx.origin)
    /// @param sender Sender of the call (msg.sender)
    /// @param to Receiver of the fees
    /// @param amount0 Amount of token0 collected
    /// @param amount1 Amount of token1 collected
    event CollectedRewards(
        address indexed origin,
        address indexed sender,
        address indexed to,
        uint256 amount0,
        uint256 amount1
    );
}
