// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../interfaces/external/pancakeswap/INonfungiblePositionManager.sol";
import "../interfaces/external/pancakeswap/IPancakeV3Pool.sol";
import "../interfaces/external/pancakeswap/IPancakeV3Factory.sol";
import "../interfaces/vaults/IPancakeSwapVaultGovernance.sol";
import "../interfaces/vaults/IPancakeSwapVault.sol";
import "../libraries/ExceptionsLibrary.sol";
import "./IntegrationVault.sol";
import "../utils/PancakeSwapHelper.sol";

import "../interfaces/external/pancakeswap/IMasterChef.sol";
import "../interfaces/external/pancakeswap/ISmartRouter.sol";

/// @notice Vault that interfaces PancakeV3 protocol in the integration layer.
contract PancakeSwapVault is IPancakeSwapVault, IntegrationVault {
    using SafeERC20 for IERC20;

    struct Pair {
        uint256 a0;
        uint256 a1;
    }

    uint256 public constant D9 = 10**9;

    /// @inheritdoc IPancakeSwapVault
    IPancakeV3Pool public pool;
    /// @inheritdoc IPancakeSwapVault
    uint256 public uniV3Nft;
    INonfungiblePositionManager private _positionManager;

    PancakeSwapHelper public helper;

    /// @inheritdoc IPancakeSwapVault
    address public masterChef;

    bool private _isPositionInFarm;

    /// @inheritdoc IPancakeSwapVault
    address public erc20Vault;

    // -------------------  EXTERNAL, VIEW  -------------------

    /// @inheritdoc IVault
    function tvl() public view returns (uint256[] memory minTokenAmounts, uint256[] memory maxTokenAmounts) {
        (minTokenAmounts, maxTokenAmounts) = helper.tvl(
            uniV3Nft,
            address(_vaultGovernance),
            _nft,
            pool,
            _vaultTokens,
            masterChef
        );
    }

    /// @inheritdoc IntegrationVault
    function supportsInterface(bytes4 interfaceId) public view override(IERC165, IntegrationVault) returns (bool) {
        return super.supportsInterface(interfaceId) || (interfaceId == type(IPancakeSwapVault).interfaceId);
    }

    /// @inheritdoc IPancakeSwapVault
    function positionManager() external view returns (INonfungiblePositionManager) {
        return _positionManager;
    }

    /// @inheritdoc IPancakeSwapVault
    function liquidityToTokenAmounts(uint128 liquidity) external view returns (uint256[] memory tokenAmounts) {
        tokenAmounts = helper.liquidityToTokenAmounts(liquidity, pool, uniV3Nft);
    }

    /// @inheritdoc IPancakeSwapVault
    function tokenAmountsToLiquidity(uint256[] memory tokenAmounts) public view returns (uint128 liquidity) {
        liquidity = helper.tokenAmountsToLiquidity(tokenAmounts, pool, uniV3Nft);
    }

    // -------------------  EXTERNAL, MUTATING  -------------------
    /// @inheritdoc IPancakeSwapVault
    function initialize(
        uint256 nft_,
        address[] memory vaultTokens_,
        uint24 fee_,
        address helper_,
        address masterChef_,
        address erc20Vault_
    ) external {
        require(vaultTokens_.length == 2, ExceptionsLibrary.INVALID_VALUE);
        _initialize(vaultTokens_, nft_);
        _positionManager = IPancakeSwapVaultGovernance(address(_vaultGovernance))
            .delayedProtocolParams()
            .positionManager;
        pool = IPancakeV3Pool(
            IPancakeV3Factory(_positionManager.factory()).getPool(_vaultTokens[0], _vaultTokens[1], fee_)
        );
        masterChef = masterChef_;
        erc20Vault = erc20Vault_;
        helper = PancakeSwapHelper(helper_);
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
        if (from == masterChef) {
            require(tokenId == uniV3Nft, ExceptionsLibrary.INVALID_TOKEN);
        } else {
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
        }
        return this.onERC721Received.selector;
    }

    /// @inheritdoc IPancakeSwapVault
    function collectEarnings() external nonReentrant returns (uint256[] memory collectedEarnings) {
        compound();
        IVaultRegistry registry = _vaultGovernance.internalParams().registry;
        address owner = registry.ownerOf(_nft);
        address to = _root(registry, _nft, owner).subvaultAt(0);
        collectedEarnings = new uint256[](2);
        (uint256 collectedEarnings0, uint256 collectedEarnings1) = IMasterChef(masterChef).collect(
            IMasterChef.CollectParams({
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

        _unstakeUniV3Nft();
        address[] memory tokens = _vaultTokens;
        for (uint256 i = 0; i < tokens.length; ++i) {
            IERC20(tokens[i]).safeIncreaseAllowance(address(_positionManager), tokenAmounts[i]);
        }

        Options memory opts = _parseOptions(options);
        Pair memory amounts = Pair({a0: tokenAmounts[0], a1: tokenAmounts[1]});
        Pair memory minAmounts = Pair({a0: opts.amount0Min, a1: opts.amount1Min});
        (, uint256 amount0, uint256 amount1) = _positionManager.increaseLiquidity(
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

        for (uint256 i = 0; i < tokens.length; ++i) {
            IERC20(tokens[i]).safeApprove(address(_positionManager), 0);
        }
        _stakeUniV3Nft();
    }

    function _pull(
        address to,
        uint256[] memory tokenAmounts,
        bytes memory options
    ) internal override returns (uint256[] memory actualTokenAmounts) {
        actualTokenAmounts = new uint256[](2);
        if (uniV3Nft == 0) return actualTokenAmounts;

        _unstakeUniV3Nft();

        Options memory opts = _parseOptions(options);
        Pair memory amounts = _pullUniV3Nft(tokenAmounts, to, opts);
        actualTokenAmounts[0] = amounts.a0;
        actualTokenAmounts[1] = amounts.a1;

        _stakeUniV3Nft();
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
                INonfungiblePositionManager.DecreaseLiquidityParams({
                    tokenId: uniV3Nft,
                    liquidity: liquidityToPull,
                    amount0Min: minAmounts.a0,
                    amount1Min: minAmounts.a1,
                    deadline: opts.deadline
                })
            );
        }
        (uint256 amount0Collected, uint256 amount1Collected) = _positionManager.collect(
            INonfungiblePositionManager.CollectParams({
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

    function compound() public returns (uint256 rewards) {
        address masterChef_ = masterChef;
        try IMasterChef(masterChef_).harvest(uniV3Nft, address(this)) returns (uint256 rewards_) {
            rewards = rewards_;
        } catch {
            return 0;
        }
        IPancakeSwapVaultGovernance.StrategyParams memory params = IPancakeSwapVaultGovernance(
            address(_vaultGovernance)
        ).strategyParams(_nft);

        uint256 amountIn = IERC20(params.cake).balanceOf(address(this));

        if (amountIn == 0) return 0;

        uint256 priceX96 = helper.calculateCakePriceX96InUnderlying(params);
        priceX96 = FullMath.mulDiv(priceX96, D9 - params.swapSlippageD, D9);

        uint256 expectedAmountOut = FullMath.mulDiv(amountIn, priceX96, CommonLibrary.Q96);
        if (expectedAmountOut == 0) return 0;

        IERC20(params.cake).safeIncreaseAllowance(params.smartRouter, amountIn);
        ISmartRouter(params.smartRouter).exactInputSingle(
            ISmartRouter.ExactInputSingleParams({
                tokenIn: params.cake,
                tokenOut: params.underlyingToken,
                fee: IPancakeV3Pool(params.poolForSwap).fee(),
                recipient: erc20Vault,
                amountIn: amountIn,
                amountOutMinimum: expectedAmountOut,
                sqrtPriceLimitX96: 0
            })
        );
    }

    function stakeUniV3Nft() external {
        require(_isStrategy(msg.sender), ExceptionsLibrary.FORBIDDEN);
        _stakeUniV3Nft();
    }

    function unstakeUniV3Nft() external {
        require(_isStrategy(msg.sender), ExceptionsLibrary.FORBIDDEN);
        _unstakeUniV3Nft();
    }

    function _stakeUniV3Nft() private {
        (, , , , , , , uint128 liquidity, , , , ) = _positionManager.positions(uniV3Nft);
        if (_isPositionInFarm || liquidity == 0) return;
        try _positionManager.safeTransferFrom(address(this), masterChef, uniV3Nft) {
            _isPositionInFarm = true;
        } catch {}
    }

    function _unstakeUniV3Nft() private {
        if (_isPositionInFarm) {
            compound();
            IMasterChef(masterChef).withdraw(uniV3Nft, address(this));
            _isPositionInFarm = false;
        }
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
