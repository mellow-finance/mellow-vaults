// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.9;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "../interfaces/external/quickswap/IFarmingCenter.sol";
import "../interfaces/external/quickswap/IAlgebraEternalFarming.sol";
import "../interfaces/external/quickswap/IAlgebraEternalVirtualPool.sol";
import "../interfaces/vaults/IERC20Vault.sol";
import "../interfaces/vaults/IQuickSwapVault.sol";
import "../interfaces/vaults/IQuickSwapVaultGovernance.sol";

import "../libraries/ExceptionsLibrary.sol";
import {PositionValue, LiquidityAmounts, TickMath, FullMath} from "../interfaces/external/quickswap/PositionValue.sol";
import "./IntegrationVault.sol";

/// @notice Vault that interfaces UniswapV3 protocol in the integration layer.
contract QuickSwapVault is IQuickSwapVault, IntegrationVault {
    using SafeERC20 for IERC20;
    uint256 public constant Q128 = 2**128;
    uint256 public positionNft;
    IFarmingCenter public farmingCenter;
    INonfungiblePositionManager public positionManager;
    address public erc20Vault; // zero-vault

    // -------------------  EXTERNAL, VIEW  -------------------

    function liquidityToTokenAmounts(uint128 liquidity) public view returns (uint256 amount0, uint256 amount1) {
        (, , , , int24 tickLower, int24 tickUpper, , , , , ) = positionManager.positions(positionNft);

        (uint160 sqrtPriceX96, , , , , , ) = IQuickSwapVaultGovernance(address(_vaultGovernance))
            .delayedStrategyParams(_nft)
            .key
            .pool
            .globalState();
        uint160 sqrtPriceAX96 = TickMath.getSqrtRatioAtTick(tickLower);
        uint160 sqrtPriceBX96 = TickMath.getSqrtRatioAtTick(tickUpper);
        (amount0, amount1) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtPriceX96,
            sqrtPriceAX96,
            sqrtPriceBX96,
            liquidity
        );
    }

    function tokenAmountsToLiquidity(uint256 amount0, uint256 amount1) public view returns (uint128 liquidity) {
        (, , , , int24 tickLower, int24 tickUpper, , , , , ) = positionManager.positions(positionNft);
        (uint160 sqrtPriceX96, , , , , , ) = IQuickSwapVaultGovernance(address(_vaultGovernance))
            .delayedStrategyParams(_nft)
            .key
            .pool
            .globalState();
        uint160 sqrtPriceAX96 = TickMath.getSqrtRatioAtTick(tickLower);
        uint160 sqrtPriceBX96 = TickMath.getSqrtRatioAtTick(tickUpper);

        liquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96,
            sqrtPriceAX96,
            sqrtPriceBX96,
            amount0,
            amount1
        );
    }

    function calculateCollectableRewards(IAlgebraEternalFarming farming, IIncentiveKey.IncentiveKey memory key)
        public
        view
        returns (uint256 rewardAmount, uint256 bonusRewardAmount)
    {
        bytes32 incentiveId = keccak256(abi.encode(key));
        (uint256 totalReward, , address virtualPoolAddress, , , , ) = farming.incentives(incentiveId);
        if (totalReward == 0) {
            return (0, 0);
        }

        IAlgebraEternalVirtualPool virtualPool = IAlgebraEternalVirtualPool(virtualPoolAddress);

        (
            uint128 liquidity,
            int24 tickLower,
            int24 tickUpper,
            uint256 innerRewardGrowth0,
            uint256 innerRewardGrowth1
        ) = farming.farms(positionNft, incentiveId);
        if (liquidity == 0) {
            return (0, 0);
        }

        (uint256 virtualPoolInnerRewardGrowth0, uint256 virtualPoolInnerRewardGrowth1) = virtualPool
            .getInnerRewardsGrowth(tickLower, tickUpper);

        (rewardAmount, bonusRewardAmount) = (
            FullMath.mulDiv(virtualPoolInnerRewardGrowth0 - innerRewardGrowth0, liquidity, Q128),
            FullMath.mulDiv(virtualPoolInnerRewardGrowth1 - innerRewardGrowth1, liquidity, Q128)
        );
    }

    function calculateClaimableRewards(IAlgebraEternalFarming farming, IIncentiveKey.IncentiveKey memory key)
        public
        view
        returns (uint256 rewardAmount, uint256 bonusRewardAmount)
    {
        (rewardAmount, bonusRewardAmount) = calculateCollectableRewards(farming, key);
        rewardAmount += farming.rewards(address(this), key.rewardToken);
        bonusRewardAmount += farming.rewards(address(this), key.bonusRewardToken);
    }

    /// @inheritdoc IVault
    function tvl() public view returns (uint256[] memory minTokenAmounts, uint256[] memory maxTokenAmounts) {
        uint256 positionNft_ = positionNft;
        if (positionNft_ == 0) {
            return (new uint256[](2), new uint256[](2));
        }
        IQuickSwapVaultGovernance.DelayedStrategyParams memory strategyParams = IQuickSwapVaultGovernance(
            address(_vaultGovernance)
        ).delayedStrategyParams(_nft);
        IIncentiveKey.IncentiveKey memory key = strategyParams.key;
        (uint160 sqrtRatioX96, , , , , , ) = key.pool.globalState();
        (uint256 amount0, uint256 amount1) = PositionValue.total(positionManager, positionNft, sqrtRatioX96);

        minTokenAmounts = new uint256[](2);
        minTokenAmounts[0] = amount0;
        minTokenAmounts[1] = amount1;

        (uint256 rewardAmount, uint256 bonusRewardAmount) = calculateClaimableRewards(
            farmingCenter.eternalFarming(),
            key
        );
        address[] memory vaultTokens = _vaultTokens;

        if (address(key.rewardToken) == vaultTokens[0]) {
            minTokenAmounts[0] += rewardAmount;
        } else if (address(key.rewardToken) == vaultTokens[1]) {
            minTokenAmounts[1] += rewardAmount;
        } else {}

        if (address(key.bonusRewardToken) == vaultTokens[0]) {
            minTokenAmounts[0] += bonusRewardAmount;
        } else if (address(key.bonusRewardToken) == vaultTokens[1]) {
            minTokenAmounts[1] += bonusRewardAmount;
        } else {
            // convert by oracle price  in token
        }

        maxTokenAmounts = minTokenAmounts;

        // calculate all rewards
    }

    /// @inheritdoc IntegrationVault
    function supportsInterface(bytes4 interfaceId) public view override(IERC165, IntegrationVault) returns (bool) {
        return super.supportsInterface(interfaceId) || (interfaceId == type(IQuickSwapVault).interfaceId);
    }

    // -------------------  EXTERNAL, MUTATING  -------------------

    constructor(INonfungiblePositionManager positionManager_) {
        positionManager = positionManager_;
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
        positionManager = IQuickSwapVaultGovernance(address(_vaultGovernance)).delayedProtocolParams().positionManager;
    }

    function _enterFarming() private {
        farmingCenter.enterFarming(
            IQuickSwapVaultGovernance(address(_vaultGovernance)).delayedStrategyParams(_nft).key,
            positionNft,
            0,
            false // eternal farming
        );
    }

    function burnFarmingPosition() public {
        _isApprovedOrOwner(msg.sender);
        uint256 positionNft_ = positionNft;
        IFarmingCenter farmingCenter_ = farmingCenter;
        farmingCenter_.exitFarming(
            IQuickSwapVaultGovernance(address(_vaultGovernance)).delayedStrategyParams(_nft).key,
            positionNft_,
            false // eternal farming
        );
        IIncentiveKey.IncentiveKey memory key = IQuickSwapVaultGovernance(address(_vaultGovernance))
            .delayedStrategyParams(_nft)
            .key;
        farmingCenter_.claimReward(key.rewardToken, address(erc20Vault), 0, type(uint256).max);
        farmingCenter_.claimReward(key.bonusRewardToken, address(erc20Vault), 0, type(uint256).max);

        farmingCenter_.withdrawToken(positionNft_, address(this), "");
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
            _enterFarming();
            positionNft = positionNft_;
        } else {
            revert(ExceptionsLibrary.FORBIDDEN);
        }
        return this.onERC721Received.selector;
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
    function collectRewards() public returns (uint256 rewardTokenAmount, uint256 bonusTokenAmount) {
        _isApprovedOrOwner(msg.sender);
        uint256 positionNft_ = positionNft;
        IFarmingCenter farmingCenter_ = farmingCenter;
        (uint256 farmingNft, , , ) = farmingCenter_.deposits(positionNft_);
        if (farmingNft != 0) {
            IIncentiveKey.IncentiveKey memory key = IQuickSwapVaultGovernance(address(_vaultGovernance))
                .delayedStrategyParams(_nft)
                .key;
            (rewardTokenAmount, bonusTokenAmount) = calculateCollectableRewards(farmingCenter_.eternalFarming(), key);
            if (rewardTokenAmount + bonusTokenAmount == 0) {
                // nothing to collect
                return (0, 0);
            }
            farmingCenter_.collectRewards(key, positionNft_);
            rewardTokenAmount = farmingCenter_.claimReward(key.rewardToken, address(erc20Vault), 0, type(uint256).max);
            bonusTokenAmount = farmingCenter_.claimReward(
                key.bonusRewardToken,
                address(erc20Vault),
                0,
                type(uint256).max
            );
        }
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

    function _push(uint256[] memory tokenAmounts, bytes memory options)
        internal
        override
        returns (uint256[] memory actualTokenAmounts)
    {
        actualTokenAmounts = new uint256[](2);
        if (positionNft == 0) return actualTokenAmounts;

        uint128 liquidity = tokenAmountsToLiquidity(tokenAmounts[0], tokenAmounts[1]);

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
        if (positionNft_ == 0) {
            return new uint256[](2);
        }
        (uint256 farmingNft, , , ) = farmingCenter_.deposits(positionNft_);

        if (farmingNft != 0) {
            burnFarmingPosition();
        }

        uint128 liquidityToPull;
        {
            uint160 sqrtRatioAX96;
            uint160 sqrtRatioBX96;
            uint128 liquidity;
            {
                int24 tickLower;
                int24 tickUpper;
                (, , , , tickLower, tickUpper, liquidity, , , , ) = positionManager.positions(positionNft);
                sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(tickLower);
                sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(tickUpper);
            }
            (uint160 sqrtRatioX96, , , , , , ) = IQuickSwapVaultGovernance(address(_vaultGovernance))
                .delayedStrategyParams(_nft)
                .key
                .pool
                .globalState();

            if (sqrtRatioX96 <= sqrtRatioAX96) {
                liquidityToPull = LiquidityAmounts.getLiquidityForAmount0(
                    sqrtRatioAX96,
                    sqrtRatioBX96,
                    tokenAmounts[0]
                );
            } else if (sqrtRatioX96 < sqrtRatioBX96) {
                uint128 liquidity0 = LiquidityAmounts.getLiquidityForAmount0(
                    sqrtRatioX96,
                    sqrtRatioBX96,
                    tokenAmounts[0]
                );
                uint128 liquidity1 = LiquidityAmounts.getLiquidityForAmount1(
                    sqrtRatioAX96,
                    sqrtRatioX96,
                    tokenAmounts[1]
                );

                liquidityToPull = liquidity0 > liquidity1 ? liquidity0 : liquidity1;
            } else {
                liquidityToPull = LiquidityAmounts.getLiquidityForAmount1(
                    sqrtRatioAX96,
                    sqrtRatioBX96,
                    tokenAmounts[1]
                );
            }
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
            _enterFarming();
        }
    }
}
