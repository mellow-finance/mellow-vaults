// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../interfaces/external/pancakeswap/IPancakeNonfungiblePositionManager.sol";
import "../interfaces/external/pancakeswap/IPancakeV3Pool.sol";
import "../interfaces/external/pancakeswap/IPancakeV3Factory.sol";
import "../interfaces/vaults/IPancakeSwapMerklVaultGovernance.sol";
import "../interfaces/vaults/IPancakeSwapMerklVault.sol";
import "../libraries/ExceptionsLibrary.sol";
import "./IntegrationVault.sol";
import "../utils/PancakeSwapMerklHelper.sol";

import "../interfaces/external/pancakeswap/ISmartRouter.sol";
import "../interfaces/external/merkl/IDistributor.sol";

/// @notice Vault that interfaces PancakeV3 protocol in the integration layer.
contract PancakeSwapMerklVault is IPancakeSwapMerklVault, IntegrationVault {
    using SafeERC20 for IERC20;

    struct Pair {
        uint256 a0;
        uint256 a1;
    }

    uint256 public constant D9 = 10**9;

    /// @inheritdoc IPancakeSwapMerklVault
    IPancakeV3Pool public pool;
    /// @inheritdoc IPancakeSwapMerklVault
    uint256 public uniV3Nft;
    IPancakeNonfungiblePositionManager private _positionManager;

    PancakeSwapMerklHelper public helper;

    /// @inheritdoc IPancakeSwapMerklVault
    address public erc20Vault;

    // -------------------  EXTERNAL, VIEW  -------------------

    /// @inheritdoc IVault
    function tvl() public view returns (uint256[] memory minTokenAmounts, uint256[] memory maxTokenAmounts) {
        (minTokenAmounts, maxTokenAmounts) = helper.tvl(uniV3Nft, address(_vaultGovernance), _nft, pool, _vaultTokens);
    }

    /// @inheritdoc IntegrationVault
    function supportsInterface(bytes4 interfaceId) public view override(IERC165, IntegrationVault) returns (bool) {
        return super.supportsInterface(interfaceId) || (interfaceId == type(IPancakeSwapMerklVault).interfaceId);
    }

    /// @inheritdoc IPancakeSwapMerklVault
    function positionManager() external view returns (IPancakeNonfungiblePositionManager) {
        return _positionManager;
    }

    /// @inheritdoc IPancakeSwapMerklVault
    function liquidityToTokenAmounts(uint128 liquidity) external view returns (uint256[] memory tokenAmounts) {
        tokenAmounts = helper.liquidityToTokenAmounts(liquidity, pool, uniV3Nft);
    }

    /// @inheritdoc IPancakeSwapMerklVault
    function tokenAmountsToLiquidity(uint256[] memory tokenAmounts) public view returns (uint128 liquidity) {
        liquidity = helper.tokenAmountsToLiquidity(tokenAmounts, pool, uniV3Nft);
    }

    // -------------------  EXTERNAL, MUTATING  -------------------
    /// @inheritdoc IPancakeSwapMerklVault
    function initialize(
        uint256 nft_,
        address[] memory vaultTokens_,
        uint24 fee_,
        address helper_,
        address erc20Vault_
    ) external {
        require(vaultTokens_.length == 2, ExceptionsLibrary.INVALID_VALUE);
        _initialize(vaultTokens_, nft_);
        _positionManager = IPancakeSwapMerklVaultGovernance(address(_vaultGovernance))
            .delayedProtocolParams()
            .positionManager;
        pool = IPancakeV3Pool(
            IPancakeV3Factory(_positionManager.factory()).getPool(_vaultTokens[0], _vaultTokens[1], fee_)
        );
        erc20Vault = erc20Vault_;
        helper = PancakeSwapMerklHelper(helper_);
        require(address(pool) != address(0), ExceptionsLibrary.NOT_FOUND);
    }

    /// @inheritdoc IERC721Receiver
    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes memory
    ) external returns (bytes4) {
        require(msg.sender == address(_positionManager), ExceptionsLibrary.FORBIDDEN);
        require(_isStrategy(operator), ExceptionsLibrary.FORBIDDEN);
        (, , address token0, address token1, uint24 fee, , , , , , , ) = _positionManager.positions(tokenId);
        require(
            token0 == _vaultTokens[0] && token1 == _vaultTokens[1] && fee == pool.fee(),
            ExceptionsLibrary.INVALID_TOKEN
        );

        if (uniV3Nft != 0) {
            (, , , , , , , uint128 liquidity, , , uint128 tokensOwed0, uint128 tokensOwed1) = _positionManager
                .positions(uniV3Nft);
            require(liquidity == 0 && tokensOwed0 == 0 && tokensOwed1 == 0, ExceptionsLibrary.INVALID_VALUE);
            _positionManager.transferFrom(address(this), from, uniV3Nft);
        }

        uniV3Nft = tokenId;
        return this.onERC721Received.selector;
    }

    /// @inheritdoc IPancakeSwapMerklVault
    function collectEarnings() external nonReentrant returns (uint256[] memory collectedEarnings) {
        address to = erc20Vault;
        collectedEarnings = new uint256[](2);
        (uint256 collectedEarnings0, uint256 collectedEarnings1) = _positionManager.collect(
            IPancakeNonfungiblePositionManager.CollectParams({
                tokenId: uniV3Nft,
                recipient: to,
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            })
        );
        collectedEarnings[0] = collectedEarnings0;
        collectedEarnings[1] = collectedEarnings1;
        emit CollectedEarnings(tx.origin, msg.sender, to, collectedEarnings0, collectedEarnings1);
    }

    /// @inheritdoc IPancakeSwapMerklVault
    function compound(
        address[] calldata tokens,
        uint256[] calldata amounts,
        bytes32[][] calldata proofs
    ) external returns (uint256[] memory claimedAmounts) {
        IPancakeSwapMerklVaultGovernance.StrategyParams memory params = IPancakeSwapMerklVaultGovernance(
            address(_vaultGovernance)
        ).strategyParams(_nft);
        address[] memory users = new address[](tokens.length);
        address this_ = address(this);
        for (uint256 i = 0; i < users.length; i++) {
            users[i] = this_;
        }
        IDistributor(params.merklFarm).claim(users, tokens, amounts, proofs);
        claimedAmounts = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            require(!IVault(this_).isVaultToken(tokens[i]), ExceptionsLibrary.FORBIDDEN);
            claimedAmounts[i] = IERC20(tokens[i]).balanceOf(this_);
            IERC20(tokens[i]).safeTransfer(params.lpFarm, claimedAmounts[i]);
        }
    }

    /// @inheritdoc IPancakeSwapMerklVault
    function updateHelper(address newHelper) external {
        require(_isStrategy(msg.sender), ExceptionsLibrary.FORBIDDEN);
        helper = PancakeSwapMerklHelper(newHelper);
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

    // -------------------  INTERNAL, MUTATING  -------------------

    function _push(uint256[] memory tokenAmounts, bytes memory options)
        internal
        override
        returns (uint256[] memory actualTokenAmounts)
    {
        actualTokenAmounts = new uint256[](2);
        if (uniV3Nft == 0) return actualTokenAmounts;

        uint128 liquidity = tokenAmountsToLiquidity(tokenAmounts);
        if (liquidity == 0) return actualTokenAmounts;

        address[] memory tokens = _vaultTokens;
        for (uint256 i = 0; i < tokens.length; ++i) {
            IERC20(tokens[i]).safeIncreaseAllowance(address(_positionManager), tokenAmounts[i]);
        }

        Options memory opts = _parseOptions(options);
        Pair memory amounts = Pair({a0: tokenAmounts[0], a1: tokenAmounts[1]});
        Pair memory minAmounts = Pair({a0: opts.amount0Min, a1: opts.amount1Min});
        (, uint256 amount0, uint256 amount1) = _positionManager.increaseLiquidity(
            IPancakeNonfungiblePositionManager.IncreaseLiquidityParams({
                tokenId: uniV3Nft,
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
            IERC20(tokens[i]).safeApprove(address(_positionManager), 0);
        }
    }

    function _pull(
        address to,
        uint256[] memory tokenAmounts,
        bytes memory options
    ) internal override returns (uint256[] memory actualTokenAmounts) {
        actualTokenAmounts = new uint256[](2);
        if (uniV3Nft == 0) return actualTokenAmounts;

        Options memory opts = _parseOptions(options);
        Pair memory amounts = _pullUniV3Nft(tokenAmounts, to, opts);
        actualTokenAmounts[0] = amounts.a0;
        actualTokenAmounts[1] = amounts.a1;
    }

    function _pullUniV3Nft(
        uint256[] memory tokenAmounts,
        address to,
        Options memory opts
    ) internal returns (Pair memory) {
        uint128 liquidityToPull;
        {
            (, , , , , int24 tickLower, int24 tickUpper, uint128 liquidity, , , , ) = _positionManager.positions(
                uniV3Nft
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
            _positionManager.decreaseLiquidity(
                IPancakeNonfungiblePositionManager.DecreaseLiquidityParams({
                    tokenId: uniV3Nft,
                    liquidity: liquidityToPull,
                    amount0Min: minAmounts.a0,
                    amount1Min: minAmounts.a1,
                    deadline: opts.deadline
                })
            );
        }
        (uint256 amount0Collected, uint256 amount1Collected) = _positionManager.collect(
            IPancakeNonfungiblePositionManager.CollectParams({
                tokenId: uniV3Nft,
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
}
