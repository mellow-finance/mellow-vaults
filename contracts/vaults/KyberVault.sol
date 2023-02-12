// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.9;

import "../interfaces/external/kyber/periphery/IBasePositionManager.sol";
import "../interfaces/external/kyber/IPool.sol";
import "../interfaces/external/kyber/IFactory.sol";
import "../interfaces/vaults/IKyberVaultGovernance.sol";
import "../interfaces/vaults/IKyberVault.sol";
import "../libraries/ExceptionsLibrary.sol";
import "./IntegrationVault.sol";
import "../utils/KyberHelper.sol";

/// @notice Vault that interfaces UniswapV3 protocol in the integration layer.
contract KyberVault is IKyberVault, IntegrationVault {
    using SafeERC20 for IERC20;

    struct Pair {
        uint256 a0;
        uint256 a1;
    }

    /// @inheritdoc IKyberVault
    IPool public pool;
    /// @inheritdoc IKyberVault
    uint256 public kyberNft;

    IBasePositionManager private _positionManager;
    KyberHelper private _kyberHelper;

    // -------------------  EXTERNAL, VIEW  -------------------

    /// @inheritdoc IVault
    function tvl() public view returns (uint256[] memory minTokenAmounts, uint256[] memory maxTokenAmounts) {
        if (kyberNft == 0) {
            return (new uint256[](2), new uint256[](2));
        }

        (uint160 sqrtPriceX96, , , ) = pool.getPoolState();
        minTokenAmounts = _kyberHelper.calculateTvlBySqrtPriceX96(kyberNft, sqrtPriceX96);
    }

    /// @inheritdoc IntegrationVault
    function supportsInterface(bytes4 interfaceId) public view override(IERC165, IntegrationVault) returns (bool) {
        return super.supportsInterface(interfaceId) || (interfaceId == type(IKyberVault).interfaceId);
    }

    /// @inheritdoc IKyberVault
    function positionManager() external view returns (IBasePositionManager) {
        return _positionManager;
    }

    /// @inheritdoc IKyberVault
    function liquidityToTokenAmounts(uint128 liquidity) external view returns (uint256[] memory tokenAmounts) {
        tokenAmounts = _kyberHelper.liquidityToTokenAmounts(liquidity, pool, kyberNft);
    }

    /// @inheritdoc IKyberVault
    function tokenAmountsToLiquidity(uint256[] memory tokenAmounts) public view returns (uint128 liquidity) {
        liquidity = _kyberHelper.tokenAmountsToLiquidity(tokenAmounts, pool, kyberNft);
    }

    // -------------------  EXTERNAL, MUTATING  -------------------
    /// @inheritdoc IKyberVault
    function initialize(
        uint256 nft_,
        address[] memory vaultTokens_,
        uint24 fee_,
        address kyberHepler_
    ) external {
        require(vaultTokens_.length == 2, ExceptionsLibrary.INVALID_VALUE);
        _initialize(vaultTokens_, nft_);
        _positionManager = IKyberVaultGovernance(address(_vaultGovernance)).delayedProtocolParams().positionManager;
        pool = IPool(IFactory(_positionManager.factory()).getPool(_vaultTokens[0], _vaultTokens[1], fee_));
        _kyberHelper = KyberHelper(kyberHepler_);
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
        (, IBasePositionManager.PoolInfo memory poolInfo) = _positionManager.positions(tokenId);

        // new position should have vault tokens
        require(
            poolInfo.token0 == _vaultTokens[0] &&
                poolInfo.token1 == _vaultTokens[1] &&
                poolInfo.fee == pool.swapFeeUnits(),
            ExceptionsLibrary.INVALID_TOKEN
        );

        if (kyberNft != 0) {
            (IBasePositionManager.Position memory position, ) = _positionManager.positions(tokenId);
            require(position.liquidity == 0 && position.rTokenOwed == 0, ExceptionsLibrary.INVALID_VALUE);
            // return previous uni v3 position nft
            _positionManager.transferFrom(address(this), from, kyberNft);
        }

        kyberNft = tokenId;
        return this.onERC721Received.selector;
    }

    /// @inheritdoc IKyberVault
    function collectEarnings() external nonReentrant returns (uint256[] memory collectedEarnings) {
        IVaultRegistry registry = _vaultGovernance.internalParams().registry;
        address owner = registry.ownerOf(_nft);
        address to = _root(registry, _nft, owner).subvaultAt(0);
        collectedEarnings = new uint256[](2);

        (, uint256 collectedEarnings0, uint256 collectedEarnings1) = _positionManager.burnRTokens(
            IBasePositionManager.BurnRTokenParams({
                tokenId: kyberNft,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp + 1
            })
        );

        collectedEarnings[0] = collectedEarnings0;
        collectedEarnings[1] = collectedEarnings1;
        emit CollectedEarnings(tx.origin, msg.sender, to, collectedEarnings0, collectedEarnings1);
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
        if (kyberNft == 0) return actualTokenAmounts;

        uint128 liquidity = tokenAmountsToLiquidity(tokenAmounts);

        if (liquidity == 0) return actualTokenAmounts;
        else {
            address[] memory tokens = _vaultTokens;
            for (uint256 i = 0; i < tokens.length; ++i) {
                IERC20(tokens[i]).safeIncreaseAllowance(address(_positionManager), tokenAmounts[i]);
            }

            Options memory opts = _parseOptions(options);
            Pair memory amounts = Pair({a0: tokenAmounts[0], a1: tokenAmounts[1]});
            Pair memory minAmounts = Pair({a0: opts.amount0Min, a1: opts.amount1Min});
            (, uint256 amount0, uint256 amount1, ) = _positionManager.addLiquidity(
                IBasePositionManager.IncreaseLiquidityParams({
                    tokenId: kyberNft,
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
    }

    function _pull(
        address to,
        uint256[] memory tokenAmounts,
        bytes memory options
    ) internal override returns (uint256[] memory actualTokenAmounts) {
        // UniV3Vault should have strictly 2 vault tokens
        actualTokenAmounts = new uint256[](2);
        if (kyberNft == 0) return actualTokenAmounts;

        Options memory opts = _parseOptions(options);
        Pair memory amounts = _pullUniV3Nft(to, tokenAmounts, opts);
        actualTokenAmounts[0] = amounts.a0;
        actualTokenAmounts[1] = amounts.a1;
    }

    function _pullUniV3Nft(
        address to,
        uint256[] memory tokenAmounts,
        Options memory opts
    ) internal returns (Pair memory) {
        uint128 liquidityToPull;
        // scope the code below to avoid stack-too-deep exception
        {
            (IBasePositionManager.Position memory position, ) = _positionManager.positions(kyberNft);

            (uint160 sqrtPriceX96, , , ) = pool.getPoolState();
            liquidityToPull = _kyberHelper.tokenAmountsToMaximalLiquidity(
                sqrtPriceX96,
                position.tickLower,
                position.tickUpper,
                tokenAmounts[0],
                tokenAmounts[1]
            );
            liquidityToPull = position.liquidity < liquidityToPull ? position.liquidity : liquidityToPull;
        }
        if (liquidityToPull != 0) {
            Pair memory minAmounts = Pair({a0: opts.amount0Min, a1: opts.amount1Min});
            _positionManager.removeLiquidity(
                IBasePositionManager.RemoveLiquidityParams({
                    tokenId: kyberNft,
                    liquidity: liquidityToPull,
                    amount0Min: minAmounts.a0,
                    amount1Min: minAmounts.a1,
                    deadline: opts.deadline
                })
            );
        }

        (, uint256 amount0Collected, uint256 amount1Collected) = _positionManager.burnRTokens(
            IBasePositionManager.BurnRTokenParams({
                tokenId: kyberNft,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp + 1
            })
        );

        IERC20(_vaultTokens[0]).safeTransferFrom(address(this), to, amount0Collected);
        IERC20(_vaultTokens[1]).safeTransferFrom(address(this), to, amount1Collected);

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
