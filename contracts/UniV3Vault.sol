// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.9;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./interfaces/external/univ3/INonfungiblePositionManager.sol";
import "./interfaces/external/univ3/IUniswapV3Pool.sol";
import "./interfaces/external/univ3/IUniswapV3Factory.sol";
import "./interfaces/IUniV3VaultGovernance.sol";
import "./interfaces/IUniV3Vault.sol";
import "./libraries/external/TickMath.sol";
import "./libraries/external/LiquidityAmounts.sol";
import "./libraries/ExceptionsLibrary.sol";
import "./IntegrationVault.sol";

/// @notice Vault that interfaces UniswapV3 protocol in the integration layer.
contract UniV3Vault is IUniV3Vault, IntegrationVault {
    struct Options {
        uint256 amount0Min;
        uint256 amount1Min;
        uint256 deadline;
    }

    struct Pair {
        uint256 a0;
        uint256 a1;
    }

    IUniswapV3Pool public pool;

    uint256 public uniV3Nft;

    function supportsInterface(bytes4 interfaceId) public view override(IERC165, IntegrationVault) returns (bool) {
        return super.supportsInterface(interfaceId) || (interfaceId == type(IUniV3Vault).interfaceId);
    }

    function initialize(
        uint256 nft_,
        address[] memory vaultTokens_,
        uint24 fee_
    ) external {
        require(_vaultTokens.length == 2, ExceptionsLibrary.TOKEN_LENGTH);
        pool = IUniswapV3Pool(
            IUniswapV3Factory(_positionManager().factory()).getPool(_vaultTokens[0], _vaultTokens[1], fee_)
        );
        require(address(pool) != address(0), ExceptionsLibrary.UNISWAP_POOL_NOT_FOUND);

        _initialize(vaultTokens_, nft_);
    }

    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes memory
    ) external returns (bytes4) {
        require(msg.sender == address(_positionManager()), ExceptionsLibrary.NOT_POSITION_MANAGER);
        require(_isStrategy(operator), ExceptionsLibrary.NOT_STRATEGY);
        (, , address token0, address token1, , , , , , , , ) = _positionManager().positions(tokenId);
        // new position should have vault tokens
        require(token0 == _vaultTokens[0] && token1 == _vaultTokens[1], ExceptionsLibrary.NOT_VAULT_TOKEN);

        if (uniV3Nft != 0) {
            (, , , , , , , uint128 liquidity, , , uint128 tokensOwed0, uint128 tokensOwed1) = _positionManager()
                .positions(uniV3Nft);
            require(liquidity == 0 && tokensOwed0 == 0 && tokensOwed1 == 0, ExceptionsLibrary.TVL_NOT_ZERO);
            // return previous uni v3 position nft
            _positionManager().transferFrom(address(this), from, uniV3Nft);
        }

        uniV3Nft = tokenId;
        return this.onERC721Received.selector;
    }

    function collectEarnings(address to) external nonReentrant returns (uint256[] memory collectedEarnings) {
        require(_isApprovedOrOwner(msg.sender), ExceptionsLibrary.APPROVED_OR_OWNER);
        IVaultRegistry registry = _vaultGovernance.internalParams().registry;
        address owner = registry.ownerOf(_nft);
        require(owner == msg.sender || _isValidPullDestination(to), ExceptionsLibrary.VALID_PULL_DESTINATION);
        collectedEarnings = new uint256[](2);
        (uint256 collectedEarnings0, uint256 collectedEarnings1) = _positionManager().collect(
            INonfungiblePositionManager.CollectParams({
                tokenId: uniV3Nft,
                recipient: to,
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            })
        );
        collectedEarnings[0] = collectedEarnings0;
        collectedEarnings[1] = collectedEarnings1;
        emit CollectedEarnings(tx.origin, to, collectedEarnings0, collectedEarnings1);
    }

    /// @inheritdoc IVault
    function tvl() public view returns (uint256[] memory minTokenAmounts, uint256[] memory maxTokenAmounts) {
        if (uniV3Nft == 0) {
            return (new uint256[](2), new uint256[](2));
        }
        uint256 amountMin0;
        uint256 amountMax0;
        uint256 amountMin1;
        uint256 amountMax1;
        minTokenAmounts = new uint256[](2);
        maxTokenAmounts = new uint256[](2);
        int24 tickLower;
        int24 tickUpper;
        uint128 liquidity;
        uint160 sqrtPriceAX96;
        uint160 sqrtPriceBX96;
        {
            IUniV3VaultGovernance.DelayedProtocolParams memory params = IUniV3VaultGovernance(address(_vaultGovernance))
                .delayedProtocolParams();
            {
                uint128 tokensOwed0;
                uint128 tokensOwed1;
                (, , , , , tickLower, tickUpper, liquidity, , , tokensOwed0, tokensOwed1) = params
                    .positionManager
                    .positions(uniV3Nft);
                minTokenAmounts[0] = tokensOwed0;
                maxTokenAmounts[0] = tokensOwed0;
                minTokenAmounts[1] = tokensOwed1;
                maxTokenAmounts[1] = tokensOwed1;
            }
            sqrtPriceAX96 = TickMath.getSqrtRatioAtTick(tickLower);
            sqrtPriceBX96 = TickMath.getSqrtRatioAtTick(tickUpper);
            {
                uint256 minPriceX96;
                uint256 maxPriceX96;
                (, minPriceX96, maxPriceX96) = params.oracle.spotPrice(_vaultTokens[0], _vaultTokens[1]);
                {
                    uint256 minSqrtPriceX96 = CommonLibrary.sqrtX96(minPriceX96);
                    (amountMin0, amountMin1) = LiquidityAmounts.getAmountsForLiquidity(
                        uint160(minSqrtPriceX96),
                        sqrtPriceAX96,
                        sqrtPriceBX96,
                        liquidity
                    );
                }
                {
                    uint256 maxSqrtPriceX96 = CommonLibrary.sqrtX96(maxPriceX96);
                    (amountMax0, amountMax1) = LiquidityAmounts.getAmountsForLiquidity(
                        uint160(maxSqrtPriceX96),
                        sqrtPriceAX96,
                        sqrtPriceBX96,
                        liquidity
                    );
                }
            }
        }
        minTokenAmounts[0] += amountMin0 < amountMax0 ? amountMin0 : amountMax0;
        minTokenAmounts[1] += amountMin1 < amountMax1 ? amountMin1 : amountMax1;
        maxTokenAmounts[0] += amountMin0 < amountMax0 ? amountMax0 : amountMin0;
        maxTokenAmounts[1] += amountMin1 < amountMax1 ? amountMax1 : amountMin1;
    }

    function _push(uint256[] memory tokenAmounts, bytes memory options)
        internal
        override
        returns (uint256[] memory actualTokenAmounts)
    {
        address[] memory tokens = _vaultTokens;
        for (uint256 i = 0; i < tokens.length; ++i) {
            _allowTokenIfNecessary(tokens[i], address(_positionManager()));
        }

        actualTokenAmounts = new uint256[](2);
        if (uniV3Nft == 0) return actualTokenAmounts;

        Options memory opts = _parseOptions(options);
        Pair memory amounts = Pair({a0: tokenAmounts[0], a1: tokenAmounts[1]});
        Pair memory minAmounts = Pair({a0: opts.amount0Min, a1: opts.amount1Min});
        (, uint256 amount0, uint256 amount1) = _positionManager().increaseLiquidity(
            INonfungiblePositionManager.IncreaseLiquidityParams({
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
    }

    function _pull(
        address to,
        uint256[] memory tokenAmounts,
        bytes memory options
    ) internal override returns (uint256[] memory actualTokenAmounts) {
        // UniV3Vault should have strictly 2 vault tokens
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
        // scope the code below to avoid stack-too-deep exception
        {
            (, , , , , int24 tickLower, int24 tickUpper, uint128 liquidity, , , , ) = _positionManager().positions(
                uniV3Nft
            );
            (uint160 sqrtPriceX96, , , , , , ) = pool.slot0();
            uint160 sqrtPriceAX96 = TickMath.getSqrtRatioAtTick(tickLower);
            uint160 sqrtPriceBX96 = TickMath.getSqrtRatioAtTick(tickUpper);
            liquidityToPull = LiquidityAmounts.getLiquidityForAmounts(
                sqrtPriceX96,
                sqrtPriceAX96,
                sqrtPriceBX96,
                tokenAmounts[0],
                tokenAmounts[1]
            );
            liquidityToPull = liquidity < liquidityToPull ? liquidity : liquidityToPull;
            if (liquidityToPull == 0) {
                return Pair({a0: 0, a1: 0});
            }
        }
        Pair memory minAmounts = Pair({a0: opts.amount0Min, a1: opts.amount1Min});
        _positionManager().decreaseLiquidity(
            INonfungiblePositionManager.DecreaseLiquidityParams({
                tokenId: uniV3Nft,
                liquidity: liquidityToPull,
                amount0Min: minAmounts.a0,
                amount1Min: minAmounts.a1,
                deadline: opts.deadline
            })
        );
        (uint256 amount0Collected, uint256 amount1Collected) = _positionManager().collect(
            INonfungiblePositionManager.CollectParams({
                tokenId: uniV3Nft,
                recipient: to,
                amount0Max: uint128(tokenAmounts[0]),
                amount1Max: uint128(tokenAmounts[1])
            })
        );
        return Pair({a0: amount0Collected, a1: amount1Collected});
    }

    function _postReclaimTokens(address, address[] memory tokens) internal view override {}

    function _positionManager() internal view returns (INonfungiblePositionManager) {
        return IUniV3VaultGovernance(address(_vaultGovernance)).delayedProtocolParams().positionManager;
    }

    function _parseOptions(bytes memory options) internal view returns (Options memory) {
        if (options.length == 0) return Options({amount0Min: 0, amount1Min: 0, deadline: block.timestamp + 600});

        require(options.length == 32 * 3, ExceptionsLibrary.IO_LENGTH);
        return abi.decode(options, (Options));
    }

    function _isStrategy(address addr) internal view returns (bool) {
        return _vaultGovernance.internalParams().registry.getApproved(_nft) == addr;
    }

    event CollectedEarnings(address indexed origin, address indexed to, uint256 amount0, uint256 amount1);
}
