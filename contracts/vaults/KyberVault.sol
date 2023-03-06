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
import "../libraries/external/FullMath.sol";
import "./IntegrationVault.sol";
import "../interfaces/utils/IKyberHelper.sol";

/// @notice Vault that interfaces Kyber protocol in the integration layer.
contract KyberVault is IKyberVault, IntegrationVault {
    using SafeERC20 for IERC20;

    /// @inheritdoc IKyberVault
    IPool public pool;
    /// @inheritdoc IKyberVault
    uint256 public kyberNft;

    IBasePositionManager public positionManager;
    IKyberHelper public kyberHelper;
    IRouter public router;

    IKyberSwapElasticLM public farm;
    IOracle public mellowOracle;
    uint256 public pid;

    bool public isLiquidityInFarm;

    // -------------------  EXTERNAL, VIEW  -------------------

    /// @inheritdoc IVault
    function tvl() public view returns (uint256[] memory minTokenAmounts, uint256[] memory maxTokenAmounts) {
        
        (minTokenAmounts, maxTokenAmounts) = kyberHelper.calcTvl();

    }

    /// @inheritdoc IntegrationVault
    function supportsInterface(bytes4 interfaceId) public view override(IERC165, IntegrationVault) returns (bool) {
        return super.supportsInterface(interfaceId) || (interfaceId == type(IKyberVault).interfaceId);
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
        positionManager = IKyberVaultGovernance(address(_vaultGovernance)).delayedProtocolParams().positionManager;
        farm = IKyberVaultGovernance(address(_vaultGovernance)).delayedProtocolParams().farm;
        router = IKyberVaultGovernance(address(_vaultGovernance)).delayedProtocolParams().router;
        pid = IKyberVaultGovernance(address(_vaultGovernance)).delayedStrategyParams(nft_).pid;
        mellowOracle = IKyberVaultGovernance(address(_vaultGovernance)).delayedProtocolParams().mellowOracle;
        pool = IPool(IFactory(positionManager.factory()).getPool(vaultTokens_[0], vaultTokens_[1], fee_));
        kyberHelper = IKyberHelper(kyberHepler_);
    }

    function updateFarmInfo() external {
        farm = IKyberVaultGovernance(address(_vaultGovernance)).delayedProtocolParams().farm;
        pid = IKyberVaultGovernance(address(_vaultGovernance)).delayedStrategyParams(_nft).pid;
    }

    function _depositIntoFarm() internal {
        if (address(farm) == address(0) || kyberNft == 0) {
            return;
        }

        (IBasePositionManager.Position memory position, ) = positionManager.positions(kyberNft);
        if (position.liquidity == 0) {
            return;
        }

        positionManager.approve(address(farm), kyberNft);

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

        (, uint256[] memory rewardsPending, ) = farm.getUserInfo(kyberNft, pid);

        isLiquidityInFarm = false;

        uint256[] memory nftIds = new uint256[](1);
        nftIds[0] = kyberNft;

        uint256[] memory liqs = new uint256[](1);
        (IBasePositionManager.Position memory position, ) = positionManager.positions(kyberNft);
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
                    IERC20(rewardTokens[i]).transfer(to, rewardsPending[i]);
                }
            }
            if (!exists) {
                bytes memory path = IKyberVaultGovernance(address(_vaultGovernance)).delayedStrategyParams(_nft).paths[
                    pointer
                ];

                uint256 toSwap = IERC20(rewardTokens[i]).balanceOf(address(this));

                if (toSwap > 0) {
                    IERC20(rewardTokens[i]).approve(address(router), toSwap);

                    address lastToken = kyberHelper.toAddress(path, path.length - 20);

                    uint256 received = router.swapExactInput(
                        IRouter.ExactInputParams({
                            path: path,
                            recipient: address(this),
                            deadline: block.timestamp + 1,
                            amountIn: toSwap,
                            minAmountOut: 0
                        })
                    );

                    IERC20(lastToken).transfer(to, received);
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
        require(msg.sender == address(positionManager) && _isStrategy(operator), ExceptionsLibrary.FORBIDDEN);
        (, IBasePositionManager.PoolInfo memory poolInfo) = positionManager.positions(tokenId);

        // new position should have vault tokens
        require(
            poolInfo.token0 == _vaultTokens[0] &&
                poolInfo.token1 == _vaultTokens[1] &&
                poolInfo.fee == pool.swapFeeUnits(),
            ExceptionsLibrary.INVALID_TOKEN
        );

        if (kyberNft != 0) {
            _withdrawFromFarm(_erc20Vault());
            (IBasePositionManager.Position memory position, ) = positionManager.positions(tokenId);
            require(position.liquidity == 0 && position.rTokenOwed == 0, ExceptionsLibrary.INVALID_VALUE);
            // return previous kyber position nft
            positionManager.transferFrom(address(this), from, kyberNft);
        }

        kyberNft = tokenId;

        _depositIntoFarm();

        return this.onERC721Received.selector;
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
        actualTokenAmounts = new uint256[](2);
        if (kyberNft == 0) return actualTokenAmounts;

        _withdrawFromFarm(_erc20Vault());

        if (kyberHelper.tokenAmountsToLiquidity(tokenAmounts, pool, kyberNft) == 0) return actualTokenAmounts;

        address[] memory tokens = _vaultTokens;
        for (uint256 i = 0; i < tokens.length; ++i) {
            IERC20(tokens[i]).safeIncreaseAllowance(address(positionManager), tokenAmounts[i]);
        }

        Options memory opts = _parseOptions(options);

        (, actualTokenAmounts[0], actualTokenAmounts[1], ) = positionManager.addLiquidity(
            IBasePositionManager.IncreaseLiquidityParams({
                tokenId: kyberNft,
                amount0Desired: tokenAmounts[0],
                amount1Desired: tokenAmounts[1],
                amount0Min: opts.amount0Min,
                amount1Min: opts.amount1Min,
                deadline: opts.deadline
            })
        );

        for (uint256 i = 0; i < tokens.length; ++i) {
            IERC20(tokens[i]).safeApprove(address(positionManager), 0);
        }

        _depositIntoFarm();
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
        (actualTokenAmounts[0], actualTokenAmounts[1]) = _pullKyberNft(to, tokenAmounts, opts);
        _depositIntoFarm();
    }

    function _pullKyberNft(
        address to,
        uint256[] memory tokenAmounts,
        Options memory opts
    ) internal returns (uint256, uint256) {

        uint256 amount0Collected;
        uint256 amount1Collected;

        bytes[] memory data = kyberHelper.getBytesToMulticall(tokenAmounts, opts);
        if (data.length > 0) {
            uint256 oldBalance0 = IERC20(_vaultTokens[0]).balanceOf(address(this));
            uint256 oldBalance1 = IERC20(_vaultTokens[1]).balanceOf(address(this));

            positionManager.multicall(data);

            uint256 newBalance0 = IERC20(_vaultTokens[0]).balanceOf(address(this));
            uint256 newBalance1 = IERC20(_vaultTokens[1]).balanceOf(address(this));

            amount0Collected = newBalance0 - oldBalance0;
            amount1Collected = newBalance1 - oldBalance1;
        }

        IERC20(_vaultTokens[0]).safeTransfer(to, amount0Collected);
        IERC20(_vaultTokens[1]).safeTransfer(to, amount1Collected);
        amount0Collected = amount0Collected > tokenAmounts[0] ? tokenAmounts[0] : amount0Collected;
        amount1Collected = amount1Collected > tokenAmounts[1] ? tokenAmounts[1] : amount1Collected;
        return (amount0Collected, amount1Collected);
    }

    function _erc20Vault() internal view returns (address) {
        address rootVault = _vaultGovernance.internalParams().registry.ownerOf(_nft);
        return IAggregateVault(rootVault).subvaultAt(0);
    }
}
