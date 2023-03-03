// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.9;

import "../interfaces/external/kyber/periphery/IBasePositionManager.sol";
import "../interfaces/external/kyber/IPool.sol";
import "../interfaces/external/kyber/IKyberSwapElasticLM.sol";
import "../interfaces/external/kyber/IFactory.sol";
import "../interfaces/vaults/IKyberVaultGovernance.sol";
import "../interfaces/vaults/IAggregateVault.sol";
import "../interfaces/vaults/IKyberVault.sol";
import "../interfaces/oracles/IOracle.sol";
import "../libraries/ExceptionsLibrary.sol";
import "./IntegrationVault.sol";
import "../utils/KyberHelper.sol";

/// @notice Vault that interfaces Kyber protocol in the integration layer.
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
    KyberHelper public kyberHelper;
    IRouter public router;

    IKyberSwapElasticLM public farm;
    IOracle public mellowOracle;
    uint256 public pid;

    bool public isLiquidityInFarm;

    // -------------------  EXTERNAL, VIEW  -------------------

    /// @inheritdoc IVault
    function tvl() public view returns (uint256[] memory minTokenAmounts, uint256[] memory maxTokenAmounts) {
        if (kyberNft == 0) return (new uint256[](2), new uint256[](2));
        (uint160 sqrtPriceX96, , , ) = pool.getPoolState();
        minTokenAmounts = kyberHelper.calculateTvlBySqrtPriceX96(pool, kyberNft, sqrtPriceX96);

        if (address(farm) != address(0)) {
            uint256 pointer = 0;

            (, , , , , , , address[] memory rewardTokens, ) = farm.getPoolInfo(pid);
            (, uint256[] memory rewardsPending, ) = farm.getUserInfo(kyberNft, pid);

            for (uint256 i = 0; i < rewardTokens.length; ++i) {
                bool exists = false;
                for (uint256 j = 0; j < _vaultTokens.length; ++j) {
                    if (rewardTokens[i] == _vaultTokens[j]) {
                        exists = true;
                        minTokenAmounts[j] += rewardsPending[i];
                    }
                }
                if (!exists) {
                    bytes memory path = IKyberVaultGovernance(address(_vaultGovernance))
                        .delayedStrategyParams(_nft)
                        .paths[pointer];
                    address lastToken = _toAddress(path, path.length - 20);

                    (uint256[] memory pricesX96, ) = mellowOracle.priceX96(rewardTokens[i], lastToken, 0x20);
                    if (pricesX96[0] != 0) {
                        uint256 amount = FullMath.mulDiv(rewardsPending[i], pricesX96[0], 2**96);
                        for (uint256 j = 0; j < _vaultTokens.length; ++j) {
                            if (lastToken == _vaultTokens[j]) {
                                minTokenAmounts[j] += amount;
                            }
                        }
                    }

                    pointer += 1;
                }
            }
        }

        maxTokenAmounts = minTokenAmounts;
    }

    function _toAddress(bytes memory _bytes, uint256 _start) internal pure returns (address) {
        require(_start + 20 >= _start, "toAddress_overflow");
        require(_bytes.length >= _start + 20, "toAddress_outOfBounds");
        address tempAddress;

        assembly {
            tempAddress := div(mload(add(add(_bytes, 0x20), _start)), 0x1000000000000000000000000)
        }

        return tempAddress;
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
        tokenAmounts = kyberHelper.liquidityToTokenAmounts(liquidity, pool, kyberNft);
    }

    /// @inheritdoc IKyberVault
    function tokenAmountsToLiquidity(uint256[] memory tokenAmounts) public view returns (uint128 liquidity) {
        liquidity = kyberHelper.tokenAmountsToLiquidity(tokenAmounts, pool, kyberNft);
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
        farm = IKyberVaultGovernance(address(_vaultGovernance)).delayedProtocolParams().farm;
        router = IKyberVaultGovernance(address(_vaultGovernance)).delayedProtocolParams().router;
        pid = IKyberVaultGovernance(address(_vaultGovernance)).delayedStrategyParams(nft_).pid;
        mellowOracle = IKyberVaultGovernance(address(_vaultGovernance)).delayedProtocolParams().mellowOracle;
        pool = IPool(IFactory(_positionManager.factory()).getPool(vaultTokens_[0], vaultTokens_[1], fee_));
        kyberHelper = KyberHelper(kyberHepler_);
        require(address(pool) != address(0), ExceptionsLibrary.NOT_FOUND);
    }

    function updateFarmInfo() external {
        farm = IKyberVaultGovernance(address(_vaultGovernance)).delayedProtocolParams().farm;
        pid = IKyberVaultGovernance(address(_vaultGovernance)).delayedStrategyParams(_nft).pid;
    }

    function _depositIntoFarm() internal {
        if (address(farm) == address(0) || kyberNft == 0) {
            return;
        }

        (IBasePositionManager.Position memory position, ) = _positionManager.positions(kyberNft);
        if (position.liquidity == 0) {
            return;
        }

        _positionManager.approve(address(farm), kyberNft);

        uint256[] memory nftIds = new uint256[](1);
        nftIds[0] = kyberNft;

        uint256[] memory liqs = new uint256[](1);
        liqs[0] = position.liquidity;

        farm.deposit(nftIds);
        farm.join(pid, nftIds, liqs);

        isLiquidityInFarm = true;
    }

    function _withdrawFromFarm(address to) internal {
        if (address(farm) == address(0) || kyberNft == 0 || !isLiquidityInFarm) {
            return;
        }

        isLiquidityInFarm = false;

        uint256[] memory nftIds = new uint256[](1);
        nftIds[0] = kyberNft;

        uint256[] memory liqs = new uint256[](1);
        (IBasePositionManager.Position memory position, ) = _positionManager.positions(kyberNft);
        liqs[0] = position.liquidity;

        farm.exit(pid, nftIds, liqs);
        farm.withdraw(nftIds);

        (, , , , , , , address[] memory rewardTokens, ) = farm.getPoolInfo(pid);

        uint256 pointer = 0;

        for (uint256 i = 0; i < rewardTokens.length; ++i) {
            bool exists = false;
            for (uint256 j = 0; j < _vaultTokens.length; ++j) {
                if (rewardTokens[i] == _vaultTokens[j]) {
                    exists = true;
                }
            }
            if (!exists) {
                bytes memory path = IKyberVaultGovernance(address(_vaultGovernance)).delayedStrategyParams(_nft).paths[
                    pointer
                ];

                uint256 toSwap = IERC20(rewardTokens[i]).balanceOf(address(this));

                if (toSwap > 0) {

                    router.swapExactInput(IRouter.ExactInputParams({
                        path: path, 
                        recipient: address(this),
                        deadline: block.timestamp + 1,
                        amountIn: IERC20(rewardTokens[i]).balanceOf(address(this)),
                        minAmountOut: 0
                    }));

                }
                
                pointer += 1;
            }
        }
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
            _withdrawFromFarm(_erc20Vault());
            (IBasePositionManager.Position memory position, ) = _positionManager.positions(tokenId);
            require(position.liquidity == 0 && position.rTokenOwed == 0, ExceptionsLibrary.INVALID_VALUE);
            // return previous kyber position nft
            _positionManager.transferFrom(address(this), from, kyberNft);
        }

        kyberNft = tokenId;

        _depositIntoFarm();

        return this.onERC721Received.selector;
    }

    function _burnRTokens() private returns (uint256 amount0, uint256 amount1) {
        (IBasePositionManager.Position memory position, ) = _positionManager.positions(kyberNft);
        if (position.rTokenOwed > 0) {
            (, amount0, amount1) = _positionManager.burnRTokens(
                IBasePositionManager.BurnRTokenParams({
                    tokenId: kyberNft,
                    amount0Min: 0,
                    amount1Min: 0,
                    deadline: block.timestamp + 1
                })
            );
        }
    }

    /// @inheritdoc IKyberVault
    function collectEarnings() external nonReentrant returns (uint256[] memory collectedEarnings) {
        IVaultRegistry registry = _vaultGovernance.internalParams().registry;
        address owner = registry.ownerOf(_nft);
        address to = _root(registry, _nft, owner).subvaultAt(0);
        collectedEarnings = new uint256[](2);
        (collectedEarnings[0], collectedEarnings[1]) = _burnRTokens();

        address[] memory tokens = _vaultTokens;
        IERC20(tokens[0]).safeTransfer(to, collectedEarnings[0]);
        IERC20(tokens[1]).safeTransfer(to, collectedEarnings[1]);
        emit CollectedEarnings(tx.origin, msg.sender, to, collectedEarnings[0], collectedEarnings[1]);
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

    function _isReclaimForbidden(address token) internal view override returns (bool) {
        address[] memory tokens = _vaultTokens;
        if (token == tokens[0] || token == tokens[1]) {
            return false;
        }
        return true;
    }

    // -------------------  INTERNAL, MUTATING  -------------------

    function _push(uint256[] memory tokenAmounts, bytes memory options)
        internal
        override
        returns (uint256[] memory actualTokenAmounts)
    {
        console2.log("W1", IERC20(_vaultTokens[0]).balanceOf(address(this)));
        console2.log("W2", IERC20(_vaultTokens[1]).balanceOf(address(this)));
        actualTokenAmounts = new uint256[](2);
        if (kyberNft == 0) return actualTokenAmounts;

        _withdrawFromFarm(_erc20Vault());

        uint128 liquidity = tokenAmountsToLiquidity(tokenAmounts);
        if (liquidity == 0) return actualTokenAmounts;

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

        _depositIntoFarm();

        console2.log("W3", IERC20(_vaultTokens[0]).balanceOf(address(this)));
        console2.log("W4", IERC20(_vaultTokens[1]).balanceOf(address(this)));
    }

    function _pull(
        address to,
        uint256[] memory tokenAmounts,
        bytes memory options
    ) internal override returns (uint256[] memory actualTokenAmounts) {
        // KyberVault should have strictly 2 vault tokens
        _withdrawFromFarm(to);
        actualTokenAmounts = new uint256[](2);
        if (kyberNft == 0) return actualTokenAmounts;

        Options memory opts = _parseOptions(options);
        Pair memory amounts = _pullKyberNft(to, tokenAmounts, opts);
        actualTokenAmounts[0] = amounts.a0;
        actualTokenAmounts[1] = amounts.a1;
        _depositIntoFarm();
    }

    function _pullKyberNft(
        address to,
        uint256[] memory tokenAmounts,
        Options memory opts
    ) internal returns (Pair memory) {
        uint128 liquidityToPull;
        // scope the code below to avoid stack-too-deep exception
        {
            (IBasePositionManager.Position memory position, ) = _positionManager.positions(kyberNft);

            (uint160 sqrtPriceX96, , , ) = pool.getPoolState();
            liquidityToPull = kyberHelper.tokenAmountsToMaximalLiquidity(
                sqrtPriceX96,
                position.tickLower,
                position.tickUpper,
                tokenAmounts[0],
                tokenAmounts[1]
            );
            liquidityToPull = position.liquidity < liquidityToPull ? position.liquidity : liquidityToPull;
        }

        uint256 amount0;
        uint256 amount1;

        if (liquidityToPull != 0) {
            Pair memory minAmounts = Pair({a0: opts.amount0Min, a1: opts.amount1Min});
            (amount0, amount1, ) = _positionManager.removeLiquidity(
                IBasePositionManager.RemoveLiquidityParams({
                    tokenId: kyberNft,
                    liquidity: liquidityToPull,
                    amount0Min: minAmounts.a0,
                    amount1Min: minAmounts.a1,
                    deadline: opts.deadline
                })
            );
        }

        (uint256 amount0Collected, uint256 amount1Collected) = _burnRTokens();

        amount0Collected += amount0;
        amount1Collected += amount1;   

        address[] memory tokens = _vaultTokens;
        IERC20(tokens[0]).safeTransfer(to, amount0Collected);
        IERC20(tokens[1]).safeTransfer(to, amount1Collected);
        amount0Collected = amount0Collected > tokenAmounts[0] ? tokenAmounts[0] : amount0Collected;
        amount1Collected = amount1Collected > tokenAmounts[1] ? tokenAmounts[1] : amount1Collected;
        return Pair({a0: amount0Collected, a1: amount1Collected});
    }

    function _erc20Vault() internal view returns (address) {
        IVaultRegistry registry = _vaultGovernance.internalParams().registry;
        address rootVault = registry.ownerOf(_nft);
        return IAggregateVault(rootVault).subvaultAt(0);
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
