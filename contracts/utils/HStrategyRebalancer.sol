// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";

import "../interfaces/external/univ3/ISwapRouter.sol";
import "../interfaces/external/univ3/INonfungiblePositionManager.sol";
import "../interfaces/vaults/IIntegrationVault.sol";
import "../interfaces/vaults/IUniV3Vault.sol";
import "../interfaces/vaults/IERC20Vault.sol";
import "../interfaces/vaults/IAaveVault.sol";
import "../libraries/CommonLibrary.sol";
import "../libraries/external/TickMath.sol";
import "../libraries/external/LiquidityAmounts.sol";
import "../utils/DefaultAccessControlLateInit.sol";
import "../libraries/external/PositionValue.sol";

contract HStrategyRebalancer is DefaultAccessControlLateInit {
    using SafeERC20 for IERC20;

    uint256 public constant DENOMINATOR = 1000_000_000;
    uint256 public constant Q96 = 2**96;
    bytes4 public constant APPROVE_SELECTOR = 0x095ea7b3;
    bytes4 public constant EXACT_INPUT_SINGLE_SELECTOR = ISwapRouter.exactInputSingle.selector;

    INonfungiblePositionManager public immutable positionManager;

    struct StrategyData {
        address[] tokens;
        address[] uniV3Vaults;
        address erc20Vault;
        address moneyVault;
        int24 halfOfShortInterval;
        int24 domainLowerTick;
        int24 domainUpperTick;
        int24 shortLowerTick;
        int24 shortUpperTick;
        address pool;
        uint256 amount0ForMint;
        uint256 amount1ForMint;
        address router;
        uint256 erc20CapitalD;
        uint256[] uniV3Weights;
    }

    function initialize(address strategyAddress) external {
        DefaultAccessControlLateInit.init(strategyAddress);
    }

    function createRebalancer(address strategyAddress) external returns (HStrategyRebalancer rebalancer) {
        rebalancer = HStrategyRebalancer(Clones.clone(address(this)));
        rebalancer.initialize(strategyAddress);
    }

    constructor(address strategyAddress, INonfungiblePositionManager positionManager_) {
        DefaultAccessControlLateInit.init(strategyAddress);
        positionManager = positionManager_;
    }

    function _getUniV3VaultTvl(address vaultAddress, uint160 sqrtPriceX96)
        private
        view
        returns (uint256 amount0, uint256 amount1)
    {
        IUniV3Vault vault = IUniV3Vault(vaultAddress);
        uint256 uniV3Nft = vault.uniV3Nft();
        if (uniV3Nft != 0) {
            (amount0, amount1) = PositionValue.total(positionManager, uniV3Nft, sqrtPriceX96, address(vault.pool()));
        }
    }

    function getTvls(
        StrategyData memory data,
        uint160 sqrtPriceX96,
        bool needUpdate
    )
        public
        returns (
            uint256[] memory total,
            uint256[] memory erc20,
            uint256[] memory money,
            uint256[] memory totalUniV3,
            uint256[2][] memory uniV3
        )
    {
        if (needUpdate) {
            for (uint256 i = 0; i < data.uniV3Vaults.length; ++i) {
                IUniV3Vault vault = IUniV3Vault(data.uniV3Vaults[i]);
                if (vault.uniV3Nft() != 0) {
                    vault.collectEarnings();
                }
            }

            if (IVault(data.moneyVault).supportsInterface(type(IAaveVault).interfaceId)) {
                IAaveVault(data.moneyVault).updateTvls();
            }
        }

        (erc20, ) = IVault(data.erc20Vault).tvl();
        (money, ) = IVault(data.moneyVault).tvl();

        total = new uint256[](2);
        totalUniV3 = new uint256[](2);
        total[0] = erc20[0] + money[0];
        total[1] = erc20[1] + money[1];

        uniV3 = new uint256[2][](data.uniV3Vaults.length);
        for (uint256 i = 0; i < data.uniV3Vaults.length; ++i) {
            (uniV3[i][0], uniV3[i][1]) = _getUniV3VaultTvl(data.uniV3Vaults[i], sqrtPriceX96);
            totalUniV3[0] += uniV3[i][0];
            totalUniV3[1] += uniV3[i][1];
        }

        total[0] += totalUniV3[0];
        total[1] += totalUniV3[1];
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

    function _expectedToken0Ratio(
        uint160 sqrtC,
        int24 lowerTick,
        int24 upperTick
    ) private pure returns (uint256 ratio0) {
        uint160 sqrtA = TickMath.getSqrtRatioAtTick(lowerTick);
        uint160 sqrtB = TickMath.getSqrtRatioAtTick(upperTick);
        ratio0 = FullMath.mulDiv(DENOMINATOR, sqrtB - sqrtC, 2 * sqrtB - sqrtC - FullMath.mulDiv(sqrtA, sqrtB, sqrtC));
    }

    function _positionsRebalance(StrategyData memory data, int24 tick)
        private
        returns (
            bool needToMintNewPositions,
            int24 newShortLowerTick,
            int24 newShortUpperTick
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

        if (data.shortLowerTick == newShortLowerTick && data.shortUpperTick == newShortUpperTick) {
            return (false, 0, 0);
        }

        _drainPositions(data);
        needToMintNewPositions = true;
    }

    function _pullIfNeeded(
        uint256[] memory expectedAmount,
        StrategyData memory data,
        address vault
    ) private returns (bool done) {
        (uint256[] memory tvl, ) = IVault(data.erc20Vault).tvl();
        uint256[] memory amountForPull = new uint256[](2);
        if (tvl[0] < expectedAmount[0]) {
            amountForPull[0] = expectedAmount[0] - tvl[0];
        }
        if (tvl[1] < expectedAmount[1]) {
            amountForPull[1] = expectedAmount[1] - tvl[1];
        }
        if (amountForPull[0] > 0 || amountForPull[1] > 0) {
            uint256[] memory pulledAmounts = IIntegrationVault(vault).pull(
                data.erc20Vault,
                data.tokens,
                amountForPull,
                ""
            );
            if (pulledAmounts[0] >= amountForPull[0] && pulledAmounts[1] >= amountForPull[1]) {
                done = true;
            }
        } else {
            done = true;
        }
    }

    function _swapRebalance(
        StrategyData memory data,
        uint160 sqrtPriceX96,
        uint256[] memory totalTvl
    ) private {
        uint256 currentToken0 = totalTvl[0];
        uint256 currentToken1 = totalTvl[1];
        uint256 priceX96 = FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, Q96);

        uint256 ratio0 = _expectedToken0Ratio(sqrtPriceX96, data.domainLowerTick, data.domainUpperTick);
        uint256 capital0 = currentToken0 + FullMath.mulDiv(currentToken1, Q96, priceX96);
        uint256 expectedAmount0 = FullMath.mulDiv(capital0, ratio0, DENOMINATOR);

        uint256[] memory amountsForSwap = new uint256[](2);
        if (expectedAmount0 > currentToken0) {
            amountsForSwap[1] = FullMath.mulDiv(expectedAmount0 - currentToken0, priceX96, Q96);
        } else {
            amountsForSwap[0] = currentToken0 - expectedAmount0;
        }

        if (amountsForSwap[0] > 0 || amountsForSwap[1] > 0) {
            if (!_pullIfNeeded(amountsForSwap, data, data.moneyVault)) {
                for (uint256 i = 0; i < data.uniV3Vaults.length; ++i) {
                    if (_pullIfNeeded(amountsForSwap, data, data.uniV3Vaults[i])) {
                        break;
                    }
                }
            }
            _swapOneToAnother(data, amountsForSwap);
        }
    }

    function _swapOneToAnother(StrategyData memory data, uint256[] memory amountsForSwap) private {
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
            return;
        }

        IERC20Vault erc20Vault = IERC20Vault(data.erc20Vault);
        bytes memory routerResult;
        ISwapRouter.ExactInputSingleParams memory swapParams = ISwapRouter.ExactInputSingleParams({
            tokenIn: data.tokens[tokenInIndex],
            tokenOut: data.tokens[tokenInIndex ^ 1],
            fee: IUniswapV3Pool(data.pool).fee(),
            recipient: data.erc20Vault,
            deadline: type(uint256).max,
            amountIn: amountIn,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });

        bytes memory routerData = abi.encode(swapParams);
        erc20Vault.externalCall(data.tokens[tokenInIndex], APPROVE_SELECTOR, abi.encode(data.router, amountIn));
        routerResult = erc20Vault.externalCall(data.router, EXACT_INPUT_SINGLE_SELECTOR, routerData);
        erc20Vault.externalCall(data.tokens[tokenInIndex], APPROVE_SELECTOR, abi.encode(data.router, 0));
    }

    function _capitalRebalance(StrategyData memory data, uint160 sqrtPriceX96) private {
        // expected ratio on uniV3Vaults according to weights
        (uint256[] memory totalTvl, , uint256[] memory moneyTvl, , uint256[2][] memory uniV3Tvl) = getTvls(
            data,
            sqrtPriceX96,
            true
        );

        uint256 uniV3RatioD = FullMath.mulDiv(
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

        uint256[] memory moneyExpected = new uint256[](2);
        uint256[2][] memory uniV3Expected;
        {
            uint256[] memory totalUniV3Expected = new uint256[](2);
            {
                uint256 priceX96 = FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, Q96);
                uint256 uniCapital = FullMath.mulDiv(
                    totalTvl[0] + FullMath.mulDiv(totalTvl[1], Q96, priceX96),
                    uniV3RatioD,
                    DENOMINATOR
                );
                uint256 ratio0 = _expectedToken0Ratio(sqrtPriceX96, data.shortLowerTick, data.shortUpperTick);
                totalUniV3Expected[0] = FullMath.mulDiv(uniCapital, ratio0, DENOMINATOR);
                totalUniV3Expected[1] = FullMath.mulDiv(uniCapital - totalUniV3Expected[0], priceX96, Q96);
            }

            moneyExpected[0] = FullMath.mulDiv(
                totalTvl[0] - totalUniV3Expected[0],
                DENOMINATOR - data.erc20CapitalD,
                DENOMINATOR
            );
            moneyExpected[1] = FullMath.mulDiv(
                totalTvl[1] - totalUniV3Expected[1],
                DENOMINATOR - data.erc20CapitalD,
                DENOMINATOR
            );

            uniV3Expected = _calculateVaultsExpectedAmounts(totalUniV3Expected, data);
        }
        _pull(
            data.moneyVault,
            data.erc20Vault,
            moneyTvl[0],
            moneyTvl[1],
            moneyExpected[0],
            moneyExpected[1],
            data.tokens
        );
        for (uint256 i = 0; i < data.uniV3Vaults.length; i++) {
            _pull(
                data.uniV3Vaults[i],
                data.erc20Vault,
                uniV3Tvl[i][0],
                uniV3Tvl[i][1],
                uniV3Expected[i][0],
                uniV3Expected[i][1],
                data.tokens
            );
        }

        _pull(
            data.erc20Vault,
            data.moneyVault,
            moneyExpected[0],
            moneyExpected[1],
            moneyTvl[0],
            moneyTvl[1],
            data.tokens
        );
        for (uint256 i = 0; i < data.uniV3Vaults.length; i++) {
            _pull(
                data.erc20Vault,
                data.uniV3Vaults[i],
                uniV3Expected[i][0],
                uniV3Expected[i][1],
                uniV3Tvl[i][0],
                uniV3Tvl[i][1],
                data.tokens
            );
        }
    }

    function _pull(
        address from,
        address to,
        uint256 amount0,
        uint256 amount1,
        uint256 expectedAmount0,
        uint256 expectedAmount1,
        address[] memory tokens
    ) private {
        uint256[] memory amountsForPull = new uint256[](2);
        if (amount0 > expectedAmount0) {
            amountsForPull[0] = amount0 - expectedAmount0;
        }

        if (amount1 > expectedAmount1) {
            amountsForPull[1] = amount1 - expectedAmount1;
        }

        if (amountsForPull[0] > 0 || amountsForPull[1] > 0) {
            IIntegrationVault(from).pull(to, tokens, amountsForPull, "");
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

    function processRebalance(StrategyData memory data)
        external
        returns (
            bool newPositionMinted,
            int24 newLowerTick,
            int24 newUpperTick
        )
    {
        _requireAdmin();

        IUniswapV3Pool pool = IUniswapV3Pool(data.pool);
        (uint160 sqrtPriceX96, int24 spotTick, , , , , ) = pool.slot0();
        {
            (newPositionMinted, newLowerTick, newUpperTick) = _positionsRebalance(data, spotTick);
            (uint256[] memory total, , , , ) = getTvls(data, sqrtPriceX96, true);

            _swapRebalance(data, sqrtPriceX96, total);

            if (newPositionMinted) {
                _mintPositions(data, newLowerTick, newUpperTick);
                data.shortLowerTick = newLowerTick;
                data.shortUpperTick = newUpperTick;
            }
        }

        _capitalRebalance(data, sqrtPriceX96);
    }
}
