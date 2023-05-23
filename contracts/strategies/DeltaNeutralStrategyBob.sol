// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "@openzeppelin/contracts/utils/Multicall.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";

import "../interfaces/utils/ILpCallback.sol";
import "../interfaces/utils/ISwapperHelper.sol";

import "../utils/ContractMeta.sol";
import "../utils/DefaultAccessControlLateInit.sol";
import "../utils/DeltaNeutralStrategyHelper.sol";
import "../interfaces/vaults/IAaveVault.sol";
import "../interfaces/vaults/IERC20Vault.sol";
import "../interfaces/vaults/IUniV3Vault.sol";
import "../interfaces/external/univ3/ISwapRouter.sol";

import "../libraries/external/TickMath.sol";
import "../libraries/external/FullMath.sol";
import "../libraries/external/OracleLibrary.sol";

contract DeltaNeutralStrategyBob is ContractMeta, Multicall, DefaultAccessControlLateInit, ILpCallback {
    using SafeERC20 for IERC20;

    uint256 public constant D4 = 10**4;
    uint256 public constant D9 = 10**9;
    uint256 public constant Q96 = 1 << 96;

    bytes4 public constant APPROVE_SELECTOR = 0x095ea7b3;
    bytes4 public constant EXACT_INPUT_SINGLE_SELECTOR = ISwapRouter.exactInputSingle.selector;

    IERC20Vault public erc20Vault;
    IUniV3Vault public uniV3Vault;
    IAaveVault public aaveVault;

    INonfungiblePositionManager public immutable positionManager;
    ISwapperHelper public immutable swapHelper;
    DeltaNeutralStrategyHelper public immutable helper;

    address[] public tokens;

    int24 public lastRebalanceTick;
    bool public wasRebalance;
    IUniswapV3Pool public pool;

    uint256 public usdIndex;
    uint256 public bobIndex;
    uint256 public stIndex;

    struct StrategyParams {
        int24 positionTickSize;
        int24 rebalanceTickDelta;
        uint256 shiftFromLTVD;
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
            newStrategyParams.positionTickSize % tickSpacing == 0 &&
                newStrategyParams.positionTickSize > newStrategyParams.rebalanceTickDelta &&
                newStrategyParams.rebalanceTickDelta >= 0 &&
                newStrategyParams.rebalanceTickDelta <= 5000 &&
                newStrategyParams.shiftFromLTVD <= D9,
            ExceptionsLibrary.INVARIANT
        );
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
        require((fee == 100 || fee == 500 || fee == 3000 || fee == 10000) && newTradingParams.maxSlippageD <= D9);
        tradingParams = newTradingParams;
        emit UpdateTradingParams(tx.origin, msg.sender, tradingParams);
    }

    function isDeltaOkay() public view returns (bool, int24) {
        (, int24 spotTick, , , , , ) = pool.slot0();
        (int24 avgTick, , bool withFail) = OracleLibrary.consult(address(pool), oracleParams.averagePriceTimeSpan);
        require(!withFail);

        int24 maxDelta = int24(oracleParams.maxTickDeviation);
        if (spotTick < avgTick && avgTick - spotTick > maxDelta) {
            return (false, spotTick);
        }

        if (avgTick < spotTick && spotTick - avgTick > maxDelta) {
            return (false, spotTick);
        }

        return (true, spotTick);
    }

    constructor(
        INonfungiblePositionManager positionManager_,
        ISwapperHelper swapHelper_,
        DeltaNeutralStrategyHelper helper_
    ) {
        require(
            address(positionManager_) != address(0) &&
                address(swapHelper_) != address(0) &&
                address(helper_) != address(0)
        );
        positionManager = positionManager_;
        swapHelper = swapHelper_;
        helper = helper_;
        DefaultAccessControlLateInit.init(address(this));
    }

    function initialize(
        address erc20Vault_,
        address uniV3Vault_,
        address aaveVault_,
        address admin,
        uint256 usdIndex_,
        uint256 bobIndex_,
        uint256 tokenIndex_
    ) external {
        erc20Vault = IERC20Vault(erc20Vault_);
        uniV3Vault = IUniV3Vault(uniV3Vault_);
        aaveVault = IAaveVault(aaveVault_);

        helper.setParams(erc20Vault, uniV3Vault, aaveVault, positionManager);

        tokens = uniV3Vault.vaultTokens();
        pool = uniV3Vault.pool();

        require(address(pool) != address(0), ExceptionsLibrary.INVALID_TARGET);
        require(usdIndex_ != bobIndex_ && bobIndex_ != tokenIndex_ && usdIndex_ != tokenIndex_, ExceptionsLibrary.INVARIANT);
        require(usdIndex_ <= 2 && bobIndex_ <= 2 && tokenIndex_ <= 2, ExceptionsLibrary.LIMIT_UNDERFLOW);

        usdIndex = usdIndex_;
        stIndex = tokenIndex_;
        bobIndex = bobIndex_;

        DefaultAccessControlLateInit.init(admin);
    }

    function rebalance() external {
        (bool deltaOkay, int24 spotTick) = isDeltaOkay();
        require(deltaOkay, ExceptionsLibrary.INVARIANT);
        int24 ticksDelta;
        if (spotTick < lastRebalanceTick) {
            ticksDelta = lastRebalanceTick - spotTick;
        } else {
            ticksDelta = spotTick - lastRebalanceTick;
        }
        require(!wasRebalance || ticksDelta >= strategyParams.rebalanceTickDelta);
        _closePosition();
        _openPosition();

        wasRebalance = true;
        lastRebalanceTick = spotTick;
    }

    function _closePosition() internal {
        uint256 uniV3Nft = uniV3Vault.uniV3Nft();
        if (uniV3Nft != 0) {
            uint256[] memory uniV3TokenAmounts = uniV3Vault.liquidityToTokenAmounts(type(uint128).max);
            uniV3Vault.pull(address(erc20Vault), tokens, uniV3TokenAmounts, "");
        }

        uint256 debt = aaveVault.getDebt(tokens[stIndex]);
        if (debt == 0) {
            return;
        }

        _getCoverage(debt);
        erc20Vault.externalCall(tokens[stIndex], APPROVE_SELECTOR, abi.encode(address(aaveVault), debt)); // approve
        aaveVault.repay(tokens[stIndex], address(erc20Vault), debt);
        erc20Vault.externalCall(tokens[stIndex], APPROVE_SELECTOR, abi.encode(address(aaveVault), 0)); // reset allowance
    }

    function _openPosition() internal {
        uint160 maxSqrtX96Delta = TickMath.getSqrtRatioAtTick(strategyParams.rebalanceTickDelta);
        uint256 maxX96Delta = FullMath.mulDiv(maxSqrtX96Delta, maxSqrtX96Delta, Q96);

        uint256 ltvQ96 = FullMath.mulDiv(
            FullMath.mulDiv(aaveVault.getLTV(tokens[usdIndex]), Q96, D4),
            strategyParams.shiftFromLTVD,
            D9
        );

        uint256 shareD = FullMath.mulDiv(ltvQ96, D9, ltvQ96 + maxX96Delta);
        _swap(stIndex, true, usdIndex);

        uint256 balance = IERC20(tokens[usdIndex]).balanceOf(address(erc20Vault));
        uint256 toAave = FullMath.mulDiv(balance, D9 - shareD, D9);

        uint256[] memory amounts = new uint256[](tokens.length);
        amounts[usdIndex] = toAave;

        erc20Vault.pull(address(aaveVault), tokens, amounts, "");
        uint256 amountToTake = getSwapAmountOut(balance - toAave, usdIndex, false);

        aaveVault.borrow(tokens[stIndex], address(erc20Vault), amountToTake);
        (, int24 spotTick, , , , , ) = pool.slot0();
        int24 lowerTick = spotTick - strategyParams.positionTickSize / 2;
        lowerTick -= lowerTick % pool.tickSpacing();
        int24 upperTick = lowerTick + strategyParams.positionTickSize;

        uint256 fromNft = uniV3Vault.uniV3Nft();
        uint256 nft = _mintNewNft(lowerTick, upperTick, block.timestamp + 1);

        positionManager.safeTransferFrom(address(this), address(uniV3Vault), nft);
        if (fromNft != 0) {
            positionManager.burn(fromNft);
        }

        uint256[] memory tokenAmounts = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; ++i) {
            tokenAmounts[i] = IERC20(tokens[i]).balanceOf(address(erc20Vault));
        }

        erc20Vault.pull(address(uniV3Vault), tokens, tokenAmounts, "");
    }

    function _mintNewNft(
        int24 lowerTick,
        int24 upperTick,
        uint256 deadline
    ) internal returns (uint256 newNft) {
        uint256 minTokenUsdForOpening = mintingParams.minTokenUsdForOpening;
        uint256 minTokenStForOpening = mintingParams.minTokenStForOpening;

        IERC20(tokens[stIndex]).safeApprove(address(positionManager), minTokenStForOpening);
        IERC20(tokens[usdIndex]).safeApprove(address(positionManager), minTokenUsdForOpening);
        (newNft, , , ) = positionManager.mint(
            INonfungiblePositionManager.MintParams({
                token0: tokens[usdIndex],
                token1: tokens[stIndex],
                fee: pool.fee(),
                tickLower: lowerTick,
                tickUpper: upperTick,
                amount0Desired: minTokenUsdForOpening,
                amount1Desired: minTokenStForOpening,
                amount0Min: 0,
                amount1Min: 0,
                recipient: address(this),
                deadline: deadline
            })
        );

        IERC20(tokens[stIndex]).safeApprove(address(positionManager), 0);
        IERC20(tokens[usdIndex]).safeApprove(address(positionManager), 0);
    }

    function _getCoverage(uint256 debt) internal {
        if (IERC20(tokens[stIndex]).balanceOf(address(erc20Vault)) < debt) {
            _swap(usdIndex, stIndex, true, 0);
        }
    }

    function _swap(
        uint256 indexA,
        uint256 indexB
        bool swapAll,
        uint256 amount
    ) internal {
        uint256 amountIn = amount;
        if (swapAll) {
            amountIn = IERC20(tokens[indexA]).balanceOf(address(erc20Vault));
        }
        if (amountIn > 0) {
            IERC20(tokens[index]).safeTransfer(address(swapHelper), amountIn);
            swapHelper.swap(tokens[indexA], tokens[indexB], amountIn, getSwapAmountOut(amountIn, indexA, true));
        }
    }

    function getSwapAmountOut(
        uint256 amount,
        uint256 index,
        bool takeSlippage
    ) public view returns (uint256) {
        (uint160 sqrtPriceX96, , , , , , ) = pool.slot0();
        uint256 priceX96 = FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, Q96);

        uint256 slippage = 0;
        if (takeSlippage) {
            slippage = tradingParams.maxSlippageD;
        }

        if (tokens[index] == pool.token0() && index == 0) {
            uint256 expectedAmount = FullMath.mulDiv(amount, priceX96, Q96);
            return FullMath.mulDiv(expectedAmount, D9 - slippage, D9);
        } else {
            uint256 expectedAmount = FullMath.mulDiv(amount, Q96, priceX96);
            return FullMath.mulDiv(expectedAmount, D9 - slippage, D9);
        }
    }

    function _checkCallbackPossible() internal view {
        (bool deltaOkay, int24 spotTick) = isDeltaOkay();
        require(deltaOkay, ExceptionsLibrary.INVARIANT);
        int24 ticksDelta;
        if (spotTick < lastRebalanceTick) {
            ticksDelta = lastRebalanceTick - spotTick;
        } else {
            ticksDelta = spotTick - lastRebalanceTick;
        }
        if (wasRebalance) {
            require(ticksDelta < strategyParams.rebalanceTickDelta, ExceptionsLibrary.INVALID_STATE);
        }
    }

    function _rebalanceERC20Vault() internal {
        (uint256 token0OnERC20, uint256 wantToHaveOnERC20) = helper.calcERC20Params();

        if (wantToHaveOnERC20 < token0OnERC20) {
            uint256 delta = token0OnERC20 - wantToHaveOnERC20;
            _swap(0, false, delta);
        } else {
            uint256 delta = wantToHaveOnERC20 - token0OnERC20;
            uint256 toSwap = getSwapAmountOut(delta, usdIndex, false);
            _swap(stIndex, false, toSwap);
        }
    }

    /// @inheritdoc ILpCallback
    function depositCallback(bytes memory depositOptions) external {
        _checkCallbackPossible();

        (uint256 shareOfCapitalQ96, uint256 debtToken1, uint256[] memory tokenAmounts) = helper.calcDepositParams(
            depositOptions
        );

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

        (, uint256 totalToken1, uint256 balanceToken0, uint256 debtToken1) = helper.calcWithdrawParams(depositOptions);

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

    function createStrategy(
        address erc20Vault_,
        address uniV3Vault_,
        address aaveVault_,
        address admin
    ) external returns (DeltaNeutralStrategy strategy) {
        strategy = DeltaNeutralStrategy(Clones.clone(address(this)));
        strategy.initialize(erc20Vault_, uniV3Vault_, aaveVault_, admin);
    }

    function pullFromUniswap(uint256[] memory tokenAmounts) external returns (uint256[] memory pulledAmounts) {
        require(msg.sender == address(helper), ExceptionsLibrary.FORBIDDEN);
        pulledAmounts = uniV3Vault.pull(address(erc20Vault), tokens, tokenAmounts, "");
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
