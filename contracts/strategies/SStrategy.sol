// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.9;

import "@openzeppelin/contracts/utils/Multicall.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import "../interfaces/external/univ3/INonfungiblePositionManager.sol";
import "../interfaces/external/univ3/IUniswapV3Pool.sol";
import "../interfaces/external/univ3/IUniswapV3Factory.sol";
import "../interfaces/external/univ3/ISwapRouter.sol";
import "../interfaces/vaults/IERC20Vault.sol";
import "../interfaces/vaults/ISqueethVault.sol";
import "../interfaces/vaults/IRequestableRootVault.sol";
import "../libraries/ExceptionsLibrary.sol";
import "../libraries/CommonLibrary.sol";
import "../libraries/external/FullMath.sol";
import "../libraries/external/TickMath.sol";
import "../libraries/external/OracleLibrary.sol";
import "../utils/DefaultAccessControl.sol";
import "../utils/ContractMeta.sol";
import "hardhat/console.sol";

contract SStrategy is ContractMeta, DefaultAccessControl {
    using SafeERC20 for IERC20;

    // IMMUTABLES
    uint256 public constant D9 = 1e9;
    uint256 public constant D18 = 1e18;
    bytes4 public constant APPROVE_SELECTOR = IERC20.approve.selector;
    bytes4 public constant TRANSFER_FROM_SELECTOR = IERC20.transferFrom.selector;
    bytes4 public constant TRANSFER_SELECTOR = IERC20.transfer.selector;
    bytes4 public constant EXACT_INPUT_SINGLE_SELECTOR = ISwapRouter.exactInputSingle.selector;

    address public mainToken;
    address public wPowerPerp;
    IRequestableRootVault rootVault;
    IERC20Vault public erc20Vault;
    ISqueethVault public squeethVault;
    ISwapRouter public swapRouter;
    IUniswapV3Pool public squeethPool;

    // INTERNAL STATE
    uint256 public startingTime;
    uint256 public startingPrice;
    uint256 public startingOptionStrikeD9;
    uint256 public startingOptionPriceETH;
    uint256 public startingOptionMoney;

    // MUTABLE PARAMS
    struct SwapParams {
        address tokenIn;
        address tokenOut;
        IUniswapV3Pool pool;
        IIntegrationVault spender;
        address recipient;
    }

    struct StrategyParams {
        uint256 lowerHedgingThresholdD9;
        uint256 upperHedgingThresholdD9;
        uint256 cycleDuration;
    }

    struct LiquidationParams {
        uint256 lowerLiquidationThresholdD9;
        uint256 upperLiquidationThresholdD9;
    }

    struct OracleParams {
        uint24 maxTickDeviation;
        uint256 slippageD9;
        uint32 oracleObservationDelta;
    }

    StrategyParams public strategyParams;
    LiquidationParams public liquidationParams;
    OracleParams public oracleParams;


    /// @notice Constructor for a new contract
    constructor(
        address mainToken_,
        IERC20Vault erc20Vault_,
        ISqueethVault squeethVault_,
        ISwapRouter swapRouter_,
        address admin_
    ) DefaultAccessControl(admin_) {
        address[] memory erc20Tokens = erc20Vault_.vaultTokens();
        address[] memory squeethTokens = squeethVault_.vaultTokens();
        require(erc20Tokens.length == 1, ExceptionsLibrary.INVALID_LENGTH);
        require(squeethTokens.length == 1, ExceptionsLibrary.INVALID_LENGTH);
        require(erc20Tokens[0] == mainToken_, ExceptionsLibrary.INVALID_TOKEN);
        require(squeethTokens[0] == mainToken_, ExceptionsLibrary.INVALID_TOKEN);
        require(squeethVault_.weth() == mainToken_, ExceptionsLibrary.INVALID_TOKEN);
        mainToken = mainToken_;
        erc20Vault = erc20Vault_;
        squeethVault = squeethVault_;
        swapRouter = swapRouter_;
        wPowerPerp = squeethVault_.wPowerPerp();
        squeethPool = IUniswapV3Pool(squeethVault_.wPowerPerpPool());
    }

    // -------------------  EXTERNAL, VIEW  -------------------


    // -------------------  EXTERNAL, MUTATING  -------------------

    function startCycleMocked(uint256 strike, uint256 optionPriceUSD, address safe)
        external
    {
        _requireAtLeastOperator(); 
        require(startingTime == 0, ExceptionsLibrary.INVARIANT);
        
        uint256 currentPrice = squeethVault.twapIndexPrice();
        uint256 strikeD9 = FullMath.mulDiv(strike, D9, currentPrice);
        uint256 amountD9 = FullMath.mulDiv(strategyParams.upperHedgingThresholdD9 - D9, strategyParams.upperHedgingThresholdD9 - strikeD9, D9);
        {
            address mainToken_ = mainToken;
            uint256 totalMoney = IERC20(mainToken_).balanceOf(address(squeethVault));
            uint256 optionPriceETH = FullMath.mulDiv(optionPriceUSD, D18, currentPrice);
            uint256 shortMoney = FullMath.mulDiv(totalMoney, D9, D9 + FullMath.mulDiv(amountD9, optionPriceETH, D18));

            console.log("to squeeth:");
            console.log(shortMoney);
            console.log("to option:");
            console.log(totalMoney - shortMoney);

            squeethVault.externalCall(mainToken_, TRANSFER_SELECTOR, abi.encode(safe, totalMoney - shortMoney));
            squeethVault.takeShort(strategyParams.upperHedgingThresholdD9, true);

            startingOptionPriceETH = optionPriceETH;
            startingOptionMoney = totalMoney - shortMoney;  
        }

        //save amount and strike
        startingTime = block.timestamp;
        startingPrice = currentPrice;
        startingOptionStrikeD9 = strikeD9;
    }


    function endCycleMocked(address safe)
        external
    {
        _requireAtLeastOperator();
        require(startingTime != 0, ExceptionsLibrary.INVARIANT);

        uint256 currentPrice = squeethVault.twapIndexPrice();
        uint256 priceChangeD9 = FullMath.mulDiv(currentPrice, D9, startingPrice);
        if (priceChangeD9 < liquidationParams.lowerLiquidationThresholdD9 || priceChangeD9 > liquidationParams.upperLiquidationThresholdD9) {
            rootVault.shutdown();
        } else {
            require(block.timestamp - startingTime >= strategyParams.cycleDuration, ExceptionsLibrary.INVARIANT);
        }
        squeethVault.closeShort();

        address mainToken_ = mainToken;
        int256 singleOptionProfitETH =  int256(D18) - int256(FullMath.mulDiv(startingOptionStrikeD9, D18, priceChangeD9));
        
        console.log("change");
        console.logInt(singleOptionProfitETH);

        if (singleOptionProfitETH > 0) {
            uint256 optionProfit = FullMath.mulDiv(startingOptionMoney, uint256(singleOptionProfitETH), startingOptionPriceETH);
            console.log("profit");
            console.log(optionProfit);
            require(IERC20(mainToken).allowance(safe, address(squeethVault)) >= optionProfit, ExceptionsLibrary.LIMIT_UNDERFLOW);
            squeethVault.externalCall(mainToken_, TRANSFER_FROM_SELECTOR, abi.encode(safe, squeethVault, optionProfit));
        }
        rootVault.invokeExecution();

        startingTime = 0;
    }

    function setRootVault(IRequestableRootVault rootVault_) external {
        _requireAdmin();
        require(address(rootVault) == address(0), ExceptionsLibrary.INIT);
        address[] memory rootTokens = rootVault_.vaultTokens();
        require(rootVault_.requestableVault() == squeethVault);
        require(rootVault_.erc20Vault() == erc20Vault);
        require(rootTokens.length == 1, ExceptionsLibrary.INVALID_LENGTH);
        require(rootTokens[0] == mainToken, ExceptionsLibrary.INVALID_TOKEN);
        rootVault = rootVault_;
        rootVault_.setWithdrawDelay(strategyParams.cycleDuration);
    }

    /// @notice Sets new oracle params
    /// @param newOracleParams New oracle parameters to set
    function updateOracleParams(OracleParams calldata newOracleParams) external {
        _requireAdmin();
        require(
            (newOracleParams.slippageD9 <= D9) &&
                (newOracleParams.oracleObservationDelta > 0),
            ExceptionsLibrary.INVARIANT
        );
        oracleParams = newOracleParams;
        emit OracleParamsUpdated(tx.origin, msg.sender, newOracleParams);
    }


    /// @notice Sets new liqudation params
    /// @param newLiquidationParams New oracle parameters to set
    function updateLiquidationParams(LiquidationParams calldata newLiquidationParams) external {
        _requireAdmin();
        require(
            (newLiquidationParams.lowerLiquidationThresholdD9 < D9) &&
                (newLiquidationParams.upperLiquidationThresholdD9 > D9),
            ExceptionsLibrary.INVARIANT
        );
        liquidationParams = newLiquidationParams;
        emit LiquidationParamsUpdated(tx.origin, msg.sender, newLiquidationParams);
    }

    /// @notice Sets new oracle params
    /// @param newStrategyParams New oracle parameters to set
    function updateStrategyParams(StrategyParams calldata newStrategyParams) external {
        _requireAdmin();
        require(
            (newStrategyParams.lowerHedgingThresholdD9 < D9) &&
                (newStrategyParams.upperHedgingThresholdD9 > D9) &&
                (newStrategyParams.cycleDuration > 0),
            ExceptionsLibrary.INVARIANT
        );
        strategyParams = newStrategyParams;
        rootVault.setWithdrawDelay(newStrategyParams.cycleDuration);
        emit StrategyParamsUpdated(tx.origin, msg.sender, newStrategyParams);
    }

    // -------------------  INTERNAL, VIEW  -------------------

    function _getPriceAfterTickChecked(IUniswapV3Pool pool_) internal view returns (uint160) {
        uint32 oracleObservationDelta = oracleParams.oracleObservationDelta;
        (uint160 sqrtPriceX96, int24 tick, , , , , ) = pool_.slot0();
        (int24 averageTick, , bool withFail) = OracleLibrary.consult(address(pool_), oracleObservationDelta);
        // Fails when we dont have observations, so return spot tick as this was the last trade price
        if (withFail) {
            averageTick = tick;
        }
        int24 tickDeviation = tick - averageTick;
        uint24 absoluteTickDeviation = (tickDeviation > 0) ? uint24(tickDeviation) : uint24(-tickDeviation);
        require(absoluteTickDeviation <= oracleParams.maxTickDeviation, ExceptionsLibrary.INVARIANT);
        return sqrtPriceX96;
    }

    function _contractName() internal pure override returns (bytes32) {
        return bytes32("SStrategy");
    }

    function _contractVersion() internal pure override returns (bytes32) {
        return bytes32("1.0.0");
    }

    // -------------------  INTERNAL, MUTATING  -------------------

    function _swapToToken(SwapParams memory params) internal returns (uint256 amountIn, uint256 amountOut) {
        amountIn = IERC20(params.tokenIn).balanceOf(address(params.spender));
        uint256 sqrtPriceX96 = uint256(_getPriceAfterTickChecked(params.pool));
        uint256 priceX96 = FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, CommonLibrary.Q96);
        if (params.tokenIn == params.pool.token1()) { 
            priceX96 = FullMath.mulDiv(CommonLibrary.Q96, CommonLibrary.Q96, priceX96);
        }

        uint256 amountOutMinimum = FullMath.mulDiv(amountIn, priceX96, CommonLibrary.Q96);
        amountOutMinimum = FullMath.mulDiv(amountOutMinimum, D9 - oracleParams.slippageD9, D9); //!
        ISwapRouter.ExactInputSingleParams memory uniswapParams = ISwapRouter.ExactInputSingleParams({
            tokenIn: params.tokenIn,
            tokenOut: params.tokenOut,
            fee: params.pool.fee(),
            recipient: params.recipient,
            deadline: block.timestamp + 1,
            amountIn: amountIn,
            amountOutMinimum: amountOutMinimum,
            sqrtPriceLimitX96: 0
        });
        ISwapRouter swapRouter_ = swapRouter;
        bytes memory data = abi.encode(uniswapParams);
        params.spender.externalCall(params.tokenIn, APPROVE_SELECTOR, abi.encode(address(swapRouter_), amountIn)); // approve
        bytes memory routerResult = erc20Vault.externalCall(address(swapRouter_), EXACT_INPUT_SINGLE_SELECTOR, data); //swap
        params.spender.externalCall(params.tokenIn, APPROVE_SELECTOR, abi.encode(address(swapRouter_), 0)); // reset allowance
        amountOut = abi.decode(routerResult, (uint256));
    }

    /// @notice Emitted when Oracle params are set.
    /// @param origin Origin of the transaction (tx.origin)
    /// @param sender Sender of the call (msg.sender)
    /// @param params Updated params
    event OracleParamsUpdated(address indexed origin, address indexed sender, OracleParams params);

    /// @notice Emitted when Oracle params are set.
    /// @param origin Origin of the transaction (tx.origin)
    /// @param sender Sender of the call (msg.sender)
    /// @param params Updated params
    event LiquidationParamsUpdated(address indexed origin, address indexed sender, LiquidationParams params);

    /// @notice Emitted when Oracle params are set.
    /// @param origin Origin of the transaction (tx.origin)
    /// @param sender Sender of the call (msg.sender)
    /// @param params Updated params
    event StrategyParamsUpdated(address indexed origin, address indexed sender, StrategyParams params);
}
