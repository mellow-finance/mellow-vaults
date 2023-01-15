// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.9;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "../interfaces/vaults/IQuickSwapVault.sol";
import "../interfaces/vaults/IQuickSwapVaultGovernance.sol";

import "../libraries/ExceptionsLibrary.sol";
import "./IntegrationVault.sol";

/// @notice Vault that interfaces UniswapV3 protocol in the integration layer.
contract QuickSwapVault is IQuickSwapVault, IntegrationVault {
    using SafeERC20 for IERC20;
    /// @inheritdoc IQuickSwapVault
    uint256 public farmingNft;

    /// @inheritdoc IQuickSwapVault
    uint256 public positionNft;

    /// @inheritdoc IQuickSwapVault
    address public quickSwapHepler;

    /// @inheritdoc IQuickSwapVault
    INonfungiblePositionManager public positionManager;

    // -------------------  EXTERNAL, VIEW  -------------------

    /// @inheritdoc IVault
    function tvl() public view returns (uint256[] memory minTokenAmounts, uint256[] memory maxTokenAmounts) {
        uint256 quickSwapNft_ = farmingNft;
        if (quickSwapNft_ == 0) {
            return (new uint256[](2), new uint256[](2));
        }
    }

    /// @inheritdoc IntegrationVault
    function supportsInterface(bytes4 interfaceId) public view override(IERC165, IntegrationVault) returns (bool) {
        return super.supportsInterface(interfaceId) || (interfaceId == type(IQuickSwapVault).interfaceId);
    }

    constructor(INonfungiblePositionManager positionManager_) {
        positionManager = positionManager_;
    }

    // -------------------  EXTERNAL, MUTATING  -------------------
    /// @inheritdoc IQuickSwapVault
    function initialize(
        uint256 nft_,
        address[] memory vaultTokens_,
        uint24 fee_,
        address quickSwapHepler_
    ) external {
        farmingNft = 0;
        require(vaultTokens_.length == 2, ExceptionsLibrary.INVALID_VALUE);
        _initialize(vaultTokens_, nft_);
        positionManager = IQuickSwapVaultGovernance(address(_vaultGovernance)).delayedProtocolParams().positionManager;
        quickSwapHepler = quickSwapHepler_;
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
        // new position should have vault tokens
        // require(
        //     token0 == _vaultTokens[0] && token1 == _vaultTokens[1] && fee == pool.fee(),
        //     ExceptionsLibrary.INVALID_TOKEN
        // );

        // if (quickSwapNft != 0) {
        //     (, , , , , , , uint128 liquidity, , , uint128 tokensOwed0, uint128 tokensOwed1) = _positionManager
        //         .positions(uniV3Nft);
        //     require(liquidity == 0 && tokensOwed0 == 0 && tokensOwed1 == 0, ExceptionsLibrary.INVALID_VALUE);
        //     // return previous uni v3 position nft
        //     _positionManager.transferFrom(address(this), from, uniV3Nft);
        // }

        // uniV3Nft = tokenId;
        return this.onERC721Received.selector;
    }

    function collectEarnings() external nonReentrant returns (uint256[] memory collectedEarnings) {
        IVaultRegistry registry = _vaultGovernance.internalParams().registry;
        address owner = registry.ownerOf(_nft);
        address to = _root(registry, _nft, owner).subvaultAt(0);
        collectedEarnings = new uint256[](2);
        // (uint256 collectedEarnings0, uint256 collectedEarnings1) = _positionManager.collect(
        //     INonfungiblePositionManager.CollectParams({
        //         tokenId: uniV3Nft,
        //         recipient: to,
        //         amount0Max: type(uint128).max,
        //         amount1Max: type(uint128).max
        //     })
        // );
        // collectedEarnings[0] = collectedEarnings0;
        // collectedEarnings[1] = collectedEarnings1;
        // emit CollectedEarnings(tx.origin, msg.sender, to, collectedEarnings0, collectedEarnings1);
    }

    // -------------------  INTERNAL, VIEW  -------------------

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
        // actualTokenAmounts = new uint256[](2);
        // if (uniV3Nft == 0) return actualTokenAmounts;
        // uint128 liquidity = tokenAmountsToLiquidity(tokenAmounts);
        // if (liquidity == 0) return actualTokenAmounts;
        // else {
        //     address[] memory tokens = _vaultTokens;
        //     for (uint256 i = 0; i < tokens.length; ++i) {
        //         IERC20(tokens[i]).safeIncreaseAllowance(address(_positionManager), tokenAmounts[i]);
        //     }
        //     Options memory opts = _parseOptions(options);
        //     Pair memory amounts = Pair({a0: tokenAmounts[0], a1: tokenAmounts[1]});
        //     Pair memory minAmounts = Pair({a0: opts.amount0Min, a1: opts.amount1Min});
        //     (, uint256 amount0, uint256 amount1) = _positionManager.increaseLiquidity(
        //         INonfungiblePositionManager.IncreaseLiquidityParams({
        //             tokenId: uniV3Nft,
        //             amount0Desired: amounts.a0,
        //             amount1Desired: amounts.a1,
        //             amount0Min: minAmounts.a0,
        //             amount1Min: minAmounts.a1,
        //             deadline: opts.deadline
        //         })
        //     );
        //     actualTokenAmounts[0] = amount0;
        //     actualTokenAmounts[1] = amount1;
        //     for (uint256 i = 0; i < tokens.length; ++i) {
        //         IERC20(tokens[i]).safeApprove(address(_positionManager), 0);
        //     }
        // }
    }

    function _pull(
        address to,
        uint256[] memory tokenAmounts,
        bytes memory options
    ) internal override returns (uint256[] memory actualTokenAmounts) {
        // // UniV3Vault should have strictly 2 vault tokens
        // actualTokenAmounts = new uint256[](2);
        // if (uniV3Nft == 0) return actualTokenAmounts;
        // Pair memory amounts = _pullUniV3Nft(tokenAmounts, to, opts);
        // actualTokenAmounts[0] = amounts.a0;
        // actualTokenAmounts[1] = amounts.a1;
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
}
