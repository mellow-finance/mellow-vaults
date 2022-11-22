// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";

import "./DefaultAccessControlLateInit.sol";

import "../interfaces/external/univ3/ISwapRouter.sol";

import "../interfaces/vaults/IAaveVault.sol";
import "../interfaces/vaults/IERC20Vault.sol";
import "../interfaces/vaults/IUniV3Vault.sol";

import "../libraries/external/FullMath.sol";
import "../libraries/external/TickMath.sol";

contract MultiPoolHStrategyRebalancer is DefaultAccessControlLateInit {
    using SafeERC20 for IERC20;

    uint256 public constant DENOMINATOR = 1000_000_000;
    uint256 public constant Q96 = 2**96;
    bytes4 public constant APPROVE_SELECTOR = 0x095ea7b3;
    bytes4 public constant EXACT_INPUT_SINGLE_SELECTOR = ISwapRouter.exactInputSingle.selector;

    INonfungiblePositionManager public immutable positionManager;

    struct StrategyData {
        int24 halfOfShortInterval;
        int24 domainLowerTick;
        int24 domainUpperTick;
        int24 shortLowerTick;
        int24 shortUpperTick;
        IERC20Vault erc20Vault;
        IIntegrationVault moneyVault;
        address router;
        IUniswapV3Pool pool;
        uint256 amount0ForMint;
        uint256 amount1ForMint;
        uint256 erc20CapitalD;
        uint256[] uniV3Weights;
        address[] tokens;
        IUniV3Vault[] uniV3Vaults;
    }

    struct Tvls {
        uint256[] money;
        uint256[2][] uniV3;
        uint256[] erc20;
        uint256[] total;
        uint256[] totalUniV3;
    }

    struct Restrictions {
        int24 newShortLowerTick;
        int24 newShortUpperTick;
        int256[] swappedAmounts;
        uint256[2][] drainedAmounts;
        uint256[2][] pulledToUniV3;
        uint256[2][] pulledFromUniV3;
        uint256 deadline;
    }

    constructor(INonfungiblePositionManager positionManager_, address admin) {
        require(address(positionManager_) != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        positionManager = positionManager_;
        DefaultAccessControlLateInit.init(admin);
    }

    function initialize(address admin) external {
        DefaultAccessControlLateInit.init(admin);
    }

    function createRebalancer(address admin) external returns (MultiPoolHStrategyRebalancer rebalancer) {
        rebalancer = MultiPoolHStrategyRebalancer(Clones.clone(address(this)));
        rebalancer.initialize(admin);
    }

    function getTvls(StrategyData memory data) public returns (Tvls memory tvls) {
        bool hasUniV3Nft = data.uniV3Vaults[0].uniV3Nft() != 0;
        {
            for (uint256 i = 0; i < data.uniV3Vaults.length; ++i) {
                if (hasUniV3Nft) {
                    data.uniV3Vaults[i].collectEarnings();
                }
            }

            if (IVault(data.moneyVault).supportsInterface(type(IAaveVault).interfaceId)) {
                IAaveVault(address(data.moneyVault)).updateTvls();
            }
        }

        (tvls.erc20, ) = IVault(data.erc20Vault).tvl();
        (tvls.money, ) = IVault(data.moneyVault).tvl();

        tvls.total = new uint256[](2);
        tvls.totalUniV3 = new uint256[](2);
        tvls.total[0] = tvls.erc20[0] + tvls.money[0];
        tvls.total[1] = tvls.erc20[1] + tvls.money[1];

        tvls.uniV3 = new uint256[2][](data.uniV3Vaults.length);
        for (uint256 i = 0; i < data.uniV3Vaults.length; ++i) {
            if (hasUniV3Nft) {
                uint256 uniV3Nft = data.uniV3Vaults[i].uniV3Nft();
                (, , , , , , , uint128 liquidity, , , , ) = positionManager.positions(uniV3Nft);
                tvls.uniV3[i] = _convertToStaticArray(data.uniV3Vaults[i].liquidityToTokenAmounts(liquidity));
                tvls.totalUniV3[0] += tvls.uniV3[i][0];
                tvls.totalUniV3[1] += tvls.uniV3[i][1];
            }
        }

        tvls.total[0] += tvls.totalUniV3[0];
        tvls.total[1] += tvls.totalUniV3[1];
    }

    function _drainPositions(StrategyData memory data) private returns (uint256[2][] memory drainedAmounts) {
        drainedAmounts = new uint256[2][](data.uniV3Vaults.length);
        for (uint256 i = 0; i < data.uniV3Vaults.length; ++i) {
            IUniV3Vault vault = IUniV3Vault(data.uniV3Vaults[i]);
            uint256 uniV3Nft = vault.uniV3Nft();

            if (uniV3Nft != 0) {
                uint256[] memory tokenAmounts = vault.pull(
                    address(data.erc20Vault),
                    data.tokens,
                    vault.liquidityToTokenAmounts(type(uint128).max),
                    ""
                );
                drainedAmounts[i][0] = tokenAmounts[0];
                drainedAmounts[i][1] = tokenAmounts[1];
            }
        }
    }

    function _mintPositions(
        StrategyData memory data,
        int24 newLowerTick,
        int24 newUpperTick
    ) private {
        IERC20(data.tokens[0]).safeApprove(address(positionManager), data.amount0ForMint * data.uniV3Vaults.length);
        IERC20(data.tokens[1]).safeApprove(address(positionManager), data.amount1ForMint * data.uniV3Vaults.length);

        for (uint256 i = 0; i < data.uniV3Vaults.length; ++i) {
            IUniV3Vault vault = IUniV3Vault(data.uniV3Vaults[i]);
            (uint256 newNft, , , ) = positionManager.mint(
                INonfungiblePositionManager.MintParams({
                    token0: data.tokens[0],
                    token1: data.tokens[1],
                    fee: vault.pool().fee(),
                    tickLower: newLowerTick,
                    tickUpper: newUpperTick,
                    amount0Desired: data.amount0ForMint,
                    amount1Desired: data.amount1ForMint,
                    amount0Min: 0,
                    amount1Min: 0,
                    recipient: address(this),
                    deadline: type(uint256).max
                })
            );

            uint256 oldNft = vault.uniV3Nft();
            positionManager.safeTransferFrom(address(this), address(vault), newNft);
            if (oldNft != 0) {
                positionManager.burn(oldNft);
            }
        }

        IERC20(data.tokens[0]).safeApprove(address(positionManager), 0);
        IERC20(data.tokens[1]).safeApprove(address(positionManager), 0);
    }

    function _calculateRatioOfToken0D(
        uint160 sqrtSpotPriceX96,
        int24 lowerTick,
        int24 upperTick
    ) private pure returns (uint256 ratioOfToken0D) {
        uint160 sqrtLowerPriceX96 = TickMath.getSqrtRatioAtTick(lowerTick);
        uint160 sqrtUpperPriceX96 = TickMath.getSqrtRatioAtTick(upperTick);
        ratioOfToken0D = FullMath.mulDiv(
            DENOMINATOR,
            sqrtUpperPriceX96 - sqrtSpotPriceX96,
            2 *
                sqrtUpperPriceX96 -
                sqrtSpotPriceX96 -
                FullMath.mulDiv(sqrtLowerPriceX96, sqrtUpperPriceX96, sqrtSpotPriceX96)
        );
    }

    function _positionsRebalance(
        StrategyData memory data,
        int24 tick,
        bool forcePositionRebalance,
        Restrictions memory restrictions
    )
        private
        returns (
            bool needToMintNewPositions,
            int24 newShortLowerTick,
            int24 newShortUpperTick,
            uint256[2][] memory drainedAmounts
        )
    {
        int24 lowerTick = tick - (tick % data.halfOfShortInterval);
        int24 upperTick = lowerTick + data.halfOfShortInterval;

        if (tick - lowerTick <= upperTick - tick) {
            newShortLowerTick = lowerTick - data.halfOfShortInterval;
            newShortUpperTick = lowerTick + data.halfOfShortInterval;
        } else {
            newShortLowerTick = upperTick - data.halfOfShortInterval;
            newShortUpperTick = upperTick + data.halfOfShortInterval;
        }

        if (newShortLowerTick < data.domainLowerTick) {
            newShortLowerTick = data.domainLowerTick;
            newShortUpperTick = newShortLowerTick + data.halfOfShortInterval * 2;
        } else if (newShortUpperTick > data.domainUpperTick) {
            newShortUpperTick = data.domainUpperTick;
            newShortLowerTick = newShortUpperTick - data.halfOfShortInterval * 2;
        }

        require(
            restrictions.newShortLowerTick == newShortLowerTick && restrictions.newShortUpperTick == newShortUpperTick,
            ExceptionsLibrary.INVARIANT
        );

        if (
            !forcePositionRebalance &&
            data.shortLowerTick == newShortLowerTick &&
            data.shortUpperTick == newShortUpperTick
        ) {
            return (false, 0, 0, new uint256[2][](restrictions.drainedAmounts.length));
        }

        drainedAmounts = _drainPositions(data);
        for (uint256 i = 0; i < drainedAmounts.length; ++i) {
            _compareAmounts(
                _convertToDynamicArray(drainedAmounts[i]),
                _convertToDynamicArray(restrictions.drainedAmounts[i])
            );
        }
        needToMintNewPositions = true;
    }

    function _swapRebalance(
        StrategyData memory data,
        uint160 sqrtPriceX96,
        Restrictions memory restrictions,
        uint256 currentAmount0,
        uint256 expectedAmount0
    ) private returns (int256[] memory swappedAmounts) {
        uint256 priceX96 = FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, Q96);
        uint256[] memory amountsForSwap = new uint256[](2);
        if (expectedAmount0 > currentAmount0) {
            amountsForSwap[1] = FullMath.mulDiv(expectedAmount0 - currentAmount0, priceX96, Q96);
        } else {
            amountsForSwap[0] = currentAmount0 - expectedAmount0;
        }

        if (amountsForSwap[0] > 0 || amountsForSwap[1] > 0) {
            swappedAmounts = _swapOneToAnother(data, amountsForSwap, restrictions);
        } else {
            swappedAmounts = new int256[](2);
        }
    }

    function _swapOneToAnother(
        StrategyData memory data,
        uint256[] memory amountsForSwap,
        Restrictions memory restrictions
    ) private returns (int256[] memory swappedAmounts) {
        uint256 tokenInIndex;
        uint256 amountIn;
        if (amountsForSwap[0] > 0) {
            amountIn = amountsForSwap[0];
            tokenInIndex = 0;
        } else {
            amountIn = amountsForSwap[1];
            tokenInIndex = 1;
        }

        if (amountIn == 0) {
            require(restrictions.swappedAmounts[tokenInIndex ^ 1] == 0, ExceptionsLibrary.LIMIT_OVERFLOW);
            require(restrictions.swappedAmounts[tokenInIndex] == 0, ExceptionsLibrary.LIMIT_UNDERFLOW);
            return new int256[](2);
        }

        IERC20Vault erc20Vault = IERC20Vault(data.erc20Vault);
        bytes memory routerResult;
        ISwapRouter.ExactInputSingleParams memory swapParams = ISwapRouter.ExactInputSingleParams({
            tokenIn: data.tokens[tokenInIndex],
            tokenOut: data.tokens[tokenInIndex ^ 1],
            fee: IUniswapV3Pool(data.pool).fee(),
            recipient: address(data.erc20Vault),
            deadline: restrictions.deadline,
            amountIn: amountIn,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });

        bytes memory routerData = abi.encode(swapParams);
        erc20Vault.externalCall(data.tokens[tokenInIndex], APPROVE_SELECTOR, abi.encode(data.router, amountIn));
        routerResult = erc20Vault.externalCall(data.router, EXACT_INPUT_SINGLE_SELECTOR, routerData);
        erc20Vault.externalCall(data.tokens[tokenInIndex], APPROVE_SELECTOR, abi.encode(data.router, 0));
        uint256 amountOut = abi.decode(routerResult, (uint256));

        require(
            restrictions.swappedAmounts[tokenInIndex ^ 1] >= 0 && restrictions.swappedAmounts[tokenInIndex] <= 0,
            ExceptionsLibrary.INVARIANT
        );
        require(restrictions.swappedAmounts[tokenInIndex ^ 1] <= int256(amountOut), ExceptionsLibrary.LIMIT_UNDERFLOW);
        require(restrictions.swappedAmounts[tokenInIndex] >= -int256(amountIn), ExceptionsLibrary.LIMIT_OVERFLOW);

        swappedAmounts = new int256[](2);
        swappedAmounts[tokenInIndex ^ 1] = int256(amountOut);
        swappedAmounts[tokenInIndex] = -int256(amountIn);
    }

    function _calculateUniV3RatioD(StrategyData memory data, uint160 sqrtPriceX96)
        private
        pure
        returns (uint256 uniV3RatioD)
    {
        uniV3RatioD = FullMath.mulDiv(
            DENOMINATOR,
            2 *
                Q96 -
                FullMath.mulDiv(TickMath.getSqrtRatioAtTick(data.shortLowerTick), Q96, sqrtPriceX96) -
                FullMath.mulDiv(sqrtPriceX96, Q96, TickMath.getSqrtRatioAtTick(data.shortUpperTick)),
            2 *
                Q96 -
                FullMath.mulDiv(TickMath.getSqrtRatioAtTick(data.domainLowerTick), Q96, sqrtPriceX96) -
                FullMath.mulDiv(sqrtPriceX96, Q96, TickMath.getSqrtRatioAtTick(data.domainUpperTick))
        );
    }

    function calculateExpectedAmounts(
        StrategyData memory data,
        uint160 sqrtPriceX96,
        uint256 totalToken0,
        uint256 totalToken1
    )
        public
        pure
        returns (
            uint256[] memory moneyExpected,
            uint256[2][] memory uniV3Expected,
            uint256 expectedAmount0
        )
    {
        moneyExpected = new uint256[](2);

        uint256 priceX96 = FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, Q96);
        uint256 totalCapitalInToken0 = totalToken0 + FullMath.mulDiv(totalToken1, Q96, priceX96);

        {
            uint256[] memory totalUniV3Expected = new uint256[](2);
            {
                uint256 uniV3RatioD = _calculateUniV3RatioD(data, sqrtPriceX96);
                uint256 uniCapitalInToken0 = FullMath.mulDiv(totalCapitalInToken0, uniV3RatioD, DENOMINATOR);

                uint256 ratioOfToken0D = _calculateRatioOfToken0D(
                    sqrtPriceX96,
                    data.shortLowerTick,
                    data.shortUpperTick
                );
                totalUniV3Expected[0] = FullMath.mulDiv(uniCapitalInToken0, ratioOfToken0D, DENOMINATOR);
                totalUniV3Expected[1] = FullMath.mulDiv(uniCapitalInToken0 - totalUniV3Expected[0], priceX96, Q96);
            }

            expectedAmount0 = FullMath.mulDiv(
                totalCapitalInToken0,
                _calculateRatioOfToken0D(sqrtPriceX96, data.domainLowerTick, data.domainUpperTick),
                DENOMINATOR
            );

            moneyExpected[0] = FullMath.mulDiv(
                expectedAmount0 - totalUniV3Expected[0],
                DENOMINATOR - data.erc20CapitalD,
                DENOMINATOR
            );

            uint256 expectedAmount1 = FullMath.mulDiv(totalCapitalInToken0 - expectedAmount0, priceX96, Q96);
            moneyExpected[1] = FullMath.mulDiv(
                expectedAmount1 - totalUniV3Expected[1],
                DENOMINATOR - data.erc20CapitalD,
                DENOMINATOR
            );

            uniV3Expected = _calculateVaultsExpectedAmounts(totalUniV3Expected, data);
        }
    }

    function _calculateVaultsExpectedAmounts(uint256[] memory totalUniV3Expected, StrategyData memory data)
        private
        pure
        returns (uint256[2][] memory expectedTokenAmounts)
    {
        uint256 totalWeight = 0;
        uint256 maxWeight = 0;
        uint256 indexOfVaultWithMaxWeight = 0;
        for (uint256 i = 0; i < data.uniV3Weights.length; ++i) {
            uint256 weight = data.uniV3Weights[i];
            totalWeight += weight;
            if (weight > maxWeight) {
                indexOfVaultWithMaxWeight = i;
                maxWeight = weight;
            }
        }

        expectedTokenAmounts = new uint256[2][](data.uniV3Weights.length);
        expectedTokenAmounts[indexOfVaultWithMaxWeight][0] = totalUniV3Expected[0];
        expectedTokenAmounts[indexOfVaultWithMaxWeight][1] = totalUniV3Expected[1];
        for (uint256 i = 0; i < data.uniV3Weights.length; ++i) {
            uint256 weight = data.uniV3Weights[i];
            if (weight == 0 || i == indexOfVaultWithMaxWeight) continue;
            expectedTokenAmounts[i][0] = FullMath.mulDiv(totalUniV3Expected[0], weight, totalWeight);
            expectedTokenAmounts[i][1] = FullMath.mulDiv(totalUniV3Expected[1], weight, totalWeight);
            expectedTokenAmounts[indexOfVaultWithMaxWeight][0] -= expectedTokenAmounts[i][0];
            expectedTokenAmounts[indexOfVaultWithMaxWeight][1] -= expectedTokenAmounts[i][1];
        }
    }

    function _pullExtraTokens(
        StrategyData memory data,
        uint256[2][] memory uniV3Expected,
        uint256[] memory moneyExpected,
        Restrictions memory restrictions,
        Tvls memory tvls
    ) private returns (uint256[2][] memory pulledFromUniV3) {
        pulledFromUniV3 = new uint256[2][](data.uniV3Vaults.length);
        for (uint256 i = 0; i < pulledFromUniV3.length; ++i) {
            pulledFromUniV3[i] = _convertToStaticArray(
                _pullTokens(
                    data.tokens,
                    data.uniV3Vaults[i],
                    data.erc20Vault,
                    _convertToDynamicArray(uniV3Expected[i]),
                    _convertToDynamicArray(tvls.uniV3[i]),
                    _convertToDynamicArray(restrictions.pulledFromUniV3[i]),
                    true
                )
            );
        }

        _pullTokens(data.tokens, data.moneyVault, data.erc20Vault, moneyExpected, tvls.money, new uint256[](2), true);
    }

    function _pullMissingTokens(
        StrategyData memory data,
        uint256[2][] memory uniV3Expected,
        uint256[] memory moneyExpected,
        Restrictions memory restrictions,
        Tvls memory tvls
    ) private returns (uint256[2][] memory pulledToUniV3) {
        pulledToUniV3 = new uint256[2][](data.uniV3Vaults.length);
        for (uint256 i = 0; i < pulledToUniV3.length; ++i) {
            pulledToUniV3[i] = _convertToStaticArray(
                _pullTokens(
                    data.tokens,
                    data.uniV3Vaults[i],
                    data.erc20Vault,
                    _convertToDynamicArray(uniV3Expected[i]),
                    _convertToDynamicArray(tvls.uniV3[i]),
                    _convertToDynamicArray(restrictions.pulledToUniV3[i]),
                    false
                )
            );
        }

        _pullTokens(data.tokens, data.moneyVault, data.erc20Vault, moneyExpected, tvls.money, new uint256[](2), false);
    }

    function _pullTokens(
        address[] memory tokens,
        IIntegrationVault vault,
        IERC20Vault erc20Vault,
        uint256[] memory expected,
        uint256[] memory tvl,
        uint256[] memory restrictions,
        bool isExtra
    ) private returns (uint256[] memory pulledAmounts) {
        if (isExtra) {
            uint256[] memory amountsToPull = new uint256[](2);
            if (tvl[0] > expected[0]) {
                amountsToPull[0] = tvl[0] - expected[0];
            }
            if (tvl[1] > expected[1]) {
                amountsToPull[1] = tvl[1] - expected[1];
            }
            if (amountsToPull[0] > 0 || amountsToPull[1] > 0) {
                pulledAmounts = vault.pull(address(erc20Vault), tokens, amountsToPull, "");
                _compareAmounts(pulledAmounts, restrictions);
            }
        } else {
            uint256[] memory amountsToPull = new uint256[](2);
            if (tvl[0] < expected[0]) {
                amountsToPull[0] = expected[0] - tvl[0];
            }
            if (tvl[1] < expected[1]) {
                amountsToPull[1] = expected[1] - tvl[1];
            }
            if (amountsToPull[0] > 0 || amountsToPull[1] > 0) {
                pulledAmounts = erc20Vault.pull(address(vault), tokens, amountsToPull, "");
                _compareAmounts(pulledAmounts, restrictions);
            }
        }
        if (pulledAmounts.length == 0) {
            pulledAmounts = new uint256[](2);
        }
    }

    function processRebalance(
        StrategyData memory data,
        bool forcePositionRebalance,
        Restrictions memory restrictions
    ) external returns (Restrictions memory actualAmounts) {
        _requireAdmin();

        (uint160 sqrtPriceX96, int24 spotTick, , , , , ) = data.pool.slot0();
        bool newPositionMinted = false;
        int24 newLowerTick;
        int24 newUpperTick;
        {
            (newPositionMinted, newLowerTick, newUpperTick, actualAmounts.drainedAmounts) = _positionsRebalance(
                data,
                spotTick,
                forcePositionRebalance,
                restrictions
            );
            if (newPositionMinted) {
                data.shortLowerTick = newLowerTick;
                data.shortUpperTick = newUpperTick;
                actualAmounts.newShortLowerTick = newLowerTick;
                actualAmounts.newShortUpperTick = newUpperTick;
            }
        }

        Tvls memory tvls = getTvls(data);
        (
            uint256[] memory moneyExpected,
            uint256[2][] memory uniV3Expected,
            uint256 expectedAmount0
        ) = calculateExpectedAmounts(data, sqrtPriceX96, tvls.total[0], tvls.total[1]);

        actualAmounts.pulledFromUniV3 = _pullExtraTokens(data, uniV3Expected, moneyExpected, restrictions, tvls);
        actualAmounts.swappedAmounts = _swapRebalance(data, sqrtPriceX96, restrictions, tvls.total[0], expectedAmount0);
        if (newPositionMinted) {
            _mintPositions(data, newLowerTick, newUpperTick);
        }
        actualAmounts.pulledToUniV3 = _pullMissingTokens(data, uniV3Expected, moneyExpected, restrictions, tvls);
    }

    function _compareAmounts(uint256[] memory actual, uint256[] memory expected) private pure {
        require(actual.length == expected.length, ExceptionsLibrary.INVALID_LENGTH);
        for (uint256 i = 0; i < actual.length; i++) {
            require(actual[i] >= expected[i], ExceptionsLibrary.LIMIT_UNDERFLOW);
        }
    }

    function _convertToDynamicArray(uint256[2] memory array) private pure returns (uint256[] memory result) {
        result = new uint256[](2);
        result[0] = array[0];
        result[1] = array[1];
    }

    function _convertToStaticArray(uint256[] memory array) private pure returns (uint256[2] memory result) {
        require(array.length == result.length, ExceptionsLibrary.INVALID_LENGTH);
        result = [array[0], array[1]];
    }
}
