// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../interfaces/vaults/IERC20Vault.sol";
import "../interfaces/vaults/IIntegrationVault.sol";

import "../interfaces/utils/ILpCallback.sol";

import "../adapters/IAdapter.sol";

import "../libraries/ExceptionsLibrary.sol";
import "../libraries/UniswapCalculations.sol";

import "../libraries/external/FullMath.sol";
import "../libraries/external/LiquidityAmounts.sol";
import "../libraries/external/TickMath.sol";

import "../utils/DefaultAccessControlLateInit.sol";

contract BaseAMMStrategy is DefaultAccessControlLateInit, ILpCallback {
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
        int24 maxTickDeviation;
        uint256 minCapitalRatioDeviationX96;
        uint256[] minSwapAmounts;
        uint256 maxCapitalRemainderRatioX96;
        uint128 initialLiquidity;
    }

    struct ImmutableParams {
        IAdapter adapter;
        address pool;
        IERC20Vault erc20Vault;
        IIntegrationVault[] ammVaults;
    }

    struct Storage {
        ImmutableParams immutableParams;
        MutableParams mutableParams;
    }

    uint256 public constant Q96 = 2**96;

    bytes32 public constant STORAGE_SLOT = keccak256("strategy.storage");

    function _contractStorage() internal pure returns (Storage storage s) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            s.slot := slot
        }
    }

    function initialize(
        address admin,
        ImmutableParams memory immutableParams,
        MutableParams memory mutableParams
    ) external {
        _contractStorage().immutableParams = immutableParams;
        _contractStorage().mutableParams = mutableParams;
        DefaultAccessControlLateInit.init(admin);
    }

    function updateMutableParams(MutableParams memory mutableParams) external {
        _requireAdmin();
        _contractStorage().mutableParams = mutableParams;
    }

    function getMutableParams() public view returns (MutableParams memory) {
        return _contractStorage().mutableParams;
    }

    function getImmutableParams() public view returns (ImmutableParams memory) {
        return _contractStorage().immutableParams;
    }

    function getCurrentState(Storage memory s) public view returns (Position[] memory currentState) {
        IIntegrationVault[] memory ammVaults = s.immutableParams.ammVaults;
        currentState = new Position[](ammVaults.length);
        (uint160 sqrtPriceX96, ) = s.immutableParams.adapter.slot0EnsureNoMEV(
            s.immutableParams.pool,
            s.mutableParams.securityParams
        );
        uint256 priceX96 = FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, Q96);

        uint256 totalCapitalInToken1 = 0;
        for (uint256 i = 0; i < ammVaults.length; i++) {
            (uint256[] memory tvl, ) = ammVaults[i].tvl();
            uint256 capitalInToken1 = FullMath.mulDiv(tvl[0], priceX96, Q96) + tvl[1];
            totalCapitalInToken1 += capitalInToken1;
            currentState[i].capitalRatioX96 = capitalInToken1;
            (currentState[i].tickLower, currentState[i].tickUpper, ) = s.immutableParams.adapter.positionInfo(
                s.immutableParams.adapter.tokenId(address(ammVaults[i]))
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
            (bool success, ) = address(s.immutableParams.adapter).delegatecall(
                abi.encodeWithSelector(IAdapter.compound.selector, s.immutableParams.ammVaults[i])
            );
            require(success, ExceptionsLibrary.INVALID_STATE);
        }
    }

    function _positionsRebalance(
        Position[] memory targetState,
        Position[] memory currentState,
        Storage memory s
    ) private {
        IIntegrationVault[] memory ammVaults = s.immutableParams.ammVaults;
        require(ammVaults.length == targetState.length, ExceptionsLibrary.INVALID_LENGTH);
        IERC20Vault erc20Vault = s.immutableParams.erc20Vault;
        address pool = s.immutableParams.pool;
        address[] memory tokens = erc20Vault.vaultTokens();
        for (uint256 i = 0; i < currentState.length; i++) {
            if (
                currentState[i].tickLower != targetState[i].tickLower ||
                currentState[i].tickUpper != targetState[i].tickUpper
            ) {
                (, uint256[] memory pullingAmounts) = ammVaults[i].tvl();
                pullingAmounts[0] <<= 1;
                pullingAmounts[1] <<= 1;
                ammVaults[i].pull(address(erc20Vault), tokens, pullingAmounts, "");
                (bool success, bytes memory data) = address(s.immutableParams.adapter).delegatecall(
                    abi.encodeWithSelector(
                        IAdapter.mint.selector,
                        pool,
                        targetState[i].tickLower,
                        targetState[i].tickUpper,
                        s.mutableParams.initialLiquidity,
                        address(this)
                    )
                );
                if (!success) revert(ExceptionsLibrary.INVALID_STATE);
                uint256 newNft = abi.decode(data, (uint256));
                (success, ) = address(s.immutableParams.adapter).delegatecall(
                    abi.encodeWithSelector(IAdapter.swapNft.selector, address(this), ammVaults[i], newNft)
                );
                if (!success) revert(ExceptionsLibrary.INVALID_STATE);
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
        address[] memory tokens = erc20Vault.vaultTokens();
        if (swapData.amountIn < s.mutableParams.minSwapAmounts[swapData.tokenInIndex]) return;
        address tokenIn = tokens[swapData.tokenInIndex];
        address tokenOut = tokens[swapData.tokenInIndex ^ 1];
        (uint160 sqrtPriceX96, int24 tick) = s.immutableParams.adapter.slot0(s.immutableParams.pool);
        uint256 priceBeforeX96 = FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, Q96);
        if (swapData.tokenInIndex == 1) {
            priceBeforeX96 = FullMath.mulDiv(Q96, Q96, priceBeforeX96);
        }
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
        require(tokenOutDelta >= swapData.amountOutMin, ExceptionsLibrary.LIMIT_UNDERFLOW);

        uint256 swapPriceX96 = FullMath.mulDiv(tokenOutDelta, Q96, tokenInDelta);
        require(
            swapPriceX96 >= FullMath.mulDiv(priceBeforeX96, Q96 - s.mutableParams.maxPriceSlippageX96, Q96),
            ExceptionsLibrary.LIMIT_OVERFLOW
        );

        (, int24 tickAfter) = s.immutableParams.adapter.slot0(s.immutableParams.pool);
        if (tick != tickAfter) {
            if (tick + s.mutableParams.maxTickDeviation < tickAfter) revert(ExceptionsLibrary.LIMIT_OVERFLOW);
            if (tickAfter + s.mutableParams.maxTickDeviation < tick) revert(ExceptionsLibrary.LIMIT_OVERFLOW);
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
        {
            uint256 maxAllowedCapitalOnERC20Vault = FullMath.mulDiv(
                capitalInToken1,
                s.mutableParams.maxCapitalRemainderRatioX96,
                Q96
            );
            (uint256[] memory erc20Tvl, ) = s.immutableParams.erc20Vault.tvl();
            uint256 erc20Capital = FullMath.mulDiv(erc20Tvl[0], priceX96, Q96) + erc20Tvl[1];
            require(erc20Capital <= maxAllowedCapitalOnERC20Vault, "Too much liquidity on erc20Vault");
        }
    }

    function _ratioRebalance(Position[] memory targetState, Storage memory s) private {
        uint256 n = s.immutableParams.ammVaults.length;
        (uint160 sqrtRatioX96, ) = s.immutableParams.adapter.slot0(s.immutableParams.pool);
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
        _requireAtLeastOperator();
        Storage memory s = _contractStorage();
        _compound(s);
        _positionsRebalance(targetState, getCurrentState(s), s);
        _swap(swapData, s);
        _ratioRebalance(targetState, s);
    }

    function depositCallback() external {
        ImmutableParams memory immutableParams = _contractStorage().immutableParams;
        IERC20Vault erc20Vault = immutableParams.erc20Vault;
        IIntegrationVault[] memory ammVaults = immutableParams.ammVaults;
        uint256 n = ammVaults.length;
        uint256[][] memory tvls = new uint256[][](n);
        uint256[] memory totalTvl = new uint256[](2);
        for (uint256 i = 0; i < n; i++) {
            (uint256[] memory tvl, ) = ammVaults[i].tvl();
            totalTvl[0] += tvl[0];
            totalTvl[1] += tvl[1];
            tvls[i] = tvl;
        }
        (uint256[] memory erc20Tvl, ) = erc20Vault.tvl();
        address[] memory tokens = erc20Vault.vaultTokens();
        for (uint256 i = 0; i < n; i++) {
            uint256[] memory amounts = new uint256[](2);
            uint256[] memory tvl = tvls[i];
            bool doesPullRequred = false;
            for (uint256 j = 0; j < 2; j++) {
                if (totalTvl[j] == 0) continue;
                amounts[j] = FullMath.mulDiv(erc20Tvl[j], tvl[j], totalTvl[j]);
                if (amounts[j] > 0) doesPullRequred = true;
            }
            if (doesPullRequred) {
                uint256[] memory actualAmounts = erc20Vault.pull(address(ammVaults[i]), tokens, amounts, "");
                for (uint256 j = 0; j < 2; j++) {
                    totalTvl[j] -= tvl[j];
                    erc20Tvl[j] -= actualAmounts[j];
                }
            }
        }
    }

    function withdrawCallback() external {}
}
