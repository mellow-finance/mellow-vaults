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
import "../libraries/ExceptionsLibrary.sol";
import "../libraries/CommonLibrary.sol";
import "../libraries/external/FullMath.sol";
import "../libraries/external/TickMath.sol";
import "../libraries/external/OracleLibrary.sol";
import "../utils/DefaultAccessControl.sol";
import "../utils/ContractMeta.sol";

contract SStrategy is DefaultAccessControl, ContractMeta {
    using SafeERC20 for IERC20;

    // IMMUTABLES
    uint256 public constant D9 = 10**9;
    uint256 public constant D18 = 10**18;
    bytes4 public constant APPROVE_SELECTOR = 0x095ea7b3;
    bytes4 public constant TRANSFER_FROM_SELECTOR = 0x095ea7b3;
    bytes4 public constant EXACT_INPUT_SINGLE_SELECTOR = ISwapRouter.exactInputSingle.selector;
    uint256 public constant OVERCOLLATERIZATION_D9 = 15e8;

    address public mainToken;
    address public sellToken;
    address public wPowerPerp;
    IERC20Vault public erc20Vault;
    ISqueethVault public squeethVault;
    ISwapRouter public swapRouter;
    IUniswapV3Pool public sellPool;
    IUniswapV3Pool public squeethPool;

    // INTERNAL STATE
    uint256 startingTime;
    uint256 startingPrice;
    uint256 lastStrikeD9;
    uint256 lastAmountD9;

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
        uint256 cycleDuration;
    }

    struct OracleParams {
        uint24 maxTickDeviation;
        uint256 slippageD9;
        uint32 oracleObservationDelta;
    }

    StrategyParams strategyParams;
    LiquidationParams liquidationParams;
    OracleParams oracleParams;


    /// @notice Constructor for a new contract
    constructor(
        IERC20Vault erc20Vault_,
        ISqueethVault squeethVault_,
        address mainToken_,
        address sellToken_,
        ISwapRouter swapRouter_,
        IUniswapV3Pool sellPool_,
        IUniswapV3Pool squeethPool_,
        address admin_
    ) DefaultAccessControl(admin_) {
        address[] memory erc20Tokens = erc20Vault_.vaultTokens();
        address[] memory squeethTokens = squeethVault_.vaultTokens();
        require(erc20Tokens.length == 1, ExceptionsLibrary.INVALID_LENGTH);
        require(squeethTokens.length == 1, ExceptionsLibrary.INVALID_LENGTH);
        require(erc20Tokens[0] == mainToken_, ExceptionsLibrary.INVALID_TOKEN);
        require(squeethTokens[0] == mainToken_, ExceptionsLibrary.INVALID_TOKEN);
        require(squeethVault_.weth() == mainToken_, ExceptionsLibrary.INVALID_TOKEN);
        require(sellPool_.token0() == mainToken_ || sellPool_.token1() == mainToken_);
        require(sellPool_.token1() == sellToken_ || sellPool_.token1() == sellToken_);
        require(address(squeethPool_) == squeethVault_.wPowerPerpPool(), ExceptionsLibrary.INVALID_VALUE);
        mainToken = mainToken_;
        sellToken = sellToken_;
        swapRouter = swapRouter_;
        wPowerPerp = squeethVault_.wPowerPerp();
        sellPool = sellPool_;
        squeethPool = squeethPool_;
    }

    // -------------------  EXTERNAL, VIEW  -------------------


    // -------------------  EXTERNAL, MUTATING  -------------------

    function startCycleMocked(uint256 strikeUSD, uint256 price, address safe)
        external
        returns (
            int256[] memory poolAmounts,
            uint256[] memory tokenAmounts,
            bool zeroToOne
        )
    {
        _requireAtLeastOperator(); 
        require(startingTime == 0, ExceptionsLibrary.INVARIANT);

        address sellToken_ = sellToken;
        address mainToken_ = mainToken;
        
        uint256 amountD9;
        {
            uint256 currentPrice = squeethVault.twapIndexPrice();
            uint256 strikeD9 = FullMath.mulDiv(strikeUSD, D9, currentPrice);
            startingPrice = currentPrice;
            lastStrikeD9 = strikeD9;

            if (mainToken_ == sellToken_) {
                //eth case
                amountD9 = FullMath.mulDiv(strategyParams.upperHedgingThresholdD9 - D9, strategyParams.upperHedgingThresholdD9 - strikeD9, OVERCOLLATERIZATION_D9);
            } else {
                //usdc case
                uint256 squared = FullMath.mulDiv(strategyParams.lowerHedgingThresholdD9, strategyParams.lowerHedgingThresholdD9, D9);
                uint256 temp = FullMath.mulDiv(1 - squared, D9, FullMath.mulDiv(OVERCOLLATERIZATION_D9, strategyParams.upperHedgingThresholdD9, D9));  
                amountD9 = FullMath.mulDiv(D9 - strategyParams.lowerHedgingThresholdD9 - temp, D9, strikeD9 - strategyParams.lowerHedgingThresholdD9);
            }
        }
        {
            uint256 totalMoney = IERC20(mainToken).balanceOf(address(erc20Vault));
            uint256 shortMoney = FullMath.mulDiv(totalMoney, D9, D9 + FullMath.mulDiv(amountD9, price, D18));
            
            uint256[] memory amounts = new uint256[](1);
            amounts[0] = shortMoney;
            address[] memory tokens = new address[](1);
            tokens[0] = mainToken_;
            erc20Vault.pull(address(squeethVault), tokens, amounts, "");
            squeethVault.takeShort(strategyParams.upperHedgingThresholdD9);

            erc20Vault.externalCall(mainToken, TRANSFER_FROM_SELECTOR, abi.encode(erc20Vault, safe, totalMoney - shortMoney));
        }
        //sell wPowerPerp from sqVault for sellToken at erc20vault
        SwapParams memory params = SwapParams({
                tokenIn: wPowerPerp,
                tokenOut: sellToken_,
                pool: squeethPool,
                spender: squeethVault,
                recipient: address(erc20Vault)
            });
        _swapToToken(params);

        //save amount and strike
        startingTime = block.timestamp;
        lastAmountD9 = amountD9;
    }


    function endCycleMocked(address safe)
        external
        returns (
            int256[] memory poolAmounts,
            uint256[] memory tokenAmounts,
            bool zeroToOne
        )
    {
        _requireAtLeastOperator();
        require(startingTime != 0, ExceptionsLibrary.INVARIANT);
        uint256 currentPrice = squeethVault.twapIndexPrice();
        uint256 priceChangeD9 = FullMath.mulDiv(currentPrice, D9, startingPrice);
        if (block.timestamp - startingTime >= strategyParams.cycleDuration) {
            require(priceChangeD9 < liquidationParams.lowerLiquidationThresholdD9 || priceChangeD9 > liquidationParams.upperLiquidationThresholdD9, ExceptionsLibrary.TIMESTAMP);
        }
        squeethVault.closeShort();
        address mainToken_ = mainToken;
        address sellToken_ = sellToken;
        uint256 squeethMoney = IERC20(mainToken_).balanceOf(address(squeethVault));
        {
            uint256[] memory amounts = new uint256[](1);
            amounts[0] = squeethMoney;
            address[] memory tokens = new address[](1);
            tokens[0] = mainToken_;
            squeethVault.pull(address(erc20Vault), tokens, amounts, "");
        }
        int256 changeFromStrikeD9 = int256(FullMath.mulDiv(lastStrikeD9, D9, priceChangeD9)) - int256(D9);
        if (sellToken_ != mainToken_) {
            changeFromStrikeD9 *= -1;
        }
        if (changeFromStrikeD9 > 0) {
            uint256 optionProfit = FullMath.mulDiv(uint256(changeFromStrikeD9), lastAmountD9, D9); 
            erc20Vault.externalCall(mainToken_, TRANSFER_FROM_SELECTOR, abi.encode(safe, erc20Vault, optionProfit));
        }
        
        //convert everything to ETH
        if (sellToken_ != mainToken_) {
            SwapParams memory params = SwapParams({
                tokenIn: sellToken_,
                tokenOut: mainToken_,
                pool: sellPool,
                spender: erc20Vault,
                recipient: address(erc20Vault)
            });
            _swapToToken(params);
        }

        startingTime = 0;
    }


    /// @notice Set new Oracle params
    /// @param params Params to set
    function setOracleParams(OracleParams memory params) external {
        _requireAdmin();

        oracleParams = params;
        emit SetOracleParams(tx.origin, msg.sender, params);
    }

    // -------------------  INTERNAL, VIEW  -------------------

    function _getPriceAfterTickChecked(IUniswapV3Pool pool_) internal view returns (uint160 sqrtPriceX96) {
        uint32 oracleObservationDelta = oracleParams.oracleObservationDelta;
        (uint160 sqrtPriceX96, int24 tick, , , , , ) = pool_.slot0();
        (int24 averageTick, , bool withFail) = OracleLibrary.consult(address(pool_), oracleObservationDelta);
        // Fails when we dont have observations, so return spot tick as this was the last trade price
        if (withFail) {
            averageTick = tick;
        }
        int24 tickDeviation = tick - averageTick;
        uint24 absoluteTickDeviation = (tickDeviation > 0) ? uint24(tickDeviation) : uint24(-tickDeviation);
        require(absoluteTickDeviation > oracleParams.maxTickDeviation, ExceptionsLibrary.INVARIANT);
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
    event SetOracleParams(address indexed origin, address indexed sender, OracleParams params);
}
