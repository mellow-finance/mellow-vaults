// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "forge-std/src/Script.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../interfaces/utils/ILpCallback.sol";
import "../interfaces/vaults/IERC20Vault.sol";
import "../interfaces/vaults/IRamsesV2Vault.sol";
import "../interfaces/vaults/IRamsesV2VaultGovernance.sol";
import "../interfaces/utils/ILpCallback.sol";

import "../interfaces/external/ramses/libraries/OracleLibrary.sol";
import "../libraries/external/FullMath.sol";
import "../libraries/ExceptionsLibrary.sol";

import "../utils/DefaultAccessControlLateInit.sol";

contract GRamsesStrategy is DefaultAccessControlLateInit, ILpCallback {
    using SafeERC20 for IERC20;

    struct ImmutableParams {
        uint24 fee;
        IRamsesV2Pool pool;
        IERC20Vault erc20Vault;
        IRamsesV2Vault lowerVault;
        IRamsesV2Vault upperVault;
        address router;
        address[] tokens;
    }

    struct MutableParams {
        uint32 timespan;
        int24 maxTickDeviation;
        int24 intervalWidth;
        int24 priceImpactD6;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 maxRatioDeviationX96;
        uint256 swapSlippageD;
        uint256 swappingAmountsCoefficientD;
        uint256[] minSwapAmounts;
    }

    struct State {
        int24 lowerTick;
        int24 upperTick;
        uint256 ratioX96;
    }

    uint256 public constant Q96 = 2**96;
    uint256 public constant D9 = 1e9;
    uint256 public constant D6 = 1e6;

    IRamsesV2NonfungiblePositionManager public immutable positionManager;

    struct Storage {
        ImmutableParams immutableParams;
        MutableParams mutableParams;
    }

    bytes32 public constant STORAGE_POSITION = keccak256("strategy.storage");

    function _contractStorage() internal pure returns (Storage storage ds) {
        bytes32 position = STORAGE_POSITION;

        assembly {
            ds.slot := position
        }
    }

    constructor(IRamsesV2NonfungiblePositionManager positionManager_) {
        positionManager = positionManager_;
    }

    function initialize(address admin, ImmutableParams memory immutableParams) external {
        DefaultAccessControlLateInit.init(admin);
        _contractStorage().immutableParams = immutableParams;
        for (uint256 i = 0; i < 2; i++) {
            IERC20(immutableParams.tokens[i]).safeIncreaseAllowance(address(positionManager), type(uint256).max);
            immutableParams.erc20Vault.externalCall(
                immutableParams.tokens[i],
                IERC20.approve.selector,
                abi.encode(immutableParams.router, type(uint256).max)
            );
        }
    }

    function getImmutableParams() public view returns (ImmutableParams memory) {
        return _contractStorage().immutableParams;
    }

    function getMutableParams() public view returns (MutableParams memory) {
        return _contractStorage().mutableParams;
    }

    function ensureNoMEV(Storage memory s) public view {
        (int24 averageTick, , bool withFail) = OracleLibrary.consult(
            address(s.immutableParams.pool),
            s.mutableParams.timespan
        );
        require(!withFail, ExceptionsLibrary.INVALID_STATE);
        (, int24 spotTick, , , , , ) = s.immutableParams.pool.slot0();
        int24 delta = spotTick - averageTick;
        if (delta < 0) delta = -delta;
        require(delta <= s.mutableParams.maxTickDeviation, ExceptionsLibrary.LIMIT_OVERFLOW);
    }

    function calculateExpectedState(Storage memory s) public view returns (State memory state) {
        (, int24 tick, , , , , ) = s.immutableParams.pool.slot0();
        int24 width = s.mutableParams.intervalWidth;
        state.lowerTick = tick - (tick % width);
        if (state.lowerTick > tick) {
            state.lowerTick -= width;
        }
        state.upperTick = state.lowerTick + width;
        int24 deltaX2 = 2 * tick - state.lowerTick - state.upperTick;
        if (deltaX2 < 0) {
            state.lowerTick -= width;
            state.upperTick -= width;
            state.ratioX96 = Q96 - FullMath.mulDiv(Q96, uint24(width * 2 + deltaX2), uint24(width * 2));
        } else {
            state.ratioX96 = FullMath.mulDiv(Q96, uint24(width * 2 - deltaX2), uint24(width * 2));
        }
    }

    function getCurrentState(Storage memory s) public view returns (State memory state) {
        uint256 lowerPositionId = s.immutableParams.lowerVault.positionId();
        if (lowerPositionId != 0) {
            uint128 lowerLiquidity;
            (, , , , , state.lowerTick, state.upperTick, lowerLiquidity, , , , ) = positionManager.positions(
                lowerPositionId
            );
            uint128 upperLiquidity;
            (, , , , , , , upperLiquidity, , , , ) = positionManager.positions(
                s.immutableParams.upperVault.positionId()
            );
            state.ratioX96 = FullMath.mulDiv(Q96, lowerLiquidity, lowerLiquidity + upperLiquidity);
        }
    }

    function calculateTargetRatioOfToken1(Storage memory s, uint256 ratioX96)
        public
        view
        returns (uint256 targetRatioOfToken1X96)
    {
        uint256[] memory lowerAmountsQ96 = s.immutableParams.lowerVault.liquidityToTokenAmounts(uint128(ratioX96));
        uint256[] memory upperAmountsQ96 = s.immutableParams.upperVault.liquidityToTokenAmounts(
            uint128(Q96 - ratioX96)
        );
        uint256 amount0 = lowerAmountsQ96[0] + upperAmountsQ96[0];
        uint256 amount1 = lowerAmountsQ96[1] + upperAmountsQ96[1];
        targetRatioOfToken1X96 = FullMath.mulDiv(Q96, amount1, amount0 + amount1);
    }

    function updateMutableParams(MutableParams memory newMutableParams) external {
        _requireAdmin();
        Storage storage s = _contractStorage();
        s.mutableParams = newMutableParams;
    }

    function updateRouter(address newRouter) external {
        _requireAdmin();
        Storage storage s = _contractStorage();
        ImmutableParams memory immutableParams = s.immutableParams;
        for (uint256 i = 0; i < immutableParams.tokens.length; i++) {
            immutableParams.erc20Vault.externalCall(
                immutableParams.tokens[i],
                IERC20.approve.selector,
                abi.encode(immutableParams.router, 0)
            );
            immutableParams.erc20Vault.externalCall(
                immutableParams.tokens[i],
                IERC20.approve.selector,
                abi.encode(newRouter, type(uint256).max)
            );
        }
        s.immutableParams.router = newRouter;
    }

    function updateVaultFarms(IRamsesV2VaultGovernance.StrategyParams memory newStrategyParams) external {
        _requireAdmin();
        ImmutableParams memory immutableParams = getImmutableParams();
        IRamsesV2VaultGovernance ramsesGovernance = IRamsesV2VaultGovernance(
            address(immutableParams.lowerVault.vaultGovernance())
        );
        ramsesGovernance.setStrategyParams(immutableParams.lowerVault.nft(), newStrategyParams);
        ramsesGovernance.setStrategyParams(immutableParams.upperVault.nft(), newStrategyParams);
    }

    function rebalance(
        bytes calldata swapData,
        uint256 minAmountOutInCaseOfSwap,
        uint256 deadline
    ) external {
        _requireAtLeastOperator();
        require(block.timestamp <= deadline, ExceptionsLibrary.TIMESTAMP);
        Storage memory s = _contractStorage();
        ensureNoMEV(s);

        State memory expected = calculateExpectedState(s);
        State memory current = getCurrentState(s);
        if (current.lowerTick == current.upperTick || expected.lowerTick != current.lowerTick) {
            _drainLiquidity(s);

            uint256 lowerVaultNft = _mint(s, expected.lowerTick, expected.upperTick);
            uint256 upperVaultNft = _mint(
                s,
                expected.lowerTick + s.mutableParams.intervalWidth,
                expected.upperTick + s.mutableParams.intervalWidth
            );

            uint256 oldLowerVaultNft = s.immutableParams.lowerVault.positionId();
            uint256 oldUpperVaultNft = s.immutableParams.upperVault.positionId();

            if (oldLowerVaultNft != 0) {
                s.immutableParams.lowerVault.collectRewards();
                s.immutableParams.upperVault.collectRewards();
            }

            positionManager.safeTransferFrom(address(this), address(s.immutableParams.lowerVault), lowerVaultNft);
            positionManager.safeTransferFrom(address(this), address(s.immutableParams.upperVault), upperVaultNft);

            if (oldLowerVaultNft != 0) {
                positionManager.burn(oldLowerVaultNft);
                emit PositionBurned(oldLowerVaultNft);
                positionManager.burn(oldUpperVaultNft);
                emit PositionBurned(oldUpperVaultNft);
            }
        } else {
            if (expected.ratioX96 + s.mutableParams.maxRatioDeviationX96 < current.ratioX96) {
                _drainLiquidity(s);
            } else if (current.ratioX96 + s.mutableParams.maxRatioDeviationX96 < expected.ratioX96) {
                _drainLiquidity(s);
            }
        }

        _swapToTarget(s, expected, swapData, minAmountOutInCaseOfSwap);
        _pushIntoRamses(s, expected.ratioX96);

        emit Rebalance(tx.origin, msg.sender);
    }

    function calculateAmountsForSwap(
        uint256[] memory currentAmounts,
        int24 priceImpactD6,
        uint256 priceX96,
        uint256 targetRatioOfToken1X96
    ) public pure returns (uint256 tokenInIndex, uint256 amountIn) {
        uint256 targetRatioOfToken0X96 = Q96 - targetRatioOfToken1X96;
        uint256 currentRatioOfToken1X96 = FullMath.mulDiv(
            currentAmounts[1],
            Q96,
            currentAmounts[1] + FullMath.mulDiv(currentAmounts[0], priceX96, Q96)
        );

        uint256 feesX96 = FullMath.mulDiv(Q96, uint256(int256(priceImpactD6)), D6);

        if (currentRatioOfToken1X96 > targetRatioOfToken1X96) {
            tokenInIndex = 1;
            // (dx * y0 - dy * x0 * p) / (1 - dy * fee)
            uint256 invertedPriceX96 = FullMath.mulDiv(Q96, Q96, priceX96);
            amountIn = FullMath.mulDiv(
                FullMath.mulDiv(currentAmounts[1], targetRatioOfToken0X96, Q96) -
                    FullMath.mulDiv(targetRatioOfToken1X96, currentAmounts[0], invertedPriceX96),
                Q96,
                Q96 - FullMath.mulDiv(targetRatioOfToken1X96, feesX96, Q96)
            );
        } else {
            // (dy * x0 - dx * y0 / p) / (1 - dx * fee)
            tokenInIndex = 0;
            amountIn = FullMath.mulDiv(
                FullMath.mulDiv(currentAmounts[0], targetRatioOfToken1X96, Q96) -
                    FullMath.mulDiv(targetRatioOfToken0X96, currentAmounts[1], priceX96),
                Q96,
                Q96 - FullMath.mulDiv(targetRatioOfToken0X96, feesX96, Q96)
            );
        }
        if (amountIn > currentAmounts[tokenInIndex]) {
            amountIn = currentAmounts[tokenInIndex];
        }
    }

    function _pushIntoRamses(Storage memory s, uint256 ratioX96) private {
        (uint256[] memory tvl, ) = s.immutableParams.erc20Vault.tvl();
        uint256[] memory lowerAmountsQ96 = s.immutableParams.lowerVault.liquidityToTokenAmounts(uint128(ratioX96));
        uint256[] memory upperAmountsQ96 = s.immutableParams.upperVault.liquidityToTokenAmounts(
            uint128(Q96 - ratioX96)
        );

        uint256 amount0 = lowerAmountsQ96[0] + upperAmountsQ96[0];
        uint256 amount1 = lowerAmountsQ96[1] + upperAmountsQ96[1];

        uint256 coefficientX96;
        if (amount0 > amount1) {
            coefficientX96 = FullMath.mulDiv(Q96, tvl[0], amount0);
        } else {
            coefficientX96 = FullMath.mulDiv(Q96, tvl[1], amount1);
        }
        uint256[] memory tokenAmounts = new uint256[](2);
        for (uint256 i = 0; i < 2; i++) {
            tokenAmounts[i] = FullMath.mulDiv(coefficientX96, lowerAmountsQ96[i], Q96);
        }
        if (tokenAmounts[0] > 0 || tokenAmounts[1] > 0) {
            s.immutableParams.erc20Vault.pull(
                address(s.immutableParams.lowerVault),
                s.immutableParams.tokens,
                tokenAmounts,
                ""
            );
        }
        (tokenAmounts, ) = s.immutableParams.erc20Vault.tvl();
        if (tokenAmounts[0] > 0 || tokenAmounts[1] > 0) {
            s.immutableParams.erc20Vault.pull(
                address(s.immutableParams.upperVault),
                s.immutableParams.tokens,
                tokenAmounts,
                ""
            );
        }
    }

    function _mint(
        Storage memory s,
        int24 lowerTick,
        int24 upperTick
    ) private returns (uint256 nft) {
        (nft, , , ) = positionManager.mint(
            IRamsesV2NonfungiblePositionManager.MintParams({
                token0: s.immutableParams.tokens[0],
                token1: s.immutableParams.tokens[1],
                fee: s.immutableParams.fee,
                tickLower: lowerTick,
                tickUpper: upperTick,
                amount0Desired: s.mutableParams.amount0Desired,
                amount1Desired: s.mutableParams.amount1Desired,
                amount0Min: 0,
                amount1Min: 0,
                recipient: address(this),
                deadline: type(uint256).max
            })
        );
        emit PositionMinted(nft);
    }

    function _drainLiquidity(Storage memory s) private {
        // drain liquidity from vaults
        if (s.immutableParams.lowerVault.positionId() != 0) {
            s.immutableParams.lowerVault.pull(
                address(s.immutableParams.erc20Vault),
                s.immutableParams.lowerVault.vaultTokens(),
                s.immutableParams.lowerVault.liquidityToTokenAmounts(type(uint128).max),
                ""
            );
            s.immutableParams.upperVault.pull(
                address(s.immutableParams.erc20Vault),
                s.immutableParams.upperVault.vaultTokens(),
                s.immutableParams.upperVault.liquidityToTokenAmounts(type(uint128).max),
                ""
            );
        }
    }

    function _swapToTarget(
        Storage memory s,
        State memory state,
        bytes calldata swapData,
        uint256 minAmountOutInCaseOfSwap
    ) private {
        uint256 priceX96;
        uint256 tokenInIndex;
        uint256 amountIn;
        {
            (uint160 sqrtSpotPriceX96, , , , , , ) = s.immutableParams.pool.slot0();
            priceX96 = FullMath.mulDiv(sqrtSpotPriceX96, sqrtSpotPriceX96, Q96);
            (uint256[] memory currentAmounts, ) = s.immutableParams.erc20Vault.tvl();
            (tokenInIndex, amountIn) = calculateAmountsForSwap(
                currentAmounts,
                s.mutableParams.priceImpactD6,
                priceX96,
                calculateTargetRatioOfToken1(s, state.ratioX96)
            );
        }

        if (amountIn < s.mutableParams.minSwapAmounts[tokenInIndex]) {
            return;
        }

        if (tokenInIndex == 1) {
            priceX96 = FullMath.mulDiv(Q96, Q96, priceX96);
        }

        (uint256[] memory tvlBefore, ) = s.immutableParams.erc20Vault.tvl();

        s.immutableParams.erc20Vault.externalCall(s.immutableParams.router, bytes4(swapData[:4]), swapData[4:]);

        uint256 actualAmountIn;
        uint256 actualAmountOut;

        {
            (uint256[] memory tvlAfter, ) = s.immutableParams.erc20Vault.tvl();

            require(tvlAfter[tokenInIndex] <= tvlBefore[tokenInIndex], ExceptionsLibrary.INVARIANT);
            require(tvlAfter[tokenInIndex ^ 1] >= tvlBefore[tokenInIndex ^ 1], ExceptionsLibrary.INVARIANT);

            actualAmountIn = tvlBefore[tokenInIndex] - tvlAfter[tokenInIndex];
            actualAmountOut = tvlAfter[tokenInIndex ^ 1] - tvlBefore[tokenInIndex ^ 1];
        }

        uint256 actualSwapPriceX96 = FullMath.mulDiv(actualAmountOut, Q96, actualAmountIn);

        require(actualAmountOut >= minAmountOutInCaseOfSwap, ExceptionsLibrary.LIMIT_UNDERFLOW);

        require(
            FullMath.mulDiv(priceX96, D9 - s.mutableParams.swapSlippageD, D9) <= actualSwapPriceX96,
            ExceptionsLibrary.LIMIT_UNDERFLOW
        );

        require(
            FullMath.mulDiv(amountIn, D9 - s.mutableParams.swappingAmountsCoefficientD, D9) <= actualAmountIn,
            ExceptionsLibrary.LIMIT_UNDERFLOW
        );

        require(
            FullMath.mulDiv(actualAmountIn, D9 - s.mutableParams.swappingAmountsCoefficientD, D9) <= amountIn,
            ExceptionsLibrary.LIMIT_UNDERFLOW
        );

        emit TokensSwapped(actualAmountIn, actualAmountOut, tokenInIndex);
    }

    /// @inheritdoc ILpCallback
    function depositCallback() external {
        Storage memory s = _contractStorage();
        State memory current = getCurrentState(s);
        _pushIntoRamses(s, current.ratioX96);
    }

    /// @inheritdoc ILpCallback
    function withdrawCallback() external {}

    /// @notice Emitted after a successful token swap
    /// @param amountIn amount of token, that pushed into SwapRouter
    /// @param amountOut amount of token, that recieved from SwapRouter
    /// @param tokenInIndex index of token, that pushed into SwapRouter
    event TokensSwapped(uint256 amountIn, uint256 amountOut, uint256 tokenInIndex);

    /// @notice Emited when mutable parameters are successfully updated
    /// @param origin Origin of the transaction (tx.origin)
    /// @param sender Sender of the call (msg.sender)
    /// @param mutableParams Updated parameters
    event UpdateMutableParams(address indexed origin, address indexed sender, MutableParams mutableParams);

    /// @notice Emited when the rebalance is successfully completed
    /// @param origin Origin of the transaction (tx.origin)
    /// @param sender Sender of the call (msg.sender)
    event Rebalance(address indexed origin, address indexed sender);

    /// @notice Emited when a new ramses v2 position is created
    /// @param tokenId nft of new ramses v2 position
    event PositionMinted(uint256 tokenId);

    /// @notice Emited when a ramses v2 position is burned
    /// @param tokenId nft of ramses v2 position
    event PositionBurned(uint256 tokenId);
}
