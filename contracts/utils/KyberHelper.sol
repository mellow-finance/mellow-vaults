// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.9;

import "../interfaces/external/kyber/periphery/helpers/TicksFeeReader.sol";
import "../interfaces/external/kyber/IKyberSwapElasticLM.sol";

import "../interfaces/utils/IKyberHelper.sol";

import "../interfaces/vaults/IKyberVault.sol";
import "../interfaces/vaults/IKyberVaultGovernance.sol";

import "../libraries/CommonLibrary.sol";
import "../libraries/external/LiquidityMath.sol";
import "../libraries/external/QtyDeltaMath.sol";
import "../libraries/external/TickMath.sol";

contract KyberHelper is IKyberHelper {
    IBasePositionManager public immutable positionManager;
    TicksFeesReader public immutable ticksManager;

    constructor(IBasePositionManager positionManager_, TicksFeesReader ticksManager_) {
        require(address(positionManager_) != address(0));
        positionManager = positionManager_;
        ticksManager = ticksManager_;
    }

    function liquidityToTokenAmounts(
        uint128 liquidity,
        IPool pool,
        uint256 kyberNft
    ) external view returns (uint256[] memory tokenAmounts) {
        tokenAmounts = new uint256[](2);

        (IBasePositionManager.Position memory position, ) = positionManager.positions(kyberNft);

        (uint160 sqrtPriceX96, , , ) = pool.getPoolState();
        uint160 sqrtPriceAX96 = TickMath.getSqrtRatioAtTick(position.tickLower);
        uint160 sqrtPriceBX96 = TickMath.getSqrtRatioAtTick(position.tickUpper);

        (tokenAmounts[0], tokenAmounts[1]) = QtyDeltaMath.calcRequiredQtys(
            sqrtPriceX96,
            sqrtPriceAX96,
            sqrtPriceBX96,
            liquidity,
            true
        );
    }

    function tokenAmountsToLiquidity(
        uint256[] memory tokenAmounts,
        IPool pool,
        uint256 kyberNft
    ) external view returns (uint128 liquidity) {
        (IBasePositionManager.Position memory position, ) = positionManager.positions(kyberNft);

        (uint160 sqrtPriceX96, , , ) = pool.getPoolState();
        uint160 sqrtPriceAX96 = TickMath.getSqrtRatioAtTick(position.tickLower);
        uint160 sqrtPriceBX96 = TickMath.getSqrtRatioAtTick(position.tickUpper);

        liquidity = LiquidityMath.getLiquidityFromQties(
            sqrtPriceX96,
            sqrtPriceAX96,
            sqrtPriceBX96,
            tokenAmounts[0],
            tokenAmounts[1]
        );
    }

    function tokenAmountsToMaximalLiquidity(
        uint160 sqrtRatioX96,
        int24 tickLower,
        int24 tickUpper,
        uint256 amount0,
        uint256 amount1
    ) public pure returns (uint128 liquidity) {
        uint160 sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(tickLower);
        uint160 sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(tickUpper);

        if (sqrtRatioX96 <= sqrtRatioAX96) {
            LiquidityMath.getLiquidityFromQty0(sqrtRatioAX96, sqrtRatioBX96, amount0);
        } else if (sqrtRatioX96 < sqrtRatioBX96) {
            uint128 liquidity0 = LiquidityMath.getLiquidityFromQty0(sqrtRatioX96, sqrtRatioBX96, amount0);
            uint128 liquidity1 = LiquidityMath.getLiquidityFromQty1(sqrtRatioAX96, sqrtRatioX96, amount1);

            liquidity = liquidity0 > liquidity1 ? liquidity0 : liquidity1;
        } else {
            liquidity = LiquidityMath.getLiquidityFromQty1(sqrtRatioAX96, sqrtRatioBX96, amount1);
        }
    }

    /// @dev returns with "Invalid Token ID" for non-existent nfts
    function calculateTvlBySqrtPriceX96(
        IPool pool,
        uint256 kyberNft,
        uint160 sqrtPriceX96
    ) public view returns (uint256[] memory tokenAmounts) {
        tokenAmounts = new uint256[](2);

        (IBasePositionManager.Position memory position, ) = positionManager.positions(kyberNft);

        uint160 sqrtPriceAX96 = TickMath.getSqrtRatioAtTick(position.tickLower);
        uint160 sqrtPriceBX96 = TickMath.getSqrtRatioAtTick(position.tickUpper);

        (tokenAmounts[0], tokenAmounts[1]) = QtyDeltaMath.calcRequiredQtys(
            sqrtPriceX96,
            sqrtPriceAX96,
            sqrtPriceBX96,
            position.liquidity,
            true
        );

        (uint256 feeAmount0, uint256 feeAmount1) = ticksManager.getTotalFeesOwedToPosition(
            positionManager,
            pool,
            kyberNft
        );

        tokenAmounts[0] += feeAmount0;
        tokenAmounts[1] += feeAmount1;
    }

    function calcTvl() external view returns (uint256[] memory minTokenAmounts, uint256[] memory maxTokenAmounts) {
        IKyberVault vault = IKyberVault(msg.sender);

        uint256 kyberNft = vault.kyberNft();
        if (kyberNft == 0) return (new uint256[](2), new uint256[](2));
        IKyberSwapElasticLM farm = vault.farm();

        address[] memory _vaultTokens = vault.vaultTokens();

        {
            IPool pool = vault.pool();
            uint160 sqrtPriceX96;
            (sqrtPriceX96, , , ) = pool.getPoolState();
            minTokenAmounts = calculateTvlBySqrtPriceX96(pool, kyberNft, sqrtPriceX96);
        }

        if (address(farm) != address(0)) {
            uint256 pointer = 0;

            address[] memory rewardTokens;
            uint256[] memory rewardsPending;

            {
                uint256 pid = vault.pid();
                (, , , , , , , rewardTokens, ) = farm.getPoolInfo(pid);
                (, rewardsPending, ) = farm.getUserInfo(kyberNft, pid);
            }

            for (uint256 i = 0; i < rewardTokens.length; ++i) {
                bool exists = false;
                for (uint256 j = 0; j < _vaultTokens.length; ++j) {
                    if (rewardTokens[i] == _vaultTokens[j]) {
                        exists = true;
                        minTokenAmounts[j] += rewardsPending[i];
                    }
                }
                if (!exists) {
                    address lastToken;

                    {
                        bytes memory path = IKyberVaultGovernance(address(vault.vaultGovernance()))
                            .delayedStrategyParams(vault.nft())
                            .paths[pointer];
                        lastToken = toAddress(path, path.length - 20);
                    }

                    uint256[] memory pricesX96;

                    {
                        IOracle mellowOracle = vault.mellowOracle();
                        (pricesX96, ) = mellowOracle.priceX96(rewardTokens[i], lastToken, 0x20);
                    }

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

    function toAddress(bytes memory _bytes, uint256 _start) public pure returns (address) {
        require(_start + 20 >= _start, "toAddress_overflow");
        require(_bytes.length >= _start + 20, "toAddress_outOfBounds");
        address tempAddress;

        assembly {
            tempAddress := div(mload(add(add(_bytes, 0x20), _start)), 0x1000000000000000000000000)
        }

        return tempAddress;
    }

    function getBytesToMulticall(uint256[] memory tokenAmounts, IKyberVault.Options memory opts)
        external
        view
        returns (bytes[] memory data)
    {
        IKyberVault vault = IKyberVault(msg.sender);

        uint256 kyberNft = vault.kyberNft();
        IPool pool = vault.pool();
        address[] memory _vaultTokens = vault.vaultTokens();

        uint128 liquidityToPull;
        // scope the code below to avoid stack-too-deep exception
        {
            (IBasePositionManager.Position memory position, ) = positionManager.positions(kyberNft);

            (uint160 sqrtPriceX96, , , ) = pool.getPoolState();
            liquidityToPull = tokenAmountsToMaximalLiquidity(
                sqrtPriceX96,
                position.tickLower,
                position.tickUpper,
                tokenAmounts[0],
                tokenAmounts[1]
            );
            liquidityToPull = position.liquidity < liquidityToPull ? position.liquidity : liquidityToPull;
        }

        if (liquidityToPull == 0) {
            return new bytes[](0);
        }

        if (ticksManager.getTotalRTokensOwedToPosition(positionManager, pool, kyberNft) > 0) {
            data = new bytes[](4);

            data[0] = abi.encodePacked(
                IBasePositionManager.removeLiquidity.selector,
                abi.encode(kyberNft, liquidityToPull, opts.amount0Min, opts.amount1Min, opts.deadline)
            );

            data[1] = abi.encodePacked(
                IBasePositionManager.burnRTokens.selector,
                abi.encode(kyberNft, 0, 0, block.timestamp + 1)
            );

            data[2] = abi.encodePacked(
                IRouterTokenHelper.transferAllTokens.selector,
                abi.encode(_vaultTokens[0], uint256(0), msg.sender)
            );
            data[3] = abi.encodePacked(
                IRouterTokenHelper.transferAllTokens.selector,
                abi.encode(_vaultTokens[1], uint256(0), msg.sender)
            );
        } else {
            data = new bytes[](3);

            data[0] = abi.encodePacked(
                IBasePositionManager.removeLiquidity.selector,
                abi.encode(kyberNft, liquidityToPull, opts.amount0Min, opts.amount1Min, opts.deadline)
            );

            data[1] = abi.encodePacked(
                IRouterTokenHelper.transferAllTokens.selector,
                abi.encode(_vaultTokens[0], uint256(0), msg.sender)
            );
            data[2] = abi.encodePacked(
                IRouterTokenHelper.transferAllTokens.selector,
                abi.encode(_vaultTokens[1], uint256(0), msg.sender)
            );
        }
    }
}
