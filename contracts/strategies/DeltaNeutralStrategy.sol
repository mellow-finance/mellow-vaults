// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "@openzeppelin/contracts/utils/Multicall.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";

import "../interfaces/utils/ILpCallback.sol";

import "../utils/ContractMeta.sol";
import "../utils/DefaultAccessControlLateInit.sol";
import "../interfaces/vaults/IAaveVault.sol";
import "../interfaces/vaults/IERC20Vault.sol";
import "../interfaces/vaults/IUniV3Vault.sol";
import "../interfaces/external/univ3/ISwapRouter.sol";

import "../libraries/external/TickMath.sol";
import "../libraries/external/FullMath.sol";
import "../libraries/external/OracleLibrary.sol";

contract DeltaNeutralStrategy is ContractMeta, Multicall, DefaultAccessControlLateInit, ILpCallback {

    using SafeERC20 for IERC20;

    uint256 public constant D4 = 10**4;
    uint256 public constant D9 = 10**9;
    uint256 public constant Q96 = 1<<96;

    bytes4 public constant APPROVE_SELECTOR = 0x095ea7b3;
    bytes4 public constant EXACT_INPUT_SINGLE_SELECTOR = ISwapRouter.exactInputSingle.selector;

    IERC20Vault public erc20Vault;
    IUniV3Vault public uniV3Vault;
    IAaveVault public aaveVault;

    INonfungiblePositionManager public immutable positionManager;
    ISwapRouter public immutable router;

    address[] public tokens;

    int24 public lastRebalanceTick;
    bool public wasRebalance;
    IUniswapV3Pool public pool;

    struct StrategyParams {
        int24 positionTickSize;
        int24 rebalanceTickDelta;
    }

    struct MintingParams {
        uint256 minToken0ForOpening;
        uint256 minToken1ForOpening;
    }

    struct OracleParams {
        uint32 averagePriceTimeSpan;
        uint24 maxTickDeviation;
    }

    struct TradingParams {
        uint24 swapFee;
        uint256 maxSlippageD;
    }

    StrategyParams public strategyParams;
    MintingParams public mintingParams;
    OracleParams public oracleParams;
    TradingParams public tradingParams;

    /// @notice updates parameters of the strategy. Can be called only by admin
    /// @param newStrategyParams the new parameters
    function updateStrategyParams(StrategyParams calldata newStrategyParams) external {
        _requireAdmin();
        int24 tickSpacing = pool.tickSpacing();
        require(
            newStrategyParams.positionTickSize % tickSpacing == 0 && newStrategyParams.positionTickSize > newStrategyParams.rebalanceTickDelta && newStrategyParams.rebalanceTickDelta > 0 && newStrategyParams.rebalanceTickDelta <= 10000,
            ExceptionsLibrary.INVARIANT
        );
        emit UpdateStrategyParams(tx.origin, msg.sender, newStrategyParams);
    }

    /// @notice updates parameters for minting position. Can be called only by admin
    /// @param newMintingParams the new parameters
    function updateMintingParams(MintingParams calldata newMintingParams) external {
        _requireAdmin();
        require(
            newMintingParams.minToken0ForOpening > 0 &&
                newMintingParams.minToken1ForOpening > 0 &&
                (newMintingParams.minToken0ForOpening <= 1000000000) &&
                (newMintingParams.minToken1ForOpening <= 1000000000),
            ExceptionsLibrary.INVARIANT
        );
        mintingParams = newMintingParams;
        emit UpdateMintingParams(tx.origin, msg.sender, newMintingParams);
    }

    /// @notice updates oracle parameters. Can be called only by admin
    /// @param newOracleParams the new parameters
    function updateOracleParams(OracleParams calldata newOracleParams) external {
        _requireAdmin();
        require(
            newOracleParams.averagePriceTimeSpan > 0 && newOracleParams.maxTickDeviation <= uint24(TickMath.MAX_TICK),
            ExceptionsLibrary.INVARIANT
        );
        oracleParams = newOracleParams;
        emit UpdateOracleParams(tx.origin, msg.sender, newOracleParams);
    }

    function updateTradingParams(TradingParams calldata newTradingParams) external {
        _requireAdmin();
        uint256 fee = newTradingParams.swapFee;
        require((fee == 100 || fee == 500 || fee == 3000 || fee == 10000) && newTradingParams.maxSlippageD <= D9,
            ExceptionsLibrary.INVALID_VALUE
        );
        tradingParams = newTradingParams;
        emit UpdateTradingParams(tx.origin, msg.sender, tradingParams);
    }

    function isDeltaOkay() public view returns (bool, int24) {
        (, int24 spotTick, , , , , ) = pool.slot0();
        (int24 avgTick, , bool withFail) = OracleLibrary.consult(address(pool), oracleParams.averagePriceTimeSpan);
        require(!withFail, ExceptionsLibrary.INVALID_STATE);

        int24 maxDelta = int24(oracleParams.maxTickDeviation);

        if (spotTick < avgTick && avgTick - spotTick > maxDelta) {
            return (false, spotTick);
        }

        if (avgTick < spotTick && spotTick - avgTick > maxDelta) {
            return (false, spotTick);
        }

        return (true, spotTick);
    }

    constructor(INonfungiblePositionManager positionManager_, ISwapRouter router_) {
        require(address(positionManager_) != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        require(address(router_) != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        positionManager = positionManager_;
        router = router_;
        DefaultAccessControlLateInit.init(address(this));
    }

    function initialize(address erc20Vault_, address uniV3Vault_, address aaveVault_, address admin) external {
        erc20Vault = IERC20Vault(erc20Vault_);
        uniV3Vault = IUniV3Vault(uniV3Vault_);
        aaveVault = IAaveVault(aaveVault_);

        address[] memory erc20Tokens = erc20Vault.vaultTokens();
        address[] memory aaveTokens = aaveVault.vaultTokens();
        address[] memory uniV3Tokens = uniV3Vault.vaultTokens();
        require(aaveTokens.length == 2, ExceptionsLibrary.INVALID_LENGTH);
        require(erc20Tokens.length == 2, ExceptionsLibrary.INVALID_LENGTH);
        require(uniV3Tokens.length == 2, ExceptionsLibrary.INVALID_LENGTH);

        require(uniV3Tokens[0] == aaveTokens[0], ExceptionsLibrary.INVARIANT);
        require(erc20Tokens[0] == aaveTokens[0], ExceptionsLibrary.INVARIANT);
        require(uniV3Tokens[1] == aaveTokens[1], ExceptionsLibrary.INVARIANT);
        require(erc20Tokens[1] == aaveTokens[1], ExceptionsLibrary.INVARIANT);
        

        tokens = uniV3Tokens;
        pool = uniV3Vault.pool();
        require(address(pool) != address(0), ExceptionsLibrary.INVALID_TARGET);

        DefaultAccessControlLateInit.init(admin);
    }

    function rebalance() external {
        (bool deltaOkay, int24 spotTick) = isDeltaOkay();
        require(deltaOkay, ExceptionsLibrary.INVARIANT);
        int24 ticksDelta;
        if (spotTick < lastRebalanceTick) {
            ticksDelta = lastRebalanceTick - spotTick;
        }
        else {
            ticksDelta = spotTick - lastRebalanceTick;
        }
        require(!wasRebalance || ticksDelta >= strategyParams.rebalanceTickDelta);
        _closePosition();
        _openPosition();
    }

    function _closePosition() internal {
        uint256 uniV3Nft = uniV3Vault.uniV3Nft();
        if (uniV3Nft != 0) {
            uint256[] memory uniV3TokenAmounts = uniV3Vault.liquidityToTokenAmounts(type(uint128).max);
            uniV3Vault.pull(address(erc20Vault), tokens, uniV3TokenAmounts, "");
        }

        uint256 debt = aaveVault.getDebt(1);
        if (debt == 0) {
            return;
        }

        _getCoverage(debt);
        uint256 balance = IERC20(tokens[1]).balanceOf(address(erc20Vault));
        erc20Vault.externalCall(tokens[1], APPROVE_SELECTOR, abi.encode(address(aaveVault), debt)); // approve
        aaveVault.repay(tokens[1], address(erc20Vault), debt);
        erc20Vault.externalCall(tokens[1], APPROVE_SELECTOR, abi.encode(address(aaveVault), 0)); // reset allowance
    }

    function _openPosition() internal {

        uint160 maxSqrtX96Delta = TickMath.getSqrtRatioAtTick(strategyParams.rebalanceTickDelta);
        uint256 maxX96Delta = FullMath.mulDiv(maxSqrtX96Delta, maxSqrtX96Delta, Q96);

        uint256 ltvQ96 = FullMath.mulDiv(aaveVault.getLTV(tokens[0]), Q96, D4);

        uint256 shareD = FullMath.mulDiv(ltvQ96, D9, ltvQ96 + maxX96Delta);
        _swap(1, true, 0);

        uint256 balance = IERC20(tokens[0]).balanceOf(address(erc20Vault));
        uint256 toAave = FullMath.mulDiv(balance, D9 - shareD, D9);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = toAave;

        erc20Vault.pull(address(aaveVault), tokens, amounts, "");
        uint256 amountToTake = _getSwapAmountOut(balance - toAave, 0, false);

        aaveVault.borrow(tokens[1], address(erc20Vault), amountToTake);
        (, int24 spotTick, , , , , ) = pool.slot0();
        int24 lowerTick = (spotTick - strategyParams.positionTickSize / 2) % pool.tickSpacing();
        int24 upperTick = lowerTick + strategyParams.positionTickSize;

        uint256 fromNft = uniV3Vault.uniV3Nft();
        uint256 nft = _mintNewNft(lowerTick, upperTick, block.timestamp + 1);

        positionManager.safeTransferFrom(address(this), address(uniV3Vault), nft);
        positionManager.burn(fromNft);

        uint256[] memory tokenAmounts = new uint256[](2);
        tokenAmounts[0] = IERC20(tokens[0]).balanceOf(address(erc20Vault));
        tokenAmounts[1] = IERC20(tokens[1]).balanceOf(address(erc20Vault));

        erc20Vault.pull(address(uniV3Vault), tokens, tokenAmounts, "");
    }

    function _mintNewNft(
        int24 lowerTick,
        int24 upperTick,
        uint256 deadline
    ) internal returns (uint256 newNft) {
        uint256 minToken0ForOpening = mintingParams.minToken0ForOpening;
        uint256 minToken1ForOpening = mintingParams.minToken1ForOpening;
        IERC20(tokens[0]).safeApprove(address(positionManager), minToken0ForOpening);
        IERC20(tokens[1]).safeApprove(address(positionManager), minToken1ForOpening);
        (newNft, , , ) = positionManager.mint(
            INonfungiblePositionManager.MintParams({
                token0: tokens[0],
                token1: tokens[1],
                fee: pool.fee(),
                tickLower: lowerTick,
                tickUpper: upperTick,
                amount0Desired: minToken0ForOpening,
                amount1Desired: minToken1ForOpening,
                amount0Min: 0,
                amount1Min: 0,
                recipient: address(this),
                deadline: deadline
            })
        );
        IERC20(tokens[0]).safeApprove(address(positionManager), 0);
        IERC20(tokens[1]).safeApprove(address(positionManager), 0);
    }

    function _getCoverage(uint256 debt) internal {
        if (IERC20(tokens[1]).balanceOf(address(erc20Vault)) < debt) {
            _swap(0, true, 0);
        }
    }

    function _swap(uint256 index, bool swapAll, uint256 amount) internal {
        uint256 amountIn = amount;
        if (swapAll) {
            amountIn = IERC20(tokens[index]).balanceOf(address(erc20Vault));
        }
        if (amountIn > 0) {
            ISwapRouter.ExactInputSingleParams memory swapParams = ISwapRouter.ExactInputSingleParams({
                tokenIn: tokens[index],
                tokenOut: tokens[1 - index],
                fee: tradingParams.swapFee,
                recipient: address(erc20Vault),
                deadline: block.timestamp + 1,
                amountIn: amountIn,
                amountOutMinimum: _getSwapAmountOut(amountIn, index, true),
                sqrtPriceLimitX96: 0
            });
            bytes memory data = abi.encode(swapParams);
            erc20Vault.externalCall(tokens[index], APPROVE_SELECTOR, abi.encode(address(router), amountIn)); // approve
            erc20Vault.externalCall(address(router), EXACT_INPUT_SINGLE_SELECTOR, data); // swap
            erc20Vault.externalCall(tokens[index], APPROVE_SELECTOR, abi.encode(address(router), 0)); // reset allowance
        }
    }

    function _getSwapAmountOut(uint256 amount, uint256 index, bool takeSlippage) internal view returns (uint256) {
        (uint160 sqrtPriceX96, , , , , , ) = pool.slot0();
        uint256 priceX96 = FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, Q96);

        uint256 slippage = 0;
        if (takeSlippage) {
            slippage = tradingParams.maxSlippageD;
        }

        if (tokens[index] == pool.token0() && index == 0) {
            uint256 expectedAmount = FullMath.mulDiv(amount, priceX96, Q96);
            return FullMath.mulDiv(expectedAmount, D9 - slippage, D9);
        }

        else {

            uint256 expectedAmount = FullMath.mulDiv(amount, Q96, priceX96);
            return FullMath.mulDiv(expectedAmount, D9 - slippage, D9);

        }
    }

    function _checkCallbackPossible() internal {
        (bool deltaOkay, int24 spotTick) = isDeltaOkay();
        require(deltaOkay, ExceptionsLibrary.INVARIANT);
        int24 ticksDelta;
        if (spotTick < lastRebalanceTick) {
            ticksDelta = lastRebalanceTick - spotTick;
        }
        else {
            ticksDelta = spotTick - lastRebalanceTick;
        }
        require(wasRebalance && ticksDelta < strategyParams.rebalanceTickDelta);
    }

    function _rebalanceERC20Vault() internal {
        uint256 token0OnERC20 = IERC20(tokens[0]).balanceOf(address(erc20Vault));
        uint256 token0CapitalOnERC20 = _getSwapAmountOut(IERC20(tokens[1]).balanceOf(address(erc20Vault)), 1, false) + token0OnERC20;
        (, , , , , , , uint128 liquidity, , , , ) = positionManager.positions(
                uniV3Vault.uniV3Nft()
            );

        uint256[] memory totalOnUni = uniV3Vault.liquidityToTokenAmounts(liquidity);
        uint256 token0CapitalOnUni = _getSwapAmountOut(totalOnUni[1], 1, false) + totalOnUni[0];

        uint256 wantToHaveOnERC20 = FullMath.mulDiv(totalOnUni[0], token0CapitalOnERC20, token0CapitalOnUni);
        if (wantToHaveOnERC20 < token0OnERC20) {
            uint256 delta = token0OnERC20 - wantToHaveOnERC20;
            _swap(0, false, delta);
        }
        else {
            uint256 delta = wantToHaveOnERC20 - token0OnERC20;
            uint256 toSwap = _getSwapAmountOut(delta, 0, false);
            _swap(1, false, toSwap);
        }
    }

    /// @inheritdoc ILpCallback
    function depositCallback(bytes memory depositOptions) external {

        _checkCallbackPossible();

        require(depositOptions.length == 32, ExceptionsLibrary.INVALID_VALUE);
        (
            uint256 shareOfCapitalQ96
        ) = abi.decode(depositOptions, (uint256));

        uint256 balanceToken0 = IERC20(aaveVault.aTokens(0)).balanceOf(address(aaveVault));
        uint256 debtToken1 = aaveVault.getDebt(1);

        uint256[] memory tokenAmounts = new uint256[](2);
        tokenAmounts[0] = FullMath.mulDiv(balanceToken0, shareOfCapitalQ96, Q96);

        erc20Vault.pull(address(aaveVault), tokens, tokenAmounts, "");
        aaveVault.borrow(tokens[1], address(erc20Vault), FullMath.mulDiv(debtToken1, shareOfCapitalQ96, Q96));

        _rebalanceERC20Vault();

        tokenAmounts[0] = IERC20(tokens[0]).balanceOf(address(erc20Vault));
        tokenAmounts[1] = IERC20(tokens[1]).balanceOf(address(erc20Vault));

        erc20Vault.pull(address(uniV3Vault), tokens, tokenAmounts, "");
        
    }

    /// @inheritdoc ILpCallback
    function withdrawCallback(bytes memory depositOptions) external {

        _checkCallbackPossible();

        require(depositOptions.length == 32, ExceptionsLibrary.INVALID_VALUE);
        (
            uint256 shareOfCapitalQ96
        ) = abi.decode(depositOptions, (uint256));

        (, , , , , , , uint128 liquidity, , , , ) = positionManager.positions(
                uniV3Vault.uniV3Nft()
            );

        uniV3Vault.collectEarnings();

        uint256 totalToken0 = FullMath.mulDiv(IERC20(tokens[0]).balanceOf(address(erc20Vault)), shareOfCapitalQ96, Q96);
        uint256 totalToken1 = FullMath.mulDiv(IERC20(tokens[1]).balanceOf(address(erc20Vault)), shareOfCapitalQ96, Q96);

        uint256[] memory pullFromUni = uniV3Vault.liquidityToTokenAmounts(uint128(FullMath.mulDiv(liquidity, shareOfCapitalQ96, Q96)));
        pullFromUni = uniV3Vault.pull(address(erc20Vault), tokens, pullFromUni, "");

        totalToken0 += pullFromUni[0];
        totalToken1 += pullFromUni[1];

        uint256 balanceToken0 = FullMath.mulDiv(IERC20(aaveVault.aTokens(0)).balanceOf(address(aaveVault)), shareOfCapitalQ96, Q96);
        uint256 debtToken1 = FullMath.mulDiv(aaveVault.getDebt(1), shareOfCapitalQ96, Q96);

        if (totalToken1 < debtToken1) {
            _swap(0, true, 0);
        }

        erc20Vault.externalCall(tokens[1], APPROVE_SELECTOR, abi.encode(address(aaveVault), debtToken1)); // approve
        aaveVault.repay(tokens[1], address(erc20Vault), debtToken1);
        erc20Vault.externalCall(tokens[1], APPROVE_SELECTOR, abi.encode(address(aaveVault), 0)); // reset allowance

        uint256[] memory tokenAmounts = new uint256[](2);
        tokenAmounts[0] = balanceToken0;

        aaveVault.pull(address(erc20Vault), tokens, tokenAmounts, "");

        _swap(1, true, 0);
        
    }

    function createStrategy(address erc20Vault_, address uniV3Vault_, address aaveVault_, address admin) external returns (DeltaNeutralStrategy strategy) {
        strategy = DeltaNeutralStrategy(Clones.clone(address(this)));
        strategy.initialize(erc20Vault_, uniV3Vault_, aaveVault_, admin);
    }

    function _contractName() internal pure override returns (bytes32) {
        return bytes32("DeltaNeutralStrategy");
    }

    function _contractVersion() internal pure override returns (bytes32) {
        return bytes32("1.0.0");
    }

    /// @notice Emitted when Strategy strategyParams are set.
    /// @param origin Origin of the transaction (tx.origin)
    /// @param sender Sender of the call (msg.sender)
    /// @param strategyParams Updated strategyParams
    event UpdateStrategyParams(address indexed origin, address indexed sender, StrategyParams strategyParams);

    /// @notice Emitted when Strategy mintingParams are set.
    /// @param origin Origin of the transaction (tx.origin)
    /// @param sender Sender of the call (msg.sender)
    /// @param mintingParams Updated mintingParams
    event UpdateMintingParams(address indexed origin, address indexed sender, MintingParams mintingParams);

    /// @notice Emitted when Strategy oracleParams are set.
    /// @param origin Origin of the transaction (tx.origin)
    /// @param sender Sender of the call (msg.sender)
    /// @param oracleParams Updated oracleParams
    event UpdateOracleParams(address indexed origin, address indexed sender, OracleParams oracleParams);

    event UpdateTradingParams(address indexed origin, address indexed sender, TradingParams tradingParams);

}