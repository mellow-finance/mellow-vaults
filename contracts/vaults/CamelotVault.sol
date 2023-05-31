// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../interfaces/vaults/ICamelotVault.sol";
import "../interfaces/vaults/ICamelotVaultGovernance.sol";

import "../libraries/ExceptionsLibrary.sol";
import "../libraries/external/FullMath.sol";

import "./IntegrationVault.sol";

/// @notice Vault that interfaces Camelot protocol in the integration layer.
contract CamelotVault is ICamelotVault, IntegrationVault {
    using SafeERC20 for IERC20;
    uint256 public constant Q96 = 2**96;
    uint256 public constant D9 = 10**9;

    /// @inheritdoc ICamelotVault
    uint256 public positionNft;
    /// @inheritdoc ICamelotVault
    address public erc20Vault;

    /// @inheritdoc ICamelotVault
    IAlgebraNonfungiblePositionManager public immutable positionManager;
    /// @inheritdoc ICamelotVault
    IAlgebraFactory public immutable factory;
    /// @inheritdoc ICamelotVault
    ICamelotHelper public immutable helper;

    /// @inheritdoc ICamelotVault
    IAlgebraPool public pool;

    // -------------------  EXTERNAL, MUTATING  -------------------

    constructor(IAlgebraNonfungiblePositionManager positionManager_, ICamelotHelper helper_) {
        positionManager = positionManager_;
        factory = IAlgebraFactory(positionManager.factory());
        helper = helper_;
    }

    /// @inheritdoc ICamelotVault
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

        pool = IAlgebraPool(factory.poolByPair(vaultTokens_[0], vaultTokens_[1]));
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

        (, , address token0, address token1, , , , , , , ) = positionManager.positions(tokenId);
        require(token0 == _vaultTokens[0] && token1 == _vaultTokens[1], ExceptionsLibrary.INVALID_TOKEN);

        uint256 positionNft_ = positionNft;
        if (positionNft_ != 0) {
            (, , , , , , uint128 liquidity, , , , ) = positionManager.positions(positionNft_);
            require(liquidity == 0, ExceptionsLibrary.INVALID_VALUE);
            positionManager.safeTransferFrom(address(this), from, positionNft_);
        }
        positionNft = tokenId;
        return this.onERC721Received.selector;
    }

    /// @inheritdoc ICamelotVault
    function collectEarnings() external returns (uint256[] memory collectedFees) {
        uint256 positionNft_ = positionNft;
        if (positionNft_ == 0) return new uint256[](2);
        collectedFees = new uint256[](2);

        (collectedFees[0], collectedFees[1]) = positionManager.collect(
            IAlgebraNonfungiblePositionManager.CollectParams({
                tokenId: positionNft_,
                recipient: erc20Vault,
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            })
        );
        emit CollectedEarnings(tx.origin, msg.sender, collectedFees[0], collectedFees[1]);
    }

    // -------------------   EXTERNAL, VIEW   -------------------

    /// @inheritdoc IVault
    function tvl() public view returns (uint256[] memory minTokenAmounts, uint256[] memory maxTokenAmounts) {
        minTokenAmounts = helper.calculateTvl(positionNft);
        maxTokenAmounts = minTokenAmounts;
    }

    /// @inheritdoc IntegrationVault
    function supportsInterface(bytes4 interfaceId) public view override(IERC165, IntegrationVault) returns (bool) {
        return super.supportsInterface(interfaceId) || (interfaceId == type(ICamelotVault).interfaceId);
    }

    // -------------------  INTERNAL, MUTATING  -------------------

    function _push(uint256[] memory tokenAmounts, bytes memory options)
        internal
        override
        returns (uint256[] memory actualTokenAmounts)
    {
        actualTokenAmounts = new uint256[](2);
        uint256 positionNft_ = positionNft;
        if (positionNft_ == 0) return actualTokenAmounts;
        (uint160 sqrtRatioX96, , , , , , ) = pool.globalState();
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
        uint256 positionNft_ = positionNft;
        if (positionNft_ == 0) {
            return new uint256[](2);
        }

        (uint160 sqrtRatioX96, , , , , , ) = pool.globalState();
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
    /// @param amount0 Amount of token0 collected
    /// @param amount1 Amount of token1 collected
    event CollectedEarnings(address indexed origin, address indexed sender, uint256 amount0, uint256 amount1);

    /// @notice Emitted when rewards are collected
    /// @param origin Origin of the transaction (tx.origin)
    /// @param sender Sender of the call (msg.sender)
    /// @param amount0 Amount of collected rewardTokenToUnderlying
    /// @param amount1 Amount of collected bonusTokenToUnderlying
    event CollectedRewards(address indexed origin, address indexed sender, uint256 amount0, uint256 amount1);
}
