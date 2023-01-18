// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

import "../interfaces/vaults/IQuickSwapVault.sol";
import "../interfaces/vaults/IQuickSwapVaultGovernance.sol";

import "../libraries/ExceptionsLibrary.sol";
import "../utils/QuickSwapHelper.sol";

/// @notice Vault that interfaces QuickSwap protocol in the integration layer.
contract MockQuickSwapVault is IERC721Receiver {
    using SafeERC20 for IERC20;
    uint256 public constant Q96 = 2**96;
    uint256 public constant D9 = 10**9;

    uint256 public positionNft;
    address public erc20Vault; // zero-vault

    address public immutable dQuickToken;
    address public immutable quickToken;

    address[] _vaultTokens;

    IFarmingCenter public immutable farmingCenter;
    ISwapRouter public immutable swapRouter;
    INonfungiblePositionManager public immutable positionManager;
    IAlgebraFactory public immutable factory;
    QuickSwapHelper public immutable helper;
    IQuickSwapVaultGovernance.DelayedStrategyParams public _delayedStrategyParams;

    function updateStrategyParams(IQuickSwapVaultGovernance.DelayedStrategyParams memory strategyParams_) public {
        _delayedStrategyParams = strategyParams_;
    }

    modifier onlyStrategy() {
        _;
    }

    constructor(
        INonfungiblePositionManager positionManager_,
        QuickSwapHelper helper_,
        ISwapRouter swapRouter_,
        IFarmingCenter farmingCenter_,
        address dQuickToken_,
        address quickToken_,
        address[] memory vaultTokens_,
        address bufferAddress
    ) {
        positionManager = positionManager_;
        factory = IAlgebraFactory(positionManager.factory());
        helper = helper_;
        swapRouter = swapRouter_;
        farmingCenter = farmingCenter_;
        dQuickToken = dQuickToken_;
        quickToken = quickToken_;
        _vaultTokens = vaultTokens_;
        erc20Vault = bufferAddress;
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
        openFarmingPosition(tokenId, farmingCenter_);
        positionNft = tokenId;
        return this.onERC721Received.selector;
    }

    function openFarmingPosition(uint256 nft, IFarmingCenter farmingCenter_) public onlyStrategy {
        positionManager.safeTransferFrom(address(this), address(farmingCenter_), nft);
        farmingCenter_.enterFarming(
            _delayedStrategyParams.key,
            nft,
            0,
            false // eternal farming
        );
    }

    function burnFarmingPosition(uint256 nft, IFarmingCenter farmingCenter_) public onlyStrategy {
        IQuickSwapVaultGovernance.DelayedStrategyParams memory strategyParams = _delayedStrategyParams;
        collectRewards(strategyParams);
        farmingCenter_.exitFarming(
            strategyParams.key,
            nft,
            false // eternal farming
        );
        farmingCenter_.withdrawToken(nft, address(this), "");
    }

    function collectEarnings() external returns (uint256[] memory collectedFees) {
        uint256 positionNft_ = positionNft;
        if (positionNft_ == 0) return new uint256[](2);
        collectedFees = new uint256[](2);
        (collectedFees[0], collectedFees[1]) = farmingCenter.collect(
            INonfungiblePositionManager.CollectParams({
                tokenId: positionNft_,
                recipient: erc20Vault,
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            })
        );
    }

    function collectRewards(IQuickSwapVaultGovernance.DelayedStrategyParams memory strategyParams)
        public
        onlyStrategy
        returns (uint256 rewardTokenAmount, uint256 bonusRewardTokenAmount)
    {
        uint256 positionNft_ = positionNft;
        IFarmingCenter farmingCenter_ = farmingCenter;
        (uint256 farmingNft, , , ) = farmingCenter_.deposits(positionNft_);
        if (farmingNft == 0) {
            return (0, 0);
        }
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
        rewardTokenAmount = farmingCenter_.claimReward(key.rewardToken, address(this), 0, type(uint256).max);
        bonusRewardTokenAmount = farmingCenter_.claimReward(key.bonusRewardToken, address(this), 0, type(uint256).max);
        {
            uint256 amount = _swapTokenToUnderlying(
                rewardTokenAmount,
                address(key.rewardToken),
                strategyParams.rewardTokenToUnderlying,
                strategyParams.swapSlippageD
            );
            IERC20(strategyParams.rewardTokenToUnderlying).safeTransfer(address(erc20Vault), amount);
        }
        {
            uint256 amount = _swapTokenToUnderlying(
                bonusRewardTokenAmount,
                address(key.bonusRewardToken),
                strategyParams.bonusTokenToUnderlying,
                strategyParams.swapSlippageD
            );
            IERC20(strategyParams.bonusTokenToUnderlying).safeTransfer(address(erc20Vault), amount);
        }
    }

    function tvl() public view returns (uint256[] memory minTokenAmounts, uint256[] memory maxTokenAmounts) {
        minTokenAmounts = helper.calculateTvl(positionNft, _delayedStrategyParams, farmingCenter, _vaultTokens[0]);
        maxTokenAmounts = minTokenAmounts;
    }

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
    ) public returns (uint256 amountOut) {
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
        amountOutMinimum = FullMath.mulDiv(amountOutMinimum, swapSlippageD, D9);
        IERC20(from).safeIncreaseAllowance(address(swapRouter), amount);
        amountOut = swapRouter.exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: from,
                tokenOut: to,
                recipient: address(this),
                deadline: block.timestamp + 1,
                amountIn: amount,
                amountOutMinimum: amountOutMinimum,
                limitSqrtPrice: 0
            })
        );
        IERC20(from).safeApprove(address(swapRouter), 0);
    }

    function push(uint256[] memory tokenAmounts, bytes memory options)
        public
        returns (uint256[] memory actualTokenAmounts)
    {
        actualTokenAmounts = new uint256[](2);
        if (positionNft == 0) return actualTokenAmounts;

        (uint160 sqrtRatioX96, , , , , , ) = _delayedStrategyParams.key.pool.globalState();
        uint128 liquidity = helper.tokenAmountsToLiquidity(positionNft, sqrtRatioX96, tokenAmounts);
        if (liquidity == 0) return actualTokenAmounts;
        address[] memory tokens = _vaultTokens;
        for (uint256 i = 0; i < tokens.length; ++i) {
            IERC20(tokens[i]).safeIncreaseAllowance(address(positionManager), tokenAmounts[i]);
        }

        (uint256 amount0Min, uint256 amount1Min, uint256 deadline) = _parseOptions(options);
        (, actualTokenAmounts[0], actualTokenAmounts[1]) = positionManager.increaseLiquidity(
            INonfungiblePositionManager.IncreaseLiquidityParams({
                tokenId: positionNft,
                amount0Desired: tokenAmounts[0],
                amount1Desired: tokenAmounts[1],
                amount0Min: amount0Min,
                amount1Min: amount1Min,
                deadline: deadline
            })
        );
        for (uint256 i = 0; i < tokens.length; ++i) {
            IERC20(tokens[i]).safeApprove(address(positionManager), 0);
        }
    }

    function pull(
        address to,
        uint256[] memory tokenAmounts,
        bytes memory options
    ) public returns (uint256[] memory actualTokenAmounts) {
        IFarmingCenter farmingCenter_ = farmingCenter;
        uint256 positionNft_ = positionNft;
        IIncentiveKey.IncentiveKey memory key = _delayedStrategyParams.key;
        if (positionNft_ == 0) {
            return new uint256[](2);
        }
        (uint256 farmingNft, , , ) = farmingCenter_.deposits(positionNft_);

        if (farmingNft != 0) {
            burnFarmingPosition(positionNft_, farmingCenter_);
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
        actualTokenAmounts = new uint256[](2);
        actualTokenAmounts[0] = amount0Collected > tokenAmounts[0] ? tokenAmounts[0] : amount0Collected;
        actualTokenAmounts[1] = amount1Collected > tokenAmounts[1] ? tokenAmounts[1] : amount1Collected;

        if (farmingNft != 0) {
            openFarmingPosition(positionNft_, farmingCenter_);
        }
    }

    function _parseOptions(bytes memory options)
        public
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
}
