// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import "../interfaces/external/univ3/INonfungiblePositionManager.sol";
import "../interfaces/external/univ3/IUniswapV3Pool.sol";
import "../interfaces/external/univ3/IUniswapV3Factory.sol";
import "../interfaces/external/univ3/ISwapRouter.sol";
import "../interfaces/vaults/IERC20Vault.sol";
import "../interfaces/vaults/IUniV3Vault.sol";
import "../interfaces/vaults/IAaveVault.sol";
import "../libraries/ExceptionsLibrary.sol";
import "../libraries/CommonLibrary.sol";
import "../libraries/external/FullMath.sol";
import "../libraries/external/TickMath.sol";
import "../libraries/external/OracleLibrary.sol";
import "../libraries/external/LiquidityAmounts.sol";
import "../utils/DefaultAccessControlLateInit.sol";
import "../utils/ContractMeta.sol";

contract HStrategy is ContractMeta, DefaultAccessControlLateInit {
    using SafeERC20 for IERC20;

    struct OtherParams {
        uint256 minToken0ForOpening;
        uint256 minToken1ForOpening;
    }

    struct StrategyParams {
        int24 burnDeltaTicks;
        int24 mintDeltaTicks;
        int24 biDeltaTicks;
        int24 widthCoefficient;
        int24 widthTicks;
        uint32 oracleObservationDelta;
        uint32 slippage;
        uint32 erc20MoneyRatioD;
    }

    struct InternalRatioParams {
        uint256 token0MoneyRatio;
        uint256 token1MoneyRatio;
        uint256 uniswapPoolRatio;
    }

    IERC20Vault public erc20Vault;
    IIntegrationVault public moneyVault;
    IUniV3Vault public uniV3Vault;
    address[] public tokens;

    INonfungiblePositionManager public positionManager;
    IUniswapV3Pool public pool;

    bytes4 public constant APPROVE_SELECTOR = IERC20.approve.selector; // 0x095ea7b3; more consistent?
    bytes4 public constant EXACT_INPUT_SINGLE_SELECTOR = ISwapRouter.exactInputSingle.selector;
    ISwapRouter public router;

    int24 public lastMintRebalanceTick;
    uint256 public constant DENOMINATOR = 10**9;

    OtherParams public otherParams;
    StrategyParams public strategyParams;

    constructor(INonfungiblePositionManager positionManager_, ISwapRouter router_) {
        require(address(positionManager_) != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        require(address(router_) != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        positionManager = positionManager_;
        DefaultAccessControlLateInit.init(address(this));
        router = router_;
    }

    function initialize(
        INonfungiblePositionManager positionManager_,
        address[] memory tokens_,
        IERC20Vault erc20Vault_,
        IIntegrationVault moneyVault_,
        IUniV3Vault uniV3Vault_,
        uint24 fee_,
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
        for (uint256 i = 0; i < 2; i++) {
            require(erc20Tokens[i] == tokens_[i], ExceptionsLibrary.INVARIANT);
            require(moneyTokens[i] == tokens_[i], ExceptionsLibrary.INVARIANT);
            require(uniV3Tokens[i] == tokens_[i], ExceptionsLibrary.INVARIANT);
        }
        positionManager = positionManager_;
        erc20Vault = erc20Vault_;
        moneyVault = moneyVault_;
        uniV3Vault = uniV3Vault_;
        tokens = tokens_;
        IUniswapV3Factory factory = IUniswapV3Factory(positionManager_.factory());
        pool = IUniswapV3Pool(factory.getPool(tokens[0], tokens[1], fee_));
        require(address(pool) != address(0), ExceptionsLibrary.ADDRESS_ZERO);
    }

    function createStrategy(
        address[] memory tokens_,
        IERC20Vault erc20Vault_,
        IIntegrationVault moneyVault_,
        IUniV3Vault uniV3Vault_,
        uint24 fee_,
        address admin_
    ) external returns (HStrategy strategy) {
        strategy = HStrategy(Clones.clone(address(this)));
        strategy.initialize(positionManager, tokens_, erc20Vault_, moneyVault_, uniV3Vault_, fee_, admin_);
    }

    function updateOtherParams(OtherParams calldata newOtherParams) external {
        _requireAdmin();
        require(
            (newOtherParams.minToken0ForOpening > 0 && newOtherParams.minToken1ForOpening > 0),
            ExceptionsLibrary.INVARIANT
        );
        otherParams = newOtherParams;
        emit UpdateOtherParams(tx.origin, msg.sender, newOtherParams);
    }

    function updateStrategyParams(StrategyParams calldata newStrategyParams) external {
        _requireAdmin();
        require(
            (newStrategyParams.biDeltaTicks > 0 &&
                newStrategyParams.burnDeltaTicks > 0 &&
                newStrategyParams.mintDeltaTicks > 0 &&
                newStrategyParams.widthCoefficient > 0 &&
                newStrategyParams.widthTicks > 0 &&
                newStrategyParams.oracleObservationDelta > 0),
            ExceptionsLibrary.INVARIANT
        );
        strategyParams = newStrategyParams;
        emit UpdateStrategyParams(tx.origin, msg.sender, newStrategyParams);
    }

    function manualPull(
        IIntegrationVault fromVault,
        IIntegrationVault toVault,
        uint256[] memory tokenAmounts,
        bytes memory vaultOptions
    ) external {
        _requireAdmin();
        fromVault.pull(address(toVault), tokens, tokenAmounts, vaultOptions);
    }

    function rebalance(
        uint256[] memory burnTokenAmounts,
        uint256[] memory swapTokenAmounts,
        uint256[] memory increaseTokenAmounts,
        uint256[] memory decreaseTokenAmounts,
        uint256 deadline,
        bytes memory options
    ) external {
        _requireAdmin();
        _burnRebalance(burnTokenAmounts);
        _biRebalance(swapTokenAmounts, deadline, options);
        _mintRebalance(deadline);
        _rebalanceUniV3Vault(increaseTokenAmounts, decreaseTokenAmounts, deadline, options);
    }

    /// @dev if the current tick differs from lastMintRebalanceTick by more than burnDeltaTicks,
    /// then function transfers all tokens from UniV3Vault to ERC20Vault and burns the position by uniV3Nft
    function _burnRebalance(uint256[] memory burnTokenAmounts) internal {
        uint256 uniV3Nft = uniV3Vault.nft();
        if (uniV3Nft == 0) {
            return;
        }

        StrategyParams memory strategyParams_ = strategyParams;
        (int24 tick, ) = _getAverageTickAndPrice(pool);

        int24 delta = tick - lastMintRebalanceTick;
        if (delta < 0) {
            delta = -delta;
        }

        if (delta > strategyParams_.burnDeltaTicks) {
            uint256[] memory collectedTokens = uniV3Vault.collectEarnings();
            for (uint256 i = 0; i < 2; i++) {
                require(collectedTokens[i] >= burnTokenAmounts[i], ExceptionsLibrary.LIMIT_UNDERFLOW);
            }
            (, , , , , , , uint256 liquidity, , , , ) = positionManager.positions(uniV3Nft);
            require(liquidity == 0, ExceptionsLibrary.INVARIANT);
            positionManager.burn(uniV3Nft);

            emit BurnUniV3Position(tx.origin, uniV3Nft);
        }
    }

    function _getRatios(uint256 uniV3Nft, int24 averageTick) internal view returns (uint256 token0RatioD, uint256 token1RatioD) {
        (, , , , , int24 lowerTick, int24 upperTick, , , , , ) = positionManager.positions(uniV3Nft);
        uint160 sqrtLowerPriceX96 = TickMath.getSqrtRatioAtTick(lowerTick);
        uint160 sqrtUpperPriceX96 = TickMath.getSqrtRatioAtTick(upperTick);
        uint160 sqrtCurrentRatio = TickMath.getSqrtRatioAtTick(averageTick);
        token0RatioD = FullMath.mulDiv(sqrtCurrentRatio, token0RatioD, sqrtUpperPriceX96);
        token1RatioD = FullMath.mulDiv(sqrtLowerPriceX96, token0RatioD, sqrtCurrentRatio);
    }

    function _biRebalance(
        uint256[] memory swapTokenAmounts,
        uint256 deadline,
        bytes memory options
    ) internal returns (uint256[] memory amountsOut) {
        {
            (int24 averageTick, uint256 priceX96) = _getAverageTickAndPrice(pool);
            uint256 token0RatioD = DENOMINATOR >> 1;
            uint256 token1RatioD = DENOMINATOR >> 1;
            {
                uint256 uniV3Nft = uniV3Vault.nft();
                if (uniV3Nft != 0) {
                    (token0RatioD, token1RatioD) = _getRatios(uniV3Nft, averageTick);
                }
            }
            uint256 amountIn = 0;
            uint256 tokenInIndex = 0;
            (uint256[] memory erc20Tvl, ) = erc20Vault.tvl();
            {
                if (moneyVault.supportsInterface(type(IAaveVault).interfaceId)) {
                    IAaveVault(address(moneyVault)).updateTvls();
                }
                (uint256[] memory moneyTvl, ) = moneyVault.tvl();
                uint256 token0Term = FullMath.mulDiv(
                    FullMath.mulDiv(token1RatioD, priceX96, CommonLibrary.Q96),
                    erc20Tvl[0] + moneyTvl[0],
                    DENOMINATOR
                );

                uint256 token1Term = FullMath.mulDiv(token0RatioD, erc20Tvl[1] + moneyTvl[1], DENOMINATOR);
                if (token0Term >= token1Term) {
                    amountIn = FullMath.mulDiv(token0Term - token1Term, CommonLibrary.Q96, priceX96);
                    tokenInIndex = 0;
                } else {
                    amountIn = token1Term - token0Term;
                    tokenInIndex = 1;
                }
            }
            // if there are not enough tokens on erc20Vault, then we pull them from moneyVault
            if (erc20Tvl[tokenInIndex] < amountIn) {
                uint256[] memory tokenForPull = new uint256[](2);
                tokenForPull[tokenInIndex] = amountIn - erc20Tvl[tokenInIndex];
                moneyVault.pull(address(erc20Vault), tokens, tokenForPull, options);
                (erc20Tvl, ) = erc20Vault.tvl();
                amountIn = erc20Tvl[tokenInIndex];
            }

            amountsOut = _swapTokensOnERC20Vault(amountIn, tokenInIndex, swapTokenAmounts, deadline);
        }

        // TODO: rewrite it in a better way
        // rebalance erc20/moneyvault by given ratio
        {
            (uint256[] memory erc20Tvl, ) = erc20Vault.tvl();
            (uint256[] memory moneyTvl, ) = moneyVault.tvl();
            for (uint256 i = 0; i < 2; i++) {
                uint256 erc20Amount = erc20Tvl[i];
                uint256 moneyAmount = moneyTvl[i];
                uint256 ratioValue = FullMath.mulDiv(
                    strategyParams.erc20MoneyRatioD,
                    erc20Amount + moneyAmount,
                    DENOMINATOR
                );
                if (ratioValue > erc20Amount) {
                    uint256 delta = ratioValue - erc20Amount;
                    uint256[] memory pullAmounts = new uint256[](2);
                    pullAmounts[i] = delta;
                    moneyVault.pull(address(erc20Vault), tokens, pullAmounts, options);
                } else {
                    uint256 delta = erc20Amount - ratioValue;
                    uint256[] memory pullAmounts = new uint256[](2);
                    pullAmounts[i] = delta;
                    erc20Vault.pull(address(moneyVault), tokens, pullAmounts, options);
                }
            }
        }
    }

    function _mintRebalance(uint256 deadline) internal {
        if (uniV3Vault.nft() != 0) {
            return;
        }
        StrategyParams memory strategyParams_ = strategyParams;
        (int24 tick, ) = _getAverageTickAndPrice(pool);
        int24 widthTicks = strategyParams_.widthTicks;

        int24 nearestLeftTick = (tick / widthTicks) * widthTicks;
        int24 nearestRightTick = nearestLeftTick;

        if (nearestLeftTick < tick) {
            nearestRightTick += widthTicks;
        } else if (nearestLeftTick > tick) {
            nearestLeftTick -= widthTicks;
        }

        int24 distToLeft = tick - nearestLeftTick;
        int24 distToRight = nearestRightTick - tick;
        int24 newMintTick = nearestLeftTick;

        if (distToLeft > strategyParams_.mintDeltaTicks && distToRight > strategyParams_.mintDeltaTicks) {
            return;
        }

        if (distToLeft <= distToRight) {
            newMintTick = nearestLeftTick;
        } else {
            newMintTick = nearestRightTick;
        }

        _mintUniV3Position(
            newMintTick,
            newMintTick - strategyParams_.widthCoefficient * widthTicks,
            newMintTick + strategyParams_.widthCoefficient * widthTicks,
            deadline
        );
        lastMintRebalanceTick = newMintTick;
    }

    function _getTvlInToken0(address vaultAddress, uint256 priceX96) internal returns (uint256 amount) {
        (uint256[] memory tvl, ) = IIntegrationVault(vaultAddress).tvl();
        return tvl[0] + FullMath.mulDiv(tvl[1], CommonLibrary.Q96, priceX96);
    }

    function _rebalanceUniV3Vault(
        uint256[] memory increaseTokenAmounts,
        uint256[] memory decreaseTokenAmounts,
        uint256 deadline,
        bytes memory options
    ) internal {
        uint256 uniV3Nft = uniV3Vault.nft();
        if (uniV3Nft == 0) {
            return;
        }

        (int24 averageTick, uint256 priceX96) = _getAverageTickAndPrice(pool);
        (uint256 token0RatioD, uint256 token1RatioD) = _getRatios(uniV3Nft, averageTick);
        uint256 uniV3RatioD = DENOMINATOR - token0RatioD - token1RatioD;
        
        uint256 moneyTvlInToken0 = _getTvlInToken0(address(moneyVault), priceX96);
        uint256 erc20TvlInToken0 = _getTvlInToken0(address(erc20Vault), priceX96);
        uint256 uniV3TvlInToken0 = _getTvlInToken0(address(uniV3Vault), priceX96);
        uint256 expectedCapitalOnUniV3 = FullMath.mulDiv(uniV3RatioD,  moneyTvlInToken0 + erc20TvlInToken0 + uniV3TvlInToken0, DENOMINATOR);

        if (expectedCapitalOnUniV3 > uniV3TvlInToken0) {
            uint256 delta = expectedCapitalOnUniV3 - uniV3TvlInToken0;
            
        } else {
            uint256 delta = uniV3TvlInToken0 - expectedCapitalOnUniV3;
                
        }
    }

    function _getAverageTickAndPrice(IUniswapV3Pool pool_) internal view returns (int24 averageTick, uint256 priceX96) {
        uint32 oracleObservationDelta = strategyParams.oracleObservationDelta;
        (, int24 tick, , , , , ) = pool_.slot0();
        bool withFail = false;
        (averageTick, , withFail) = OracleLibrary.consult(address(pool_), oracleObservationDelta);
        // Fails when we dont have observations, so return spot tick as this was the last trade price
        if (withFail) {
            averageTick = tick;
        }
        uint256 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(averageTick);
        priceX96 = FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, CommonLibrary.Q96);
    }

    function _getTokenAmountInVaults(uint256 tokenIndex) internal view returns (uint256 amount) {
        (uint256[] memory moneyVaultTvl, ) = moneyVault.tvl();
        (uint256[] memory erc20VaultTvl, ) = erc20Vault.tvl();
        amount = moneyVaultTvl[tokenIndex] + erc20VaultTvl[tokenIndex];
    }

    function _swapTokensOnERC20Vault(
        uint256 amountIn,
        uint256 tokenInIndex,
        uint256[] memory minTokensAmount,
        uint256 deadline
    ) internal returns (uint256[] memory amountsOut) {
        ISwapRouter.ExactInputSingleParams memory swapParams = ISwapRouter.ExactInputSingleParams({
            tokenIn: tokens[tokenInIndex],
            tokenOut: tokens[tokenInIndex ^ 1],
            fee: pool.fee(),
            recipient: address(erc20Vault),
            deadline: deadline,
            amountIn: amountIn,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });

        bytes memory routerResult;
        {
            bytes memory data = abi.encode(swapParams);
            erc20Vault.externalCall(tokens[tokenInIndex], APPROVE_SELECTOR, abi.encode(address(router), amountIn)); // approve
            routerResult = erc20Vault.externalCall(address(router), EXACT_INPUT_SINGLE_SELECTOR, data); // swap
            erc20Vault.externalCall(tokens[tokenInIndex], APPROVE_SELECTOR, abi.encode(address(router), 0)); // reset allowance
        }

        uint256 amountOut = abi.decode(routerResult, (uint256));
        require(minTokensAmount[tokenInIndex ^ 1] <= amountOut, ExceptionsLibrary.LIMIT_UNDERFLOW);

        amountsOut = new uint256[](2);
        amountsOut[tokenInIndex ^ 1] = amountOut;

        emit SwapTokensOnERC20Vault(tx.origin, swapParams);
    }

    function _mintUniV3Position(
        int24 tick,
        int24 lowerTick,
        int24 upperTick,
        uint256 deadline
    ) internal {
        uint256[] memory tokensForMint = new uint256[](2);
        {
            uint160 lowerSqrtRatio = TickMath.getSqrtRatioAtTick(lowerTick);
            uint160 upperSqrtRatio = TickMath.getSqrtRatioAtTick(upperTick);
            uint160 currentSqrtRatio = TickMath.getSqrtRatioAtTick(tick);
            (uint256 token0Amount, uint256 token1Amount) = LiquidityAmounts.getAmountsForLiquidity(
                currentSqrtRatio,
                lowerSqrtRatio,
                upperSqrtRatio,
                1
            ); // get token amounts for 1 unit of liquidity for mint
            tokensForMint[0] = token0Amount;
            tokensForMint[1] = token1Amount;
        }

        {
            // transfer tokens from erc20Vault to strategy address of needed amount for mint of position
            (uint256[] memory erc20Tvl, ) = erc20Vault.tvl();
            for (uint256 i = 0; i < 2; i++) {
                require(tokensForMint[i] <= erc20Tvl[i], ExceptionsLibrary.LIMIT_UNDERFLOW);
                erc20Vault.externalCall(tokens[i], APPROVE_SELECTOR, abi.encode(address(this), tokensForMint[i]));
                IERC20(tokens[i]).safeTransferFrom(address(erc20Vault), address(this), tokensForMint[i]);
                erc20Vault.externalCall(tokens[i], APPROVE_SELECTOR, abi.encode(address(this), 0));
            }
        }

        IERC20(tokens[0]).safeApprove(address(positionManager), tokensForMint[0]);
        IERC20(tokens[1]).safeApprove(address(positionManager), tokensForMint[1]);

        (uint256 newNft, , uint256 usedToken0Amount, uint256 usedToken1Amount) = positionManager.mint(
            INonfungiblePositionManager.MintParams({
                token0: tokens[0],
                token1: tokens[1],
                fee: pool.fee(),
                tickLower: lowerTick,
                tickUpper: upperTick,
                amount0Desired: tokensForMint[0],
                amount1Desired: tokensForMint[1],
                amount0Min: 0,
                amount1Min: 0,
                recipient: address(this),
                deadline: deadline
            })
        );

        positionManager.safeTransferFrom(address(this), address(uniV3Vault), newNft);
        IERC20(tokens[0]).safeApprove(address(positionManager), 0);
        IERC20(tokens[1]).safeApprove(address(positionManager), 0);

        // transfer redundant tokens to erc20Vault back
        // perhaps not needed
        {
            uint256 token0ForTransfer = tokensForMint[0] - usedToken0Amount;
            uint256 token1ForTransfer = tokensForMint[1] - usedToken1Amount;
            if (token0ForTransfer > 0) {
                IERC20(tokens[0]).safeTransfer(address(erc20Vault), token0ForTransfer);
            }
            if (token1ForTransfer > 0) {
                IERC20(tokens[1]).safeTransfer(address(erc20Vault), token1ForTransfer);
            }
        }

        emit MintUniV3Position(tx.origin, newNft, lowerTick, upperTick);
    }

    /// @notice Covert token amounts and deadline to byte options
    /// @dev Empty tokenAmounts are equivalent to zero tokenAmounts
    function _makeUniswapVaultOptions(uint256[] memory tokenAmounts, uint256 deadline)
        internal
        pure
        returns (bytes memory options)
    {
        options = new bytes(0x60);
        assembly {
            mstore(add(options, 0x60), deadline)
        }
        if (tokenAmounts.length == 2) {
            uint256 tokenAmount0 = tokenAmounts[0];
            uint256 tokenAmount1 = tokenAmounts[1];
            assembly {
                mstore(add(options, 0x20), tokenAmount0)
                mstore(add(options, 0x40), tokenAmount1)
            }
        }
    }

    function _contractName() internal pure override returns (bytes32) {
        return bytes32("HStrategy");
    }

    function _contractVersion() internal pure override returns (bytes32) {
        return bytes32("1.0.0");
    }

    /// @notice Emitted when new position in UniV3Pool has been minted.
    /// @param origin Origin of the transaction (tx.origin)
    /// @param uniV3Nft nft of new minted position
    /// @param lowerTick lowerTick of that position
    /// @param upperTick upperTick of that position
    event MintUniV3Position(address indexed origin, uint256 uniV3Nft, int24 lowerTick, int24 upperTick);

    /// @notice Emitted when position in UniV3Pool has been burnt.
    /// @param origin Origin of the transaction (tx.origin)
    /// @param uniV3Nft nft of new minted position
    event BurnUniV3Position(address indexed origin, uint256 uniV3Nft);

    /// @notice Emitted when swap is initiated.
    /// @param origin Origin of the transaction (tx.origin)
    /// @param swapParams Swap params
    event SwapTokensOnERC20Vault(address indexed origin, ISwapRouter.ExactInputSingleParams swapParams);

    /// @notice Emitted when Strategy params are set.
    /// @param origin Origin of the transaction (tx.origin)
    /// @param sender Sender of the call (msg.sender)
    /// @param params Updated params
    event UpdateStrategyParams(address indexed origin, address indexed sender, StrategyParams params);

    /// @notice Emitted when Other params are set.
    /// @param origin Origin of the transaction (tx.origin)
    /// @param sender Sender of the call (msg.sender)
    /// @param params Updated params
    event UpdateOtherParams(address indexed origin, address indexed sender, OtherParams params);
}
