// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "@openzeppelin/contracts/utils/Multicall.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";

import "../interfaces/utils/ILpCallback.sol";

import "../utils/ContractMeta.sol";
import "../utils/DefaultAccessControlLateInit.sol";
import "../interfaces/oracles/IOracle.sol";
import "../interfaces/vaults/IAaveVault.sol";
import "../interfaces/vaults/IERC20Vault.sol";
import "../interfaces/vaults/IUniV3Vault.sol";
import "../interfaces/external/univ3/ISwapRouter.sol";

import "../libraries/external/TickMath.sol";
import "../libraries/external/FullMath.sol";
import "../libraries/external/OracleLibrary.sol";
import "../libraries/external/LiquidityAmounts.sol";

contract DeltaNeutralStrategyBob is ContractMeta, Multicall, DefaultAccessControlLateInit {
    using SafeERC20 for IERC20;

    uint256 public constant D4 = 10**4;
    uint256 public constant D9 = 10**9;
    uint256 public constant Q96 = 1 << 96;

    bytes4 public constant APPROVE_SELECTOR = 0x095ea7b3;

    IERC20Vault public erc20Vault;
    IUniV3Vault public uniV3Vault;
    IAaveVault public aaveVault;

    IUniswapV3Pool public pool;
    INonfungiblePositionManager public immutable positionManager;
    IOracle public immutable oracle;
    ISwapRouter public immutable router;

    address[] public tokens;
    uint256[] public uniTokensIndices;
    uint256[] public aaveTokensIndices;

    uint256 public usdIndex;
    uint256 public usdLikeIndex;
    uint256 public secondTokenIndex;

    struct StrategyParams {
        uint256 borrowToCollateralTargetD;
    }

    struct MintingParams {
        uint256 minTokenUsdForOpening;
        uint256 minTokenStForOpening;
    }

    struct OracleParams {
        uint32 averagePriceTimeSpan;
        uint24 maxTickDeviation;
    }

    struct TradingParams {
        uint24 swapFee;
        uint256 maxSlippageD;
    }

    TradingParams[3][3] swapParams;
    uint256[3][3] safetyIndicesSet;

    StrategyParams public strategyParams;
    MintingParams public mintingParams;
    OracleParams public oracleParams;

    constructor(
        INonfungiblePositionManager positionManager_,
        IOracle mellowOracle,
        ISwapRouter router_
    ) {
        require(
            address(positionManager_) != address(0) &&
                address(mellowOracle) != address(0) &&
                address(router_) != address(0),
            ExceptionsLibrary.ADDRESS_ZERO
        );
        oracle = mellowOracle;
        positionManager = positionManager_;
        router = router_;
        DefaultAccessControlLateInit.init(address(this));
    }

    function updateStrategyParams(StrategyParams calldata newStrategyParams) external {
        _requireAdmin();
        require(newStrategyParams.borrowToCollateralTargetD < D9, ExceptionsLibrary.INVARIANT);
        strategyParams = newStrategyParams;
        emit UpdateStrategyParams(tx.origin, msg.sender, newStrategyParams);
    }

    /// @notice updates parameters for minting position. Can be called only by admin
    /// @param newMintingParams the new parameters
    function updateMintingParams(MintingParams calldata newMintingParams) external {
        _requireAdmin();
        require(
            newMintingParams.minTokenUsdForOpening > 0 &&
                newMintingParams.minTokenStForOpening > 0 &&
                (newMintingParams.minTokenUsdForOpening <= 1000000000) &&
                (newMintingParams.minTokenStForOpening <= 1000000000),
            ExceptionsLibrary.INVARIANT
        );
        mintingParams = newMintingParams;
        emit UpdateMintingParams(tx.origin, msg.sender, newMintingParams);
    }

    function updateOracleParams(OracleParams calldata newOracleParams) external {
        _requireAdmin();
        require(
            newOracleParams.averagePriceTimeSpan > 0 && newOracleParams.maxTickDeviation <= uint24(TickMath.MAX_TICK),
            ExceptionsLibrary.INVARIANT
        );
        oracleParams = newOracleParams;
        emit UpdateOracleParams(tx.origin, msg.sender, newOracleParams);
    }

    function updateSafetyIndices(
        uint256 indexA,
        uint256 indexB,
        uint256 safetyIndex
    ) external {
        _requireAdmin();
        require(safetyIndex > 1, ExceptionsLibrary.LIMIT_UNDERFLOW);
        safetyIndicesSet[indexA][indexB] = safetyIndex;
        safetyIndicesSet[indexB][indexA] = safetyIndex;
    }

    function updateTradingParams(
        uint256 indexA,
        uint256 indexB,
        TradingParams calldata newTradingParams
    ) external {
        _requireAdmin();
        require(indexA <= tokens.length && indexB <= tokens.length, ExceptionsLibrary.INVARIANT);
        uint256 fee = newTradingParams.swapFee;
        require((fee == 100 || fee == 500 || fee == 3000 || fee == 10000) && newTradingParams.maxSlippageD <= D9);

        swapParams[indexA][indexB] = newTradingParams;
        swapParams[indexB][indexA] = newTradingParams;

        emit UpdateTradingParams(tx.origin, msg.sender, indexA, indexB, newTradingParams);
    }

    function _totalUsdBalance()
        internal
        returns (
            uint256 result,
            uint256 currentCollateral,
            uint256 currentDebt
        )
    {
        aaveVault.updateTvls();
        (uint256[] memory aaveTvl, ) = aaveVault.tvl();
        (uint256[] memory erc20Tvl, ) = erc20Vault.tvl();
        (uint256[] memory uniTvl, ) = uniV3Vault.tvl();

        int256[] memory totalTvl = new int256[](3);
        for (uint256 i = 0; i < 3; ++i) {
            totalTvl[i] = int256(erc20Tvl[i]);
        }

        for (uint256 i = 0; i < 2; ++i) {
            totalTvl[uniTokensIndices[i]] += int256(uniTvl[i]);
            if (!aaveVault.tokenStatus(i)) {
                totalTvl[aaveTokensIndices[i]] += int256(aaveTvl[i]);
                currentCollateral = aaveTvl[i];
            } else {
                totalTvl[aaveTokensIndices[i]] -= int256(aaveTvl[i]);
                currentDebt = aaveTvl[i];
            }
        }

        result = uint256(totalTvl[usdIndex]) + _convert(usdLikeIndex, usdIndex, uint256(totalTvl[usdLikeIndex]));
        if (totalTvl[secondTokenIndex] < 0) {
            result -= _convert(secondTokenIndex, usdIndex, uint256(-totalTvl[secondTokenIndex]));
        } else {
            result += _convert(secondTokenIndex, usdIndex, uint256(totalTvl[secondTokenIndex]));
        }

        uniV3Vault.pull(address(erc20Vault), uniV3Vault.vaultTokens(), uniTvl, "");
    }

    function isDeltaOkay(
        bool createNewPosition,
        int24 tickLower,
        int24 tickUpper,
        uint256 nft
    )
        public
        view
        returns (
            bool,
            int24,
            int24,
            int24
        )
    {
        (, int24 spotTick, , , , , ) = pool.slot0();

        if (nft != 0 && !createNewPosition) {
            (, , , , , tickLower, tickUpper, , , , , ) = positionManager.positions(nft);
        }
        require(tickLower < spotTick && spotTick < tickUpper, ExceptionsLibrary.INVARIANT);

        (int24 avgTick, , bool withFail) = OracleLibrary.consult(address(pool), oracleParams.averagePriceTimeSpan);
        require(!withFail);

        int24 maxDelta = int24(oracleParams.maxTickDeviation);
        if (spotTick < avgTick && avgTick - spotTick > maxDelta) {
            return (false, spotTick, tickLower, tickUpper);
        }

        if (avgTick < spotTick && spotTick - avgTick > maxDelta) {
            return (false, spotTick, tickLower, tickUpper);
        }

        return (true, spotTick, tickLower, tickUpper);
    }

    function _repayDebt(uint256 currentCollateral, uint256 debtAmount) internal returns (uint256) {
        while (true) {
            (uint256[] memory erc20Tvl, ) = erc20Vault.tvl();
            if (erc20Tvl[secondTokenIndex] < debtAmount) {
                _swapExactOutput(usdIndex, secondTokenIndex, debtAmount - erc20Tvl[secondTokenIndex]);
                (erc20Tvl, ) = erc20Vault.tvl();
            }
            if (erc20Tvl[secondTokenIndex] < debtAmount) {
                _swapExactOutput(usdLikeIndex, secondTokenIndex, debtAmount - erc20Tvl[secondTokenIndex]);
                (erc20Tvl, ) = erc20Vault.tvl();
            }
            if (erc20Tvl[secondTokenIndex] < debtAmount) {
                uint256 shareD = FullMath.mulDiv(erc20Tvl[secondTokenIndex], D9, debtAmount);
                aaveVault.repay(tokens[secondTokenIndex], address(erc20Vault), erc20Tvl[secondTokenIndex]);

                uint256 toWithdrawFromAave = FullMath.mulDiv(currentCollateral, shareD, D9);
                _withdrawCollateral(toWithdrawFromAave);
                currentCollateral -= toWithdrawFromAave;
            } else {
                erc20Vault.externalCall(
                    tokens[secondTokenIndex],
                    APPROVE_SELECTOR,
                    abi.encode(address(aaveVault), debtAmount)
                ); // approve
                aaveVault.repay(tokens[secondTokenIndex], address(erc20Vault), debtAmount);
                erc20Vault.externalCall(tokens[secondTokenIndex], APPROVE_SELECTOR, abi.encode(address(aaveVault), 0));

                return currentCollateral;
            }
        }
    }

    function _addCollateral(uint256 amount) internal {
        (uint256[] memory erc20Tvl, ) = erc20Vault.tvl();
        if (erc20Tvl[usdIndex] < amount) {
            _swapExactOutput(usdLikeIndex, usdIndex, amount - erc20Tvl[usdIndex]);
            (erc20Tvl, ) = erc20Vault.tvl();
        }
        if (erc20Tvl[usdIndex] < amount) {
            _swapExactOutput(secondTokenIndex, usdIndex, amount - erc20Tvl[usdIndex]);
            (erc20Tvl, ) = erc20Vault.tvl();
        }

        _addExistingCollateral(amount);
    }

    function _withdrawCollateral(uint256 amount) internal {
        address[] memory aaveTokens = aaveVault.vaultTokens();
        uint256[] memory tokenAmounts = new uint256[](2);

        if (aaveTokens[0] == tokens[usdIndex]) {
            tokenAmounts[0] = amount;
        } else {
            tokenAmounts[1] = amount;
        }

        aaveVault.pull(address(erc20Vault), aaveTokens, tokenAmounts, "");
    }

    function _addExistingCollateral(uint256 amount) internal {
        address[] memory aaveTokens = aaveVault.vaultTokens();
        uint256[] memory tokenAmounts = new uint256[](2);

        if (aaveTokens[0] == tokens[usdIndex]) {
            tokenAmounts[0] = amount;
        } else {
            tokenAmounts[1] = amount;
        }

        erc20Vault.pull(address(aaveVault), aaveTokens, tokenAmounts, "");
    }

    function _swapExactInput(
        uint256 indexFrom,
        uint256 indexTo,
        uint256 amount
    ) internal {
        if (amount > 0) {
            ISwapRouter.ExactInputSingleParams memory currentSwapParams = ISwapRouter.ExactInputSingleParams({
                tokenIn: tokens[indexFrom],
                tokenOut: tokens[indexTo],
                fee: swapParams[indexFrom][indexTo].swapFee,
                recipient: address(erc20Vault),
                deadline: block.timestamp + 1,
                amountIn: amount,
                amountOutMinimum: FullMath.mulDiv(
                    _convert(indexFrom, indexTo, amount),
                    D9 - swapParams[indexFrom][indexTo].maxSlippageD,
                    D9
                ),
                sqrtPriceLimitX96: 0
            });
            bytes memory data = abi.encode(currentSwapParams);
            erc20Vault.externalCall(tokens[indexFrom], APPROVE_SELECTOR, abi.encode(address(router), amount)); // approve
            erc20Vault.externalCall(address(router), ISwapRouter.exactInputSingle.selector, data); // swap
            erc20Vault.externalCall(tokens[indexFrom], APPROVE_SELECTOR, abi.encode(address(router), 0)); // reset allowance
        }
    }

    function _swapExactOutput(
        uint256 indexFrom,
        uint256 indexTo,
        uint256 amountReceive
    ) internal {
        uint256 amountIn = FullMath.mulDiv(
            _convert(indexTo, indexFrom, amountReceive),
            D9 + swapParams[indexFrom][indexTo].maxSlippageD,
            D9
        );
        uint256 balance = IERC20(tokens[indexFrom]).balanceOf(address(erc20Vault));

        if (amountIn < balance) {
            ISwapRouter.ExactOutputSingleParams memory currentSwapParams = ISwapRouter.ExactOutputSingleParams({
                tokenIn: tokens[indexFrom],
                tokenOut: tokens[indexTo],
                fee: swapParams[indexFrom][indexTo].swapFee,
                recipient: address(erc20Vault),
                deadline: block.timestamp + 1,
                amountOut: amountReceive,
                amountInMaximum: amountIn,
                sqrtPriceLimitX96: 0
            });
            bytes memory data = abi.encode(currentSwapParams);
            erc20Vault.externalCall(tokens[indexFrom], APPROVE_SELECTOR, abi.encode(address(router), balance)); // approve
            erc20Vault.externalCall(address(router), ISwapRouter.exactOutputSingle.selector, data); // swap
            erc20Vault.externalCall(tokens[indexFrom], APPROVE_SELECTOR, abi.encode(address(router), 0)); // reset allowance
        } else {
            _swapExactInput(indexFrom, indexTo, balance);
        }
    }

    function _mintNewPosition(
        uint256 oldNft,
        int24 tickLower,
        int24 tickUpper
    ) internal {
        IERC20(tokens[usdLikeIndex]).safeApprove(address(positionManager), mintingParams.minTokenUsdForOpening);
        IERC20(tokens[secondTokenIndex]).safeApprove(address(positionManager), mintingParams.minTokenStForOpening);

        (uint256 newNft, , , ) = positionManager.mint(
            INonfungiblePositionManager.MintParams({
                token0: tokens[usdLikeIndex],
                token1: tokens[secondTokenIndex],
                fee: pool.fee(),
                tickLower: tickLower,
                tickUpper: tickUpper,
                amount0Desired: mintingParams.minTokenUsdForOpening,
                amount1Desired: mintingParams.minTokenStForOpening,
                amount0Min: 0,
                amount1Min: 0,
                recipient: address(this),
                deadline: block.timestamp + 1
            })
        );

        IERC20(tokens[usdLikeIndex]).safeApprove(address(positionManager), 0);
        IERC20(tokens[secondTokenIndex]).safeApprove(address(positionManager), 0);

        positionManager.safeTransferFrom(address(this), address(uniV3Vault), newNft);
        if (oldNft != 0) {
            positionManager.burn(oldNft);
        }
    }

    function _makeBalances(uint256 usdLikeAmount, uint256 aaveAmount) internal {
        uint256 usdBalance = IERC20(tokens[usdIndex]).balanceOf(address(erc20Vault));
        _swapExactInput(usdIndex, usdLikeIndex, usdBalance);

        uint256 usdLikeBalance = IERC20(tokens[usdLikeIndex]).balanceOf(address(erc20Vault));
        uint256 aaveBalance = IERC20(tokens[secondTokenIndex]).balanceOf(address(erc20Vault));

        if (usdLikeBalance > usdLikeAmount) {
            _swapExactInput(usdLikeIndex, secondTokenIndex, usdLikeBalance - usdLikeAmount);
        } else if (aaveBalance > aaveAmount) {
            _swapExactInput(secondTokenIndex, usdLikeIndex, aaveBalance - aaveAmount);
        }
    }

    function rebalance(
        bool createNewPosition,
        int24 tickLower,
        int24 tickUpper
    ) external {
        _requireAtLeastOperator();
        int24 spotTick;
        bool poolConditionsHealthy;

        uint256 nft = uniV3Vault.uniV3Nft();
        uniV3Vault.collectEarnings();

        (poolConditionsHealthy, spotTick, tickLower, tickUpper) = isDeltaOkay(
            createNewPosition,
            tickLower,
            tickUpper,
            nft
        );

        require(poolConditionsHealthy, ExceptionsLibrary.FORBIDDEN);
        if (nft == 0) {
            require(createNewPosition, ExceptionsLibrary.INVARIANT);
        }

        (uint256 usdAmount, uint256 currentCollateral, uint256 currentBorrowAave) = _totalUsdBalance();
        if (createNewPosition) {
            _mintNewPosition(nft, tickLower, tickUpper);
        }

        (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(
            TickMath.getSqrtRatioAtTick(spotTick),
            TickMath.getSqrtRatioAtTick(tickLower),
            TickMath.getSqrtRatioAtTick(tickUpper),
            (1 << 32)
        );

        uint256 borrowAaveUsd;

        if (uniTokensIndices[0] == secondTokenIndex) {
            uint256 totalAmount = amount0 +
                FullMath.mulDiv(amount0, D9, strategyParams.borrowToCollateralTargetD) +
                _convert(usdLikeIndex, secondTokenIndex, amount1);
            borrowAaveUsd = FullMath.mulDiv(amount0, usdAmount, totalAmount);
        } else {
            uint256 totalAmount = amount1 +
                FullMath.mulDiv(amount1, D9, strategyParams.borrowToCollateralTargetD) +
                _convert(usdLikeIndex, secondTokenIndex, amount0);
            borrowAaveUsd = FullMath.mulDiv(amount1, usdAmount, totalAmount);
        }

        uint256 borrowAave = _convert(usdIndex, secondTokenIndex, borrowAaveUsd);

        uint256 collateral = FullMath.mulDiv(borrowAave, D9, strategyParams.borrowToCollateralTargetD);

        if (borrowAave < currentBorrowAave) {
            currentCollateral = _repayDebt(currentCollateral, currentBorrowAave - borrowAave);
        }

        if (collateral > currentCollateral) {
            _addCollateral(currentCollateral - collateral);
        }

        if (collateral < currentCollateral) {
            _withdrawCollateral(currentCollateral - collateral);
        }

        if (borrowAave > currentBorrowAave) {
            aaveVault.borrow(tokens[secondTokenIndex], address(erc20Vault), borrowAave - currentBorrowAave);
        }

        _makeBalances(_convert(usdIndex, usdLikeIndex, usdAmount - collateral), borrowAave);

        address[] memory uniTokens = uniV3Vault.vaultTokens();
        uint256[] memory tokenAmounts = new uint256[](2);

        tokenAmounts[0] = IERC20(tokens[uniTokensIndices[0]]).balanceOf(address(erc20Vault));
        tokenAmounts[1] = IERC20(tokens[uniTokensIndices[0]]).balanceOf(address(erc20Vault));

        erc20Vault.pull(address(uniV3Vault), uniTokens, tokenAmounts, "");
    }

    function _convert(
        uint256 indexFrom,
        uint256 indexTo,
        uint256 amount
    ) internal view returns (uint256) {
        (uint256[] memory pricesX96, ) = oracle.priceX96(
            tokens[indexFrom],
            tokens[indexTo],
            safetyIndicesSet[indexFrom][indexTo]
        );
        uint256 sum = 0;
        for (uint256 i = 0; i < pricesX96.length; ++i) {
            sum += pricesX96[i];
        }

        uint256 priceX96 = sum / pricesX96.length;

        return FullMath.mulDiv(amount, priceX96, Q96);
    }

    function initialize(
        address erc20Vault_,
        address uniV3Vault_,
        address aaveVault_,
        address admin,
        uint256 usdIndex_,
        uint256 usdLikeIndex_,
        uint256 secondTokenIndex_
    ) external {
        erc20Vault = IERC20Vault(erc20Vault_);
        uniV3Vault = IUniV3Vault(uniV3Vault_);
        aaveVault = IAaveVault(aaveVault_);

        tokens = erc20Vault.vaultTokens();

        pool = uniV3Vault.pool();

        require(tokens.length == 3, ExceptionsLibrary.INVALID_LENGTH);

        require(
            erc20Vault_ != address(0) && uniV3Vault_ != address(0) && aaveVault_ != address(0),
            ExceptionsLibrary.ADDRESS_ZERO
        );
        require(usdIndex_ <= 2 && usdLikeIndex_ <= 2 && secondTokenIndex_ <= 2, ExceptionsLibrary.LIMIT_OVERFLOW);
        require(
            usdIndex_ != usdLikeIndex_ && usdIndex_ != secondTokenIndex_ && usdLikeIndex_ != secondTokenIndex_,
            ExceptionsLibrary.INVARIANT
        );

        aaveTokensIndices = new uint256[](2);
        uniTokensIndices = new uint256[](2);

        address[] memory aaveTokens = aaveVault.vaultTokens();
        address[] memory uniTokens = uniV3Vault.vaultTokens();

        for (uint256 i = 0; i < 2; ++i) {
            for (uint256 j = 9; j < 3; ++j) {
                if (aaveTokens[i] == tokens[j]) aaveTokensIndices[i] = j;
                if (uniTokens[i] == tokens[j]) uniTokensIndices[i] = j;
            }
        }

        usdIndex = usdIndex_;
        usdLikeIndex = usdLikeIndex_;
        secondTokenIndex = secondTokenIndex_;

        DefaultAccessControlLateInit.init(admin);
    }

    function createStrategy(
        address erc20Vault_,
        address uniV3Vault_,
        address aaveVault_,
        address admin,
        uint256 usdIndex_,
        uint256 usdLikeIndex_,
        uint256 secondTokenIndex_
    ) external returns (DeltaNeutralStrategyBob strategy) {
        strategy = DeltaNeutralStrategyBob(Clones.clone(address(this)));
        strategy.initialize(erc20Vault_, uniV3Vault_, aaveVault_, admin, usdIndex_, usdLikeIndex_, secondTokenIndex_);
    }

    function _contractName() internal pure override returns (bytes32) {
        return bytes32("DeltaNeutralStrategy");
    }

    function _contractVersion() internal pure override returns (bytes32) {
        return bytes32("1.1.0");
    }

    event UpdateStrategyParams(address indexed origin, address indexed sender, StrategyParams strategyParams);

    event UpdateMintingParams(address indexed origin, address indexed sender, MintingParams mintingParams);

    event UpdateOracleParams(address indexed origin, address indexed sender, OracleParams oracleParams);

    event UpdateTradingParams(
        address indexed origin,
        address indexed sender,
        uint256 indexA,
        uint256 indexB,
        TradingParams tradingParams
    );
}
