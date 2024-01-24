// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../interfaces/external/velo/INonfungiblePositionManager.sol";
import "../interfaces/external/velo/ICLPool.sol";
import "../interfaces/external/velo/ICLFactory.sol";
import "../interfaces/external/velo/ICLGauge.sol";

import "../interfaces/vaults/IVeloVault.sol";
import "../interfaces/vaults/IVeloVaultGovernance.sol";

import "../libraries/ExceptionsLibrary.sol";
import "./IntegrationVault.sol";

import "../utils/VeloHelper.sol";

import "forge-std/src/console2.sol";

/// @notice Vault that interfaces Velodrome protocol in the integration layer.
contract VeloVault is IVeloVault, IntegrationVault {
    using SafeERC20 for IERC20;

    ICLPool public pool;
    uint256 public tokenId;

    IVeloHelper public immutable helper;
    INonfungiblePositionManager public immutable positionManager;

    // -------------------  EXTERNAL, VIEW  -------------------

    /// @inheritdoc IVault
    function tvl() public view returns (uint256[] memory minTokenAmounts, uint256[] memory maxTokenAmounts) {
        uint256 tokenId_ = tokenId;
        if (tokenId_ == 0) return (new uint256[](2), new uint256[](2));
        minTokenAmounts = helper.calculateTvlBySpotPrice(tokenId_);
        maxTokenAmounts = minTokenAmounts;
    }

    /// @inheritdoc IntegrationVault
    function supportsInterface(bytes4 interfaceId) public view override(IERC165, IntegrationVault) returns (bool) {
        return super.supportsInterface(interfaceId) || (interfaceId == type(IVeloVault).interfaceId);
    }

    function liquidityToTokenAmounts(uint128 liquidity) public view returns (uint256[] memory tokenAmounts) {
        return helper.liquidityToTokenAmounts(liquidity, pool, tokenId);
    }

    function tokenAmountsToLiquidity(uint256[] memory tokenAmounts) public view returns (uint128 liquidity) {
        return helper.tokenAmountsToLiquidity(tokenAmounts, pool, tokenId);
    }

    function strategyParams() public view returns (IVeloVaultGovernance.StrategyParams memory) {
        return IVeloVaultGovernance(address(_vaultGovernance)).strategyParams(_nft);
    }

    // -------------------  EXTERNAL, MUTATING  -------------------

    constructor(INonfungiblePositionManager positionManager_, VeloHelper helper_) {
        positionManager = positionManager_;
        helper = helper_;
    }

    function initialize(
        uint256 nft_,
        address[] memory vaultTokens_,
        int24 tickSpacing_
    ) external override {
        require(vaultTokens_.length == 2, ExceptionsLibrary.INVALID_LENGTH);
        _initialize(vaultTokens_, nft_);
        pool = ICLPool(ICLFactory(positionManager.factory()).getPool(_vaultTokens[0], _vaultTokens[1], tickSpacing_));
        require(address(pool) != address(0), ExceptionsLibrary.NOT_FOUND);
    }

    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId_,
        bytes memory
    ) external returns (bytes4) {
        if (from == strategyParams().gauge) {
            require(from == operator && tokenId_ == tokenId, ExceptionsLibrary.FORBIDDEN);
            return this.onERC721Received.selector;
        }
        require(msg.sender == address(positionManager) && _isStrategy(operator), ExceptionsLibrary.FORBIDDEN);
        (, , address token0, address token1, int24 tickSpacing, , , , , , , ) = positionManager.positions(tokenId_);
        // new position should have vault tokens
        require(
            token0 == _vaultTokens[0] && token1 == _vaultTokens[1] && tickSpacing == pool.tickSpacing(),
            ExceptionsLibrary.INVALID_TOKEN
        );

        if (tokenId != 0) {
            (, , , , , , , uint128 liquidity, , , , ) = positionManager.positions(tokenId);
            require(liquidity == 0, ExceptionsLibrary.INVALID_VALUE);
            positionManager.transferFrom(address(this), from, tokenId);
        }

        tokenId = tokenId_;
        return this.onERC721Received.selector;
    }

    function collectRewards() external override {
        if (tokenId == 0) return;
        IVeloVaultGovernance.StrategyParams memory params = strategyParams();
        ICLGauge(params.gauge).getReward(tokenId);
        address token = ICLGauge(params.gauge).rewardToken();
        uint256 balance = IERC20(token).balanceOf(address(this));
        if (balance > 0) {
            IERC20(token).safeTransfer(params.farm, balance);
        }
    }

    function unstakeTokenId() external override {
        if (tokenId == 0) return;
        require(_isStrategy(msg.sender), ExceptionsLibrary.FORBIDDEN);
        ICLGauge(strategyParams().gauge).withdraw(tokenId);
    }

    function stakeTokenId() external override {
        if (tokenId == 0) return;
        require(_isStrategy(msg.sender), ExceptionsLibrary.FORBIDDEN);
        address gauge = strategyParams().gauge;
        positionManager.approve(gauge, tokenId);
        ICLGauge(gauge).deposit(tokenId);
    }

    // -------------------  INTERNAL, VIEW  -------------------

    function _parseOptions(bytes memory options)
        internal
        pure
        returns (
            uint256 amount0Min,
            uint256 amount1Min,
            uint256 deadline
        )
    {
        if (options.length == 0) return (0, 0, type(uint256).max);
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

    function _push(uint256[] memory tokenAmounts, bytes memory options) internal override returns (uint256[] memory) {
        if (tokenId == 0) return new uint256[](2);
        uint128 liquidity = tokenAmountsToLiquidity(tokenAmounts);
        if (liquidity == 0) return new uint256[](2);
        address[] memory tokens = _vaultTokens;

        address gauge = strategyParams().gauge;
        for (uint256 i = 0; i < tokens.length; ++i) {
            IERC20(tokens[i]).safeIncreaseAllowance(address(gauge), tokenAmounts[i]);
        }

        (uint256 amount0Min, uint256 amount1Min, uint256 deadline) = _parseOptions(options);
        uint256[] memory actualAmounts = new uint256[](2);
        (, actualAmounts[0], actualAmounts[1]) = ICLGauge(gauge).increaseStakedLiquidity(
            tokenId,
            tokenAmounts[0],
            tokenAmounts[1],
            amount0Min,
            amount1Min,
            deadline
        );

        for (uint256 i = 0; i < tokens.length; ++i) {
            IERC20(tokens[i]).safeApprove(address(gauge), 0);
        }
        return actualAmounts;
    }

    function _pull(
        address to,
        uint256[] memory tokenAmounts,
        bytes memory options
    ) internal override returns (uint256[] memory) {
        uint256 tokenId_ = tokenId;
        if (tokenId_ == 0) return new uint256[](2);
        return _pullTokenId(to, tokenAmounts, options, tokenId_);
    }

    function _pullTokenId(
        address to,
        uint256[] memory tokenAmounts,
        bytes memory options,
        uint256 tokenId_
    ) internal returns (uint256[] memory actualAmounts) {
        uint128 liquidityToPull;
        {
            (, , , , , int24 tickLower, int24 tickUpper, uint128 liquidity, , , , ) = positionManager.positions(
                tokenId_
            );
            (uint160 sqrtPriceX96, , , , , ) = pool.slot0();
            liquidityToPull =
                helper.tokenAmountsToMaximalLiquidity(
                    sqrtPriceX96,
                    tickLower,
                    tickUpper,
                    tokenAmounts[0],
                    tokenAmounts[1]
                ) +
                1;

            liquidityToPull = liquidity < liquidityToPull ? liquidity : liquidityToPull;
        }

        actualAmounts = new uint256[](2);
        if (liquidityToPull != 0) {
            (uint256 amount0Min, uint256 amount1Min, uint256 deadline) = _parseOptions(options);
            address gauge = strategyParams().gauge;
            (actualAmounts[0], actualAmounts[1]) = ICLGauge(gauge).decreaseStakedLiquidity(
                tokenId_,
                liquidityToPull,
                amount0Min,
                amount1Min,
                deadline
            );
            address[] memory tokens = _vaultTokens;
            for (uint256 i = 0; i < 2; i++) {
                if (actualAmounts[i] > 0) IERC20(tokens[i]).safeTransfer(to, actualAmounts[i]);
            }
        }

        // actualAmounts[0] = actualAmounts[0] > tokenAmounts[0] ? tokenAmounts[0] : actualAmounts[0];
        // actualAmounts[1] = actualAmounts[1] > tokenAmounts[1] ? tokenAmounts[1] : actualAmounts[1];
    }
}
