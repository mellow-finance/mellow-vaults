// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "@openzeppelin/contracts/utils/Multicall.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";

import "../utils/ContractMeta.sol";
import "../utils/DefaultAccessControlLateInit.sol";
import "../interfaces/vaults/IAaveVault.sol";
import "../interfaces/vaults/IERC20Vault.sol";
import "../interfaces/vaults/IUniV3Vault.sol";
import "../interfaces/external/univ3/ISwapRouter.sol";

import "../libraries/external/TickMath.sol";
import "../libraries/external/FullMath.sol";
import "../libraries/external/OracleLibrary.sol";

contract DeltaNeutralStrategy is ContractMeta, Multicall, DefaultAccessControlLateInit {

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
        uint256 positionTickSize;
        uint256 rebalanceTickDelta;
        uint256 shareToGetBackD;
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
            newStrategyParams.positionTickSize % uint256(uint24(tickSpacing)) == 0 && newStrategyParams.positionTickSize > newStrategyParams.rebalanceTickDelta,
            ExceptionsLibrary.INVARIANT
        );
        require(
            newStrategyParams.shareToGetBackD <= D9, ExceptionsLibrary.INVALID_VALUE
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

        uint256 maxDelta = oracleParams.maxTickDeviation;

        if (spotTick < avgTick && uint256(uint24(avgTick - spotTick)) > maxDelta) {
            return (false, spotTick);
        }

        if (avgTick < spotTick && uint256(uint24(spotTick - avgTick)) > maxDelta) {
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
        for (uint256 i = 0; i < 2; i++) {
            require(uniV3Tokens[i] == aaveTokens[i], ExceptionsLibrary.INVARIANT);
            require(erc20Tokens[i] == aaveTokens[i], ExceptionsLibrary.INVARIANT);
        }

        tokens = erc20Tokens;
        pool = uniV3Vault.pool();
        require(address(pool) != address(0), ExceptionsLibrary.INVALID_TARGET);

        DefaultAccessControlLateInit.init(admin);
    }

    function rebalance() external {
        (bool deltaOkay, int24 spotTick) = isDeltaOkay();
        require(deltaOkay, ExceptionsLibrary.INVARIANT);
        uint256 ticksDelta;
        if (spotTick < lastRebalanceTick) {
            ticksDelta = uint256(uint24(lastRebalanceTick - spotTick));
        }
        else {
            ticksDelta = uint256(uint24(spotTick - lastRebalanceTick));
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

        while (true) {
            uint256 debt = aaveVault.getDebt(1);
            if (debt == 0) {
                break;
            }

            _getCoverage(debt);
            uint256 balance = IERC20(tokens[1]).balanceOf(address(erc20Vault));
            if (balance >= debt) {
                aaveVault.repay(tokens[1], debt);
            }
            else {
                uint256 shareD = FullMath.mulDiv(balance, D9, debt);
                aaveVault.repay(tokens[1], balance);
                uint256 oldBalance = IERC20(aaveVault.aTokens(0)).balanceOf(address(aaveVault));
                uint256 balanceToUse = FullMath.mulDiv(oldBalance, FullMath.mulDiv(shareD, strategyParams.shareToGetBackD, D9), D9);

                uint256[] memory tokenAmounts = new uint256[](2);
                tokenAmounts[0] = balanceToUse;

                aaveVault.pull(address(erc20Vault), tokens, tokenAmounts, "");
            }
        }
    }

    function _openPosition() internal {

        uint160 maxSqrtX96Delta = TickMath.getSqrtRatioAtTick(strategyParams.rebalanceTickDelta);
        uint256 maxX96Delta = FullMath.mulDiv(maxSqrtX96Delta, maxSqrtX96Delta, Q96);

    }

    function _getCoverage(uint256 debt) internal {
        if (IERC20(tokens[1]).balanceOf(address(erc20Vault)) < debt) {
            uint256 amountIn = IERC20(tokens[0]).balanceOf(address(erc20Vault));
            if (amountIn > 0) {
                ISwapRouter.ExactInputSingleParams memory swapParams = ISwapRouter.ExactInputSingleParams({
                    tokenIn: tokens[0],
                    tokenOut: tokens[1],
                    fee: tradingParams.swapFee,
                    recipient: address(erc20Vault),
                    deadline: block.timestamp + 1,
                    amountIn: amountIn,
                    amountOutMinimum: _getSwapAmountOut(amountIn),
                    sqrtPriceLimitX96: 0
                });
                bytes memory data = abi.encode(swapParams);
                erc20Vault.externalCall(tokens[0], APPROVE_SELECTOR, abi.encode(address(router), amountIn)); // approve
                erc20Vault.externalCall(address(router), EXACT_INPUT_SINGLE_SELECTOR, data); // swap
                erc20Vault.externalCall(tokens[0], APPROVE_SELECTOR, abi.encode(address(router), 0)); // reset allowance
            }
        }
    }

    function _getSwapAmountOut(uint256 amount) internal view returns (uint256) {
        (uint160 sqrtPriceX96, , , , , , ) = pool.slot0();
        uint256 priceX96 = FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, Q96);

        if (tokens[0] == pool.token0()) {
            uint256 expectedAmount = FullMath.mulDiv(amount, priceX96, Q96);
            return FullMath.mulDiv(expectedAmount, D9 - tradingParams.maxSlippageD, D9);
        }

        else {

            uint256 expectedAmount = FullMath.mulDiv(amount, Q96, priceX96);
            return FullMath.mulDiv(expectedAmount, D9 - tradingParams.maxSlippageD, D9);

        }
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