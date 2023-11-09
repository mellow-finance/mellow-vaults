// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../interfaces/external/ramses/IRamsesV2NonfungiblePositionManager.sol";
import "../interfaces/external/ramses/IRamsesV2Pool.sol";
import "../interfaces/external/ramses/IRamsesV2Factory.sol";
import "../interfaces/external/ramses/IGaugeV2.sol";
import "../interfaces/vaults/IRamsesV2VaultGovernance.sol";
import "../interfaces/vaults/IRamsesV2Vault.sol";
import "../libraries/ExceptionsLibrary.sol";
import "./IntegrationVault.sol";
import "../utils/RamsesV2Helper.sol";

contract RamsesV2Vault is IRamsesV2Vault, IntegrationVault {
    using SafeERC20 for IERC20;

    struct Pair {
        uint256 a0;
        uint256 a1;
    }

    /// @inheritdoc IRamsesV2Vault
    IRamsesV2Pool public pool;

    /// @inheritdoc IRamsesV2Vault
    uint256 public positionId;

    /// @inheritdoc IRamsesV2Vault
    address public erc20Vault;

    /// @inheritdoc IRamsesV2Vault
    IRamsesV2NonfungiblePositionManager public positionManager;

    RamsesV2Helper public helper;

    // -------------------  EXTERNAL, VIEW  -------------------

    /// @inheritdoc IVault
    function tvl() public view returns (uint256[] memory minTokenAmounts, uint256[] memory maxTokenAmounts) {
        uint256 positionId_ = positionId;
        if (positionId_ == 0) {
            return (new uint256[](2), new uint256[](2));
        }

        address vaultGovernance_ = address(_vaultGovernance);
        IRamsesV2VaultGovernance.DelayedProtocolParams memory params = IRamsesV2VaultGovernance(vaultGovernance_)
            .delayedProtocolParams();
        IRamsesV2VaultGovernance.DelayedStrategyParams memory strategyParams = IRamsesV2VaultGovernance(
            vaultGovernance_
        ).delayedStrategyParams(_nft);
        // cheaper way to calculate tvl by spot price
        if (strategyParams.safetyIndicesSet == 2) {
            (uint160 sqrtPriceX96, , , , , , ) = pool.slot0();
            minTokenAmounts = helper.calculateTvlBySqrtPriceX96(positionId, sqrtPriceX96);
            maxTokenAmounts = minTokenAmounts;
        } else {
            (uint256 minPriceX96, uint256 maxPriceX96) = _getMinMaxPrice(
                params.oracle,
                strategyParams.safetyIndicesSet
            );
            (minTokenAmounts, maxTokenAmounts) = helper.calculateTvlByMinMaxPrices(
                positionId_,
                minPriceX96,
                maxPriceX96
            );
        }
    }

    /// @inheritdoc IntegrationVault
    function supportsInterface(bytes4 interfaceId) public view override(IERC165, IntegrationVault) returns (bool) {
        return super.supportsInterface(interfaceId) || (interfaceId == type(IRamsesV2Vault).interfaceId);
    }

    /// @inheritdoc IRamsesV2Vault
    function liquidityToTokenAmounts(uint128 liquidity) external view returns (uint256[] memory tokenAmounts) {
        tokenAmounts = helper.liquidityToTokenAmounts(liquidity, pool, positionId);
    }

    /// @inheritdoc IRamsesV2Vault
    function tokenAmountsToLiquidity(uint256[] memory tokenAmounts) public view returns (uint128 liquidity) {
        liquidity = helper.tokenAmountsToLiquidity(tokenAmounts, pool, positionId);
    }

    // -------------------  EXTERNAL, MUTATING  -------------------
    /// @inheritdoc IRamsesV2Vault
    function initialize(
        uint256 nft_,
        address[] memory vaultTokens_,
        uint24 fee_,
        address helper_,
        address erc20Vault_
    ) external {
        require(vaultTokens_.length == 2, ExceptionsLibrary.INVALID_VALUE);
        _initialize(vaultTokens_, nft_);
        positionManager = IRamsesV2VaultGovernance(address(_vaultGovernance)).delayedProtocolParams().positionManager;
        pool = IRamsesV2Pool(
            IRamsesV2Factory(positionManager.factory()).getPool(_vaultTokens[0], _vaultTokens[1], fee_)
        );
        helper = RamsesV2Helper(helper_);
        erc20Vault = erc20Vault_;
        require(address(pool) != address(0), ExceptionsLibrary.NOT_FOUND);
    }

    /// @inheritdoc IERC721Receiver
    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes memory
    ) external returns (bytes4) {
        require(msg.sender == address(positionManager), ExceptionsLibrary.FORBIDDEN);
        require(_isStrategy(operator), ExceptionsLibrary.FORBIDDEN);
        (, , address token0, address token1, uint24 fee, , , , , , , ) = positionManager.positions(tokenId);
        // new position should have vault tokens
        require(
            token0 == _vaultTokens[0] && token1 == _vaultTokens[1] && fee == pool.fee(),
            ExceptionsLibrary.INVALID_TOKEN
        );

        if (positionId != 0) {
            (, , , , , , , uint128 liquidity, , , uint128 tokensOwed0, uint128 tokensOwed1) = positionManager.positions(
                positionId
            );
            require(liquidity == 0 && tokensOwed0 == 0 && tokensOwed1 == 0, ExceptionsLibrary.INVALID_VALUE);
            // return previous position nft
            positionManager.transferFrom(address(this), from, positionId);
        }

        positionId = tokenId;
        return this.onERC721Received.selector;
    }

    /// @inheritdoc IRamsesV2Vault
    function collectEarnings() external nonReentrant returns (uint256[] memory collectedEarnings) {
        collectedEarnings = new uint256[](2);
        address to = erc20Vault;
        (uint256 collectedEarnings0, uint256 collectedEarnings1) = positionManager.collect(
            IRamsesV2NonfungiblePositionManager.CollectParams({
                tokenId: positionId,
                recipient: to,
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            })
        );
        collectedEarnings[0] = collectedEarnings0;
        collectedEarnings[1] = collectedEarnings1;
        emit CollectedEarnings(tx.origin, msg.sender, to, collectedEarnings0, collectedEarnings1);
    }

    /// @inheritdoc IRamsesV2Vault
    function collectRewards() external nonReentrant returns (uint256[] memory collectedRewards) {
        IRamsesV2VaultGovernance.StrategyParams memory params = IRamsesV2VaultGovernance(address(_vaultGovernance))
            .strategyParams(_nft);

        IGaugeV2(params.gaugeV2).getReward(positionId, params.rewards);

        collectedRewards = new uint256[](params.rewards.length);
        for (uint256 i = 0; i < params.rewards.length; i++) {
            collectedRewards[i] = IERC20(params.rewards[i]).balanceOf(address(this));
            if (collectedRewards[i] > 0) {
                try IERC20(params.rewards[i]).transfer(params.farm, collectedRewards[i]) returns (bool success) {
                    if (!success) {
                        collectedRewards[i] = 0;
                    }
                } catch {
                    collectedRewards[i] = 0;
                }
            }
        }

        emit CollectedRewards(tx.origin, msg.sender, params.farm, params.rewards, collectedRewards);
    }

    // -------------------  INTERNAL, VIEW  -------------------

    function _parseOptions(bytes memory options) internal view returns (Options memory) {
        if (options.length == 0) return Options({amount0Min: 0, amount1Min: 0, deadline: block.timestamp + 600});

        require(options.length == 32 * 3, ExceptionsLibrary.INVALID_VALUE);
        return abi.decode(options, (Options));
    }

    function _isStrategy(address addr) internal view returns (bool) {
        return _vaultGovernance.internalParams().registry.getApproved(_nft) == addr;
    }

    function _isReclaimForbidden(address) internal pure override returns (bool) {
        return false;
    }

    function _getMinMaxPrice(IOracle oracle, uint32 safetyIndicesSet)
        internal
        view
        returns (uint256 minPriceX96, uint256 maxPriceX96)
    {
        (uint256[] memory prices, ) = oracle.priceX96(_vaultTokens[0], _vaultTokens[1], safetyIndicesSet);
        require(prices.length >= 1, ExceptionsLibrary.INVARIANT);
        minPriceX96 = prices[0];
        maxPriceX96 = prices[0];
        for (uint32 i = 1; i < prices.length; ++i) {
            if (prices[i] < minPriceX96) {
                minPriceX96 = prices[i];
            } else if (prices[i] > maxPriceX96) {
                maxPriceX96 = prices[i];
            }
        }
    }

    // -------------------  INTERNAL, MUTATING  -------------------

    function _push(uint256[] memory tokenAmounts, bytes memory options)
        internal
        override
        returns (uint256[] memory actualTokenAmounts)
    {
        actualTokenAmounts = new uint256[](2);
        if (positionId == 0) return actualTokenAmounts;

        uint128 liquidity = tokenAmountsToLiquidity(tokenAmounts);

        if (liquidity == 0) return actualTokenAmounts;
        else {
            address[] memory tokens = _vaultTokens;
            for (uint256 i = 0; i < tokens.length; ++i) {
                IERC20(tokens[i]).safeIncreaseAllowance(address(positionManager), tokenAmounts[i]);
            }

            Options memory opts = _parseOptions(options);
            Pair memory amounts = Pair({a0: tokenAmounts[0], a1: tokenAmounts[1]});
            Pair memory minAmounts = Pair({a0: opts.amount0Min, a1: opts.amount1Min});
            (, uint256 amount0, uint256 amount1) = positionManager.increaseLiquidity(
                IRamsesV2NonfungiblePositionManager.IncreaseLiquidityParams({
                    tokenId: positionId,
                    amount0Desired: amounts.a0,
                    amount1Desired: amounts.a1,
                    amount0Min: minAmounts.a0,
                    amount1Min: minAmounts.a1,
                    deadline: opts.deadline
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
        actualTokenAmounts = new uint256[](2);
        if (positionId == 0) return actualTokenAmounts;

        Options memory opts = _parseOptions(options);
        Pair memory amounts = _pullPosition(tokenAmounts, to, opts);
        actualTokenAmounts[0] = amounts.a0;
        actualTokenAmounts[1] = amounts.a1;
    }

    function _pullPosition(
        uint256[] memory tokenAmounts,
        address to,
        Options memory opts
    ) internal returns (Pair memory) {
        uint128 liquidityToPull;
        // scope the code below to avoid stack-too-deep exception
        {
            (, , , , , int24 tickLower, int24 tickUpper, uint128 liquidity, , , , ) = positionManager.positions(
                positionId
            );
            (uint160 sqrtPriceX96, , , , , , ) = pool.slot0();
            liquidityToPull = helper.tokenAmountsToMaximalLiquidity(
                sqrtPriceX96,
                tickLower,
                tickUpper,
                tokenAmounts[0],
                tokenAmounts[1]
            );
            liquidityToPull = liquidity < liquidityToPull ? liquidity : liquidityToPull;
        }
        if (liquidityToPull != 0) {
            Pair memory minAmounts = Pair({a0: opts.amount0Min, a1: opts.amount1Min});
            positionManager.decreaseLiquidity(
                IRamsesV2NonfungiblePositionManager.DecreaseLiquidityParams({
                    tokenId: positionId,
                    liquidity: liquidityToPull,
                    amount0Min: minAmounts.a0,
                    amount1Min: minAmounts.a1,
                    deadline: opts.deadline
                })
            );
        }
        (uint256 amount0Collected, uint256 amount1Collected) = positionManager.collect(
            IRamsesV2NonfungiblePositionManager.CollectParams({
                tokenId: positionId,
                recipient: to,
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            })
        );
        amount0Collected = amount0Collected > tokenAmounts[0] ? tokenAmounts[0] : amount0Collected;
        amount1Collected = amount1Collected > tokenAmounts[1] ? tokenAmounts[1] : amount1Collected;
        return Pair({a0: amount0Collected, a1: amount1Collected});
    }

    // --------------------------  EVENTS  --------------------------

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

    /// @notice Emitted when earnings are collected
    /// @param origin Origin of the transaction (tx.origin)
    /// @param sender Sender of the call (msg.sender)
    /// @param to Receiver of the rewards
    /// @param rewards array of reward tokens
    /// @param amounts of collected rewards
    event CollectedRewards(
        address indexed origin,
        address indexed sender,
        address indexed to,
        address[] rewards,
        uint256[] amounts
    );
}
