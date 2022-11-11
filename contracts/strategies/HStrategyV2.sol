// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";

import "../interfaces/external/univ3/ISwapRouter.sol";
import "../interfaces/vaults/IERC20Vault.sol";
import "../interfaces/vaults/IAaveVault.sol";
import "../interfaces/vaults/IUniV3Vault.sol";

import "../libraries/ExceptionsLibrary.sol";
import "../libraries/external/FullMath.sol";
import "../libraries/external/PositionValue.sol";

import "../utils/ContractMeta.sol";
import "../utils/DefaultAccessControlLateInit.sol";

contract HStrategyV2 is ContractMeta, DefaultAccessControlLateInit {
    using SafeERC20 for IERC20;

    uint256 public constant DENOMINATOR = 1000_000_000;
    uint256 public constant Q96 = 2**96;
    bytes4 public constant APPROVE_SELECTOR = 0x095ea7b3;
    bytes4 public constant EXACT_INPUT_SINGLE_SELECTOR = ISwapRouter.exactInputSingle.selector;

    int24 public halfOfShortInterval;
    int24 public domainLowerTick;
    int24 public domainUpperTick;
    int24 public shortLowerTick;
    int24 public shortUpperTick;

    uint24 public swapFees;
    uint256 public erc20CapitalD;

    uint256 public uniV3Nft;

    IERC20Vault public erc20Vault;
    IIntegrationVault public moneyVault;
    IUniV3Vault public uniV3Vault;

    ISwapRouter public immutable router;
    INonfungiblePositionManager public immutable positionManager;
    IUniswapV3Pool public pool;

    constructor(INonfungiblePositionManager positionManager_, ISwapRouter router_) {
        require(address(positionManager_) != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        require(address(router_) != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        positionManager = positionManager_;
        router = router_;
        DefaultAccessControlLateInit.init(address(this));
    }

    function initialize(
        address[] memory tokens_,
        IERC20Vault erc20Vault_,
        IIntegrationVault moneyVault_,
        IUniV3Vault uniV3Vault_,
        address admin_
    ) external {
        DefaultAccessControlLateInit.init(admin_); // call once is checked here
        address[] memory erc20Tokens = erc20Vault_.vaultTokens();
        address[] memory moneyTokens = moneyVault_.vaultTokens();
        address[] memory uniV3Tokens = uniV3Vault_.vaultTokens();
        require(tokens_.length == 2, ExceptionsLibrary.INVALID_LENGTH);
        require(erc20Tokens.length == 2, ExceptionsLibrary.INVALID_LENGTH);
        require(moneyTokens.length == 2, ExceptionsLibrary.INVALID_LENGTH);
        require(uniV3Tokens.length == 2, ExceptionsLibrary.INVALID_LENGTH);
        for (uint256 i = 0; i < 2; ++i) {
            require(erc20Tokens[i] == tokens_[i], ExceptionsLibrary.INVARIANT);
            require(moneyTokens[i] == tokens_[i], ExceptionsLibrary.INVARIANT);
            require(uniV3Tokens[i] == tokens_[i], ExceptionsLibrary.INVARIANT);
        }
        erc20Vault = erc20Vault_;
        moneyVault = moneyVault_;
        uniV3Vault = uniV3Vault_;
        pool = uniV3Vault.pool();
        require(address(pool) != address(0), ExceptionsLibrary.ADDRESS_ZERO);
    }

    function createStrategy(
        address[] memory tokens_,
        IERC20Vault erc20Vault_,
        IIntegrationVault moneyVault_,
        IUniV3Vault uniV3Vault_,
        address admin_
    ) external returns (HStrategyV2 strategy) {
        strategy = HStrategyV2(Clones.clone(address(this)));
        strategy.initialize(tokens_, erc20Vault_, moneyVault_, uniV3Vault_, admin_);
    }

    function updateStrategyParams(
        int24 newHalfOfShortInterval,
        int24 newDomainLowerTick,
        int24 newDomainUpperTick,
        uint24 newSwapFees,
        uint256 newErc20CapitalD
    ) external {
        _requireAdmin();
        halfOfShortInterval = newHalfOfShortInterval;
        domainLowerTick = newDomainLowerTick;
        domainUpperTick = newDomainUpperTick;
        swapFees = newSwapFees;
        erc20CapitalD = newErc20CapitalD;
    }

    function caclulateCurrentTvl(uint160 sqrtPriceX96)
        public
        returns (
            uint256[] memory erc20Tvl,
            uint256[] memory uniV3Tvl,
            uint256[] memory moneyTvl,
            uint256[] memory totalTvl
        )
    {
        uniV3Tvl = new uint256[](2);
        if (uniV3Nft != 0) {
            uniV3Vault.collectEarnings();
            (uniV3Tvl[0], uniV3Tvl[1]) = PositionValue.total(positionManager, uniV3Nft, sqrtPriceX96, address(pool));
        }

        (erc20Tvl, ) = erc20Vault.tvl();
        if (moneyVault.supportsInterface(type(IAaveVault).interfaceId)) {
            IAaveVault(address(moneyVault)).updateTvls();
        }
        (moneyTvl, ) = moneyVault.tvl();
        totalTvl = new uint256[](2);
        totalTvl[0] = erc20Tvl[0] + uniV3Tvl[0] + moneyTvl[0];
        totalTvl[1] = erc20Tvl[1] + uniV3Tvl[1] + moneyTvl[1];
    }

    function rebalance() external {
        _requireAtLeastOperator();
        _positionRebalance();
        _swapRebalance();
        _liquidityRebalance();
    }

    function _positionRebalance() internal {
        (, int24 spotTick, , , , , ) = pool.slot0();
        int24 lowerTick = spotTick - (spotTick % halfOfShortInterval);
        int24 upperTick = lowerTick + halfOfShortInterval;
        int24 newShortLowerTick = 0;
        int24 newShortUpperTick = 0;

        if (spotTick - lowerTick <= upperTick - spotTick) {
            newShortLowerTick = lowerTick - halfOfShortInterval;
            newShortUpperTick = lowerTick + halfOfShortInterval;
        } else {
            newShortLowerTick = upperTick - halfOfShortInterval;
            newShortUpperTick = upperTick + halfOfShortInterval;
        }

        if (shortLowerTick < domainLowerTick) {
            shortLowerTick = domainLowerTick;
            shortUpperTick = shortLowerTick + halfOfShortInterval * 2;
        } else if (shortUpperTick > domainUpperTick) {
            shortUpperTick = domainUpperTick;
            shortLowerTick = shortUpperTick - halfOfShortInterval * 2;
        }

        if (shortLowerTick == newShortLowerTick && shortUpperTick == newShortUpperTick) {
            return; // nothing to rebalance
        }

        shortLowerTick = newShortLowerTick;
        shortUpperTick = newShortUpperTick;
        _drainPosition();
    }

    function _swapRebalance() internal {
        (uint160 sqrtPriceX96, , , , , , ) = pool.slot0();
        (uint256[] memory erc20Tvl, , , uint256[] memory totalTvl) = caclulateCurrentTvl(sqrtPriceX96);
        uint256 currentToken0 = totalTvl[0];
        uint256 currentToken1 = totalTvl[1];
        uint256 ratio0 = expectedToken0Ratio(sqrtPriceX96);
        uint256 priceX96 = FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, Q96);
        uint256 capital0 = currentToken0 + FullMath.mulDiv(currentToken1, Q96, priceX96);
        uint256 expectedAmount0 = FullMath.mulDiv(capital0, ratio0, DENOMINATOR);
        if (expectedAmount0 > currentToken0) {
            uint256 amount1 = FullMath.mulDiv(expectedAmount0 - currentToken0, priceX96, Q96);
            if (amount1 > erc20Tvl[1]) {
                uint256[] memory needToPull = new uint256[](2);
                needToPull[1] = amount1;
                uint256[] memory pulled = moneyVault.pull(
                    address(erc20Vault),
                    erc20Vault.vaultTokens(),
                    needToPull,
                    ""
                );
                if (pulled[1] < needToPull[1]) {
                    needToPull[1] = needToPull[1] - pulled[1];
                    uniV3Vault.pull(address(erc20Vault), erc20Vault.vaultTokens(), needToPull, "");
                }
            }
            _swapOneToAnother(-int256(expectedAmount0 - currentToken0), priceX96);
        } else {
            if (currentToken0 - expectedAmount0 > erc20Tvl[0]) {
                uint256[] memory needToPull = new uint256[](2);
                needToPull[0] = currentToken0 - expectedAmount0;
                uint256[] memory pulled = moneyVault.pull(
                    address(erc20Vault),
                    erc20Vault.vaultTokens(),
                    needToPull,
                    ""
                );
                if (pulled[0] < needToPull[0]) {
                    needToPull[0] = needToPull[0] - pulled[0];
                    uniV3Vault.pull(address(erc20Vault), erc20Vault.vaultTokens(), needToPull, "");
                }
            }
            _swapOneToAnother(int256(currentToken0 - expectedAmount0), priceX96);
        }
    }

    function _liquidityRebalance() internal {
        _mintPositionInNeeded();
        (uint160 sqrtPriceX96, , , , , , ) = pool.slot0();
        (, uint256[] memory uniV3Tvl, uint256[] memory moneyTvl, uint256[] memory totalTvl) = caclulateCurrentTvl(
            sqrtPriceX96
        );

        uint256 uniV3RatioD = FullMath.mulDiv(
            DENOMINATOR,
            2 *
                Q96 -
                FullMath.mulDiv(TickMath.getSqrtRatioAtTick(shortLowerTick), Q96, sqrtPriceX96) -
                FullMath.mulDiv(sqrtPriceX96, Q96, TickMath.getSqrtRatioAtTick(shortUpperTick)),
            2 *
                Q96 -
                FullMath.mulDiv(TickMath.getSqrtRatioAtTick(domainLowerTick), Q96, sqrtPriceX96) -
                FullMath.mulDiv(sqrtPriceX96, Q96, TickMath.getSqrtRatioAtTick(domainUpperTick))
        );

        uint256[] memory uniV3Expected = new uint256[](2);
        uint256[] memory moneyExpected = new uint256[](2);

        uniV3Expected[0] = FullMath.mulDiv(totalTvl[0], uniV3RatioD, DENOMINATOR);
        uniV3Expected[1] = FullMath.mulDiv(totalTvl[1], uniV3RatioD, DENOMINATOR);

        moneyExpected[0] = FullMath.mulDiv(totalTvl[0] - uniV3Expected[0], DENOMINATOR - erc20CapitalD, DENOMINATOR);
        moneyExpected[1] = FullMath.mulDiv(totalTvl[1] - uniV3Expected[1], DENOMINATOR - erc20CapitalD, DENOMINATOR);

        _pullExtra(uniV3Vault, uniV3Tvl, uniV3Expected);
        _pullExtra(moneyVault, moneyTvl, moneyExpected);

        _pullMissing(uniV3Vault, uniV3Tvl, uniV3Expected);
        _pullMissing(moneyVault, moneyTvl, moneyExpected);
    }

    function expectedToken0Ratio(uint160 sqrtC) public view returns (uint256 ratio0) {
        uint160 sqrtA = TickMath.getSqrtRatioAtTick(domainLowerTick);
        uint160 sqrtB = TickMath.getSqrtRatioAtTick(domainUpperTick);

        ratio0 = FullMath.mulDiv(DENOMINATOR, sqrtB - sqrtC, 2 * sqrtB - sqrtC - FullMath.mulDiv(sqrtA, sqrtB, sqrtC));
    }

    function _pullExtra(
        IIntegrationVault vault,
        uint256[] memory current,
        uint256[] memory expected
    ) internal returns (uint256[] memory tokenAmounts) {
        if (expected[0] < current[0] || expected[1] < current[1]) {
            uint256[] memory pullAmount = new uint256[](2);
            pullAmount[0] = current[0] - expected[0];
            pullAmount[1] = current[1] - expected[1];
            tokenAmounts = vault.pull(address(erc20Vault), vault.vaultTokens(), pullAmount, "");
        }
    }

    function _pullMissing(
        IIntegrationVault vault,
        uint256[] memory current,
        uint256[] memory expected
    ) internal returns (uint256[] memory tokenAmounts) {
        if (expected[0] > current[0] || expected[1] > current[1]) {
            uint256[] memory pullAmount = new uint256[](2);
            pullAmount[0] = expected[0] - current[0];
            pullAmount[1] = expected[1] - current[1];
            tokenAmounts = erc20Vault.pull(address(vault), vault.vaultTokens(), pullAmount, "");
        }
    }

    function _swapOneToAnother(int256 amount0, uint256 priceX96) internal {
        address[] memory tokens = erc20Vault.vaultTokens();

        uint256 tokenInIndex = 0;
        uint256 amountIn;
        if (amount0 > 0) {
            amountIn = uint256(amount0);
        } else {
            amountIn = uint256(FullMath.mulDiv(uint256(-amount0), priceX96, Q96));
            tokenInIndex = 1;
        }

        {}

        bytes memory routerResult;
        ISwapRouter.ExactInputSingleParams memory swapParams = ISwapRouter.ExactInputSingleParams({
            tokenIn: tokens[tokenInIndex],
            tokenOut: tokens[tokenInIndex ^ 1],
            fee: swapFees,
            recipient: address(erc20Vault),
            deadline: type(uint256).max,
            amountIn: amountIn,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });

        bytes memory data = abi.encode(swapParams);
        erc20Vault.externalCall(tokens[tokenInIndex], APPROVE_SELECTOR, abi.encode(address(router), amountIn));
        routerResult = erc20Vault.externalCall(address(router), EXACT_INPUT_SINGLE_SELECTOR, data);
        erc20Vault.externalCall(tokens[tokenInIndex], APPROVE_SELECTOR, abi.encode(address(router), 0));
    }

    function _mintPositionInNeeded() internal {
        address[] memory tokens = erc20Vault.vaultTokens();
        if (uniV3Nft == 0) {
            uint256[] memory pullExistentials = erc20Vault.pullExistentials();
            uint256[] memory tokenAmounts = new uint256[](2);
            tokenAmounts[0] = pullExistentials[0] * 10;
            tokenAmounts[1] = pullExistentials[1] * 10;

            IERC20(tokens[0]).safeApprove(address(positionManager), tokenAmounts[0]);
            IERC20(tokens[1]).safeApprove(address(positionManager), tokenAmounts[1]);

            (uint256 newNft, , , ) = positionManager.mint(
                INonfungiblePositionManager.MintParams({
                    token0: tokens[0],
                    token1: tokens[1],
                    fee: pool.fee(),
                    tickLower: shortLowerTick,
                    tickUpper: shortUpperTick,
                    amount0Desired: tokenAmounts[0],
                    amount1Desired: tokenAmounts[1],
                    amount0Min: 0,
                    amount1Min: 0,
                    recipient: address(this),
                    deadline: type(uint256).max
                })
            );
            IERC20(tokens[0]).safeApprove(address(positionManager), 0);
            IERC20(tokens[1]).safeApprove(address(positionManager), 0);

            uint256 oldNft = uniV3Vault.uniV3Nft();
            positionManager.safeTransferFrom(address(this), address(uniV3Vault), newNft);
            if (oldNft != 0) {
                positionManager.burn(oldNft);
            }
        }
    }

    function _drainPosition() internal {
        if (uniV3Nft != 0) {
            uniV3Vault.pull(
                address(erc20Vault),
                erc20Vault.vaultTokens(),
                uniV3Vault.liquidityToTokenAmounts(type(uint128).max),
                ""
            );
            uniV3Nft = 0;
        }
    }

    function _contractName() internal pure override returns (bytes32) {
        return bytes32("HStrategyV2");
    }

    function _contractVersion() internal pure override returns (bytes32) {
        return bytes32("1.0.0");
    }
}
