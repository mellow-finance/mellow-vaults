// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../interfaces/vaults/IERC20Vault.sol";
import "../interfaces/vaults/IIntegrationVault.sol";

import "../adapters/IAdapter.sol";

import "../libraries/ExceptionsLibrary.sol";
import "../libraries/UniswapCalculations.sol";

import "../libraries/external/FullMath.sol";
import "../libraries/external/LiquidityAmounts.sol";
import "../libraries/external/TickMath.sol";

contract BaseAMMStrategy {
    struct Position {
        int24 tickLower;
        int24 tickUpper;
        uint256 capitalRatioX96;
    }

    struct SwapData {
        address router;
        uint256 tokenInIndex;
        uint256 amountIn;
        uint256 amountOutMin;
        bytes data;
    }

    struct MutableParams {
        bytes securityParams;
        uint256 maxPriceSlippageX96;
        uint256 maxPriceDeviationX96;
        uint256 minCapitalRatioDeviationX96;
        uint256[] minSwapAmounts;
    }

    struct ImmutableParams {
        address pool;
        IERC20Vault erc20Vault;
        IIntegrationVault[] ammVaults;
    }

    struct Storage {
        ImmutableParams immutableParams;
        MutableParams mutableParams;
    }

    uint256 public constant Q96 = 2**96;

    IAdapter public adapter;
    Storage private _s;

    function getCurrentState(Storage memory s) public view returns (Position[] memory currentState) {
        IIntegrationVault[] memory ammVaults = s.immutableParams.ammVaults;
        currentState = new Position[](ammVaults.length);
        (uint160 sqrtPriceX96, ) = adapter.slot0EnsureNoMEV(s.immutableParams.pool, s.mutableParams.securityParams);
        uint256 priceX96 = FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, Q96);

        uint256 totalCapitalInToken1 = 0;
        for (uint256 i = 0; i < ammVaults.length; i++) {
            (uint256[] memory tvl, ) = ammVaults[i].tvl();
            uint256 capitalInToken1 = FullMath.mulDiv(tvl[0], priceX96, Q96) + tvl[1];
            totalCapitalInToken1 += capitalInToken1;
            currentState[i].capitalRatioX96 = capitalInToken1;
            (currentState[i].tickLower, currentState[i].tickUpper, ) = adapter.positionInfo(
                adapter.tokenId(address(ammVaults[i]))
            );
        }

        {
            (uint256[] memory tvl, ) = s.immutableParams.erc20Vault.tvl();
            totalCapitalInToken1 += FullMath.mulDiv(tvl[0], priceX96, Q96) + tvl[1];
        }

        require(totalCapitalInToken1 > 0, ExceptionsLibrary.INVALID_VALUE);

        for (uint256 i = 0; i < ammVaults.length; i++) {
            currentState[i].capitalRatioX96 = FullMath.mulDiv(
                currentState[i].capitalRatioX96,
                Q96,
                totalCapitalInToken1
            );
        }
    }

    function _compound(Storage memory s) private {
        for (uint256 i = 0; i < s.immutableParams.ammVaults.length; i++) {
            (bool success, ) = address(adapter).delegatecall(
                abi.encodeWithSelector(IAdapter.compound.selector, s.immutableParams.ammVaults[i])
            );
            require(success);
        }
    }

    function _positionsRebalance(
        Position[] memory targetState,
        Position[] memory currentState,
        Storage memory s
    ) private {
        IIntegrationVault[] memory ammVaults = s.immutableParams.ammVaults;
        require(ammVaults.length == targetState.length);
        IERC20Vault erc20Vault = s.immutableParams.erc20Vault;
        address pool = s.immutableParams.pool;
        address[] memory tokens = erc20Vault.vaultTokens();
        for (uint256 i = 0; i < currentState.length; i++) {
            if (
                currentState[i].tickLower != targetState[i].tickLower ||
                currentState[i].tickUpper != targetState[i].tickUpper
            ) {
                (, uint256[] memory tvl) = ammVaults[i].tvl();
                ammVaults[i].pull(address(erc20Vault), tokens, tvl, "");
                (bool success, bytes memory data) = address(adapter).delegatecall(
                    abi.encodeWithSelector(
                        IAdapter.mintWithDust.selector,
                        pool,
                        targetState[i].tickLower,
                        targetState[i].tickUpper,
                        address(this)
                    )
                );
                if (!success) revert();
                uint256 newNft = abi.decode(data, (uint256));
                (success, ) = address(adapter).delegatecall(
                    abi.encodeWithSelector(IAdapter.swapNft.selector, address(this), ammVaults[i], newNft)
                );
                if (!success) revert();
            } else if (currentState[i].capitalRatioX96 > targetState[i].capitalRatioX96) {
                (, uint256[] memory tvl) = ammVaults[i].tvl();
                for (uint256 j = 0; j < tvl.length; j++) {
                    tvl[j] = FullMath.mulDiv(
                        tvl[j],
                        currentState[i].capitalRatioX96 - targetState[i].capitalRatioX96,
                        currentState[i].capitalRatioX96
                    );
                }
                ammVaults[i].pull(address(erc20Vault), tokens, tvl, "");
            }
        }
    }

    function _swap(SwapData calldata swapData, Storage memory s) private {
        IERC20Vault erc20Vault = s.immutableParams.erc20Vault;
        address pool = s.immutableParams.pool;
        address[] memory tokens = erc20Vault.vaultTokens();
        if (swapData.amountIn < s.mutableParams.minSwapAmounts[swapData.tokenInIndex]) return;
        address tokenIn = tokens[swapData.tokenInIndex];
        address tokenOut = tokens[swapData.tokenInIndex ^ 1];
        (uint160 sqrtPriceX96, ) = adapter.slot0(pool);
        uint256 priceBeforeX96 = FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, Q96);
        uint256 tokenInBefore = IERC20(tokenIn).balanceOf(address(erc20Vault));
        uint256 tokenOutBefore = IERC20(tokenOut).balanceOf(address(erc20Vault));

        erc20Vault.externalCall(
            tokenIn,
            IERC20.approve.selector,
            abi.encode(address(swapData.router), swapData.amountIn)
        );
        erc20Vault.externalCall(address(swapData.router), bytes4(swapData.data[:4]), swapData.data[4:]);
        erc20Vault.externalCall(tokenIn, IERC20.approve.selector, abi.encode(address(swapData.router), 0));

        uint256 tokenInDelta = tokenInBefore - IERC20(tokenIn).balanceOf(address(erc20Vault));
        uint256 tokenOutDelta = IERC20(tokenOut).balanceOf(address(erc20Vault)) - tokenOutBefore;
        require(tokenOutDelta >= swapData.amountOutMin);

        uint256 swapPriceX96 = FullMath.mulDiv(tokenInDelta, Q96, tokenOutDelta);
        if (swapData.tokenInIndex == 1) {
            priceBeforeX96 = FullMath.mulDiv(Q96, Q96, priceBeforeX96);
        }
        require(swapPriceX96 >= FullMath.mulDiv(priceBeforeX96, Q96 - s.mutableParams.maxPriceSlippageX96, Q96));

        (uint160 sqrtPriceAfterX96, ) = adapter.slot0(pool);
        if (sqrtPriceX96 != sqrtPriceAfterX96) {
            if (sqrtPriceX96 + s.mutableParams.maxPriceDeviationX96 < sqrtPriceAfterX96) revert();
            if (sqrtPriceAfterX96 + s.mutableParams.maxPriceDeviationX96 < sqrtPriceX96) revert();
        }
    }

    function _pushIntoPositions(
        Position[] memory targetState,
        Storage memory s,
        uint256[][] memory tvls,
        uint256 priceX96,
        uint256 minCapitalDeviationInToken1,
        uint256 capitalInToken1,
        uint160 sqrtRatioX96,
        address[] memory tokens
    ) private {
        for (uint256 i = 0; i < s.immutableParams.ammVaults.length; i++) {
            uint256 requiredCapitalInToken1;
            {
                uint256[] memory tvl = tvls[i];
                uint256 vaultCapitalInToken1 = FullMath.mulDiv(tvl[0], priceX96, Q96) + tvl[1];
                uint256 expectedCapitalInToken1 = FullMath.mulDiv(targetState[i].capitalRatioX96, capitalInToken1, Q96);
                if (vaultCapitalInToken1 + minCapitalDeviationInToken1 > expectedCapitalInToken1) continue;
                requiredCapitalInToken1 = expectedCapitalInToken1 - vaultCapitalInToken1;
            }
            if (requiredCapitalInToken1 == 0) continue;

            uint256 targetRatioOfToken1X96 = UniswapCalculations.calculateTargetRatioOfToken1(
                UniswapCalculations.PositionParams({
                    sqrtLowerPriceX96: TickMath.getSqrtRatioAtTick(targetState[i].tickLower),
                    sqrtUpperPriceX96: TickMath.getSqrtRatioAtTick(targetState[i].tickUpper),
                    sqrtPriceX96: sqrtRatioX96
                }),
                priceX96
            );
            uint256[] memory amounts = new uint256[](2);
            amounts[1] = FullMath.mulDiv(targetRatioOfToken1X96, requiredCapitalInToken1, Q96);
            amounts[0] = FullMath.mulDiv(requiredCapitalInToken1 - amounts[1], Q96, priceX96);
            s.immutableParams.erc20Vault.pull(address(s.immutableParams.ammVaults[i]), tokens, amounts, "");
        }
    }

    function _ratioRebalance(Position[] memory targetState, Storage memory s) private {
        uint256 n = s.immutableParams.ammVaults.length;
        (uint160 sqrtRatioX96, ) = adapter.slot0(s.immutableParams.pool);
        uint256[][] memory tvls = new uint256[][](n);
        (uint256[] memory totalTvl, ) = s.immutableParams.erc20Vault.tvl();
        for (uint256 i = 0; i < n; i++) {
            (uint256[] memory tvl, ) = s.immutableParams.ammVaults[i].tvl();
            totalTvl[0] += tvl[0];
            totalTvl[1] += tvl[1];
            tvls[i] = tvl;
        }

        uint256 priceX96 = FullMath.mulDiv(sqrtRatioX96, sqrtRatioX96, Q96);
        uint256 capitalInToken1 = FullMath.mulDiv(totalTvl[0], priceX96, Q96) + totalTvl[1];
        _pushIntoPositions(
            targetState,
            s,
            tvls,
            priceX96,
            FullMath.mulDiv(s.mutableParams.minCapitalRatioDeviationX96, capitalInToken1, Q96),
            capitalInToken1,
            sqrtRatioX96,
            s.immutableParams.erc20Vault.vaultTokens()
        );
    }

    function rebalance(Position[] memory targetState, SwapData calldata swapData) external {
        Storage memory s = _s;
        _compound(s);
        _positionsRebalance(targetState, getCurrentState(s), s);
        _swap(swapData, s);
        _ratioRebalance(targetState, s);
    }
}
