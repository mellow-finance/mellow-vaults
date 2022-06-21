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
                newStrategyParams.widthTicks > 0),
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
        uint256 deadline,
        uint256[] memory minTokenAmounts,
        bytes memory options
    ) external returns (uint256[] memory amountsOut) {
        _requireAdmin();
        _burnRebalance();
        InternalRatioParams memory params = _mintRebalance(deadline, options);
        amountsOut = _biRebalance(params, minTokenAmounts, deadline, options);
    }

    function _mintRebalance(uint256 deadline, bytes memory options)
        internal
        returns (InternalRatioParams memory internalRatioParams)
    {
        if (uniV3Vault.nft() != 0) {
            return
                InternalRatioParams({
                    token0MoneyRatio: DENOMINATOR >> 1,
                    token1MoneyRatio: DENOMINATOR >> 1,
                    uniswapPoolRatio: 0
                });
        }

        StrategyParams memory strategyParams_ = strategyParams;
        (, int24 tick, , , , , ) = pool.slot0();
        int24 widthTicks = strategyParams_.widthTicks;
        int24 leftTick = tick - ((tick > 0 ? tick : -tick) % widthTicks);
        int24 rightTick = leftTick + widthTicks;

        if (tick - leftTick <= strategyParams_.mintDeltaTicks || rightTick - tick <= strategyParams_.mintDeltaTicks) {
            internalRatioParams = _mintUniV3Position(
                tick,
                tick - strategyParams_.widthCoefficient * widthTicks,
                tick + strategyParams_.widthCoefficient * widthTicks,
                deadline,
                options
            );
            lastMintRebalanceTick = tick;
        }
    }

    /// @dev if the current tick differs from lastMintRebalanceTick by more than burnDeltaTicks,
    /// then function transfers all tokens from UniV3Vault to ERC20Vault and burns the position by uniV3Nft
    function _burnRebalance() internal {
        uint256 uniV3Nft = uniV3Vault.nft();
        if (uniV3Nft == 0) {
            return;
        }

        StrategyParams memory strategyParams_ = strategyParams;
        (, int24 tick, , , , , ) = pool.slot0();

        int24 delta = tick - lastMintRebalanceTick;
        if (delta < 0) {
            delta = -delta;
        }

        if (delta > strategyParams_.burnDeltaTicks) {
            uniV3Vault.collectEarnings();
            (, , , , , , , uint256 liquidity, , , , ) = positionManager.positions(uniV3Nft);
            require(liquidity == 0, ExceptionsLibrary.INVARIANT);
            positionManager.burn(uniV3Nft);

            emit BurnUniV3Position(tx.origin, uniV3Nft);
        }
    }

    function _biRebalance(
        InternalRatioParams memory internalRatioParams,
        uint256[] memory minTokenAmounts,
        uint256 deadline,
        bytes memory options
    ) internal returns (uint256[] memory amountsOut) {
        uint256 priceX96;
        {
            (uint256 sqrtX96Price, , , , , , ) = pool.slot0();
            priceX96 = FullMath.mulDiv(sqrtX96Price, sqrtX96Price, CommonLibrary.Q96);
        }

        bool isPositive;
        uint256 delta;
        uint256[] memory erc20VaultTvls;
        {
            (uint256[] memory moneyVaultTvls, ) = moneyVault.tvl();
            (erc20VaultTvls, ) = erc20Vault.tvl();
            uint256 token0Amount = moneyVaultTvls[0] + erc20VaultTvls[0];
            uint256 token1Amount = moneyVaultTvls[1] + erc20VaultTvls[1];
            uint256 token1Term = FullMath.mulDiv(internalRatioParams.token1MoneyRatio, priceX96, CommonLibrary.Q96) *
                token0Amount;
            uint256 token0Term = internalRatioParams.token0MoneyRatio * token1Amount;
            if (token1Term >= token0Term) {
                isPositive = true;
                delta = token1Term - token0Term;
            } else {
                isPositive = false;
                delta = token0Term - token1Term;
            }
        }

        ISwapRouter.ExactInputSingleParams memory swapParams;
        uint256 tokenInIndex = 0;
        uint256 amountIn = 0;

        if (delta == 0) {
            return new uint256[](2);
        }

        if (isPositive) {
            amountIn = FullMath.mulDiv(delta, CommonLibrary.Q96, priceX96);
            tokenInIndex = 0;
        } else {
            amountIn = delta;
            tokenInIndex = 1;
        }

        if (erc20VaultTvls[tokenInIndex] < amountIn) {
            uint256[] memory tokensToPull = new uint256[](2);
            tokensToPull[tokenInIndex] = amountIn - erc20VaultTvls[tokenInIndex];
            moneyVault.pull(address(erc20Vault), tokens, tokensToPull, options);
        }

        swapParams = ISwapRouter.ExactInputSingleParams({
            tokenIn: tokens[tokenInIndex],
            tokenOut: tokens[tokenInIndex ^ 1],
            fee: pool.fee(),
            recipient: address(erc20Vault),
            deadline: deadline,
            amountIn: amountIn,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });


        // swap ~one token to another
        bytes memory routerResult;
        {
            bytes memory data = abi.encode(swapParams);
            erc20Vault.externalCall(tokens[tokenInIndex], APPROVE_SELECTOR, abi.encode(address(router), amountIn)); // approve
            routerResult = erc20Vault.externalCall(address(router), EXACT_INPUT_SINGLE_SELECTOR, data); //swap
            erc20Vault.externalCall(tokens[tokenInIndex], APPROVE_SELECTOR, abi.encode(address(router), 0)); // reset allowance
        }
        {
            uint256 amountOut = abi.decode(routerResult, (uint256));
            require(minTokenAmounts[tokenInIndex ^ 1] <= amountOut, ExceptionsLibrary.LIMIT_UNDERFLOW);

            amountsOut = new uint256[](2);
            amountsOut[tokenInIndex ^ 1] = amountOut;
        }

        // pull all tokens from erc20Vault to moneyVault
        {
            (erc20VaultTvls, ) = erc20Vault.tvl();
            erc20Vault.pull(address(moneyVault), tokens, erc20VaultTvls, options);
        }

        emit RebalanceTokens(tx.origin, swapParams);
    }

    function _calculateTokensForUniV3(
        uint160 lowerTickRatio,
        uint160 upperTickRatio,
        uint160 currentTickRatio,
        InternalRatioParams memory internalRatioParams
    ) internal returns (uint256 requiredToken0Amount, uint256 requiredToken1Amount) {
        if (moneyVault.supportsInterface(type(IAaveVault).interfaceId)) {
            IAaveVault(address(moneyVault)).updateTvls();
        }
        (uint256[] memory moneyVaultTvl, ) = moneyVault.tvl();
        (uint256[] memory erc20VaultTvl, ) = erc20Vault.tvl();
        uint256 totalToken0Amount = moneyVaultTvl[0] + erc20VaultTvl[0];
        uint256 totalToken1Amount = moneyVaultTvl[0] + erc20VaultTvl[0];
        uint128 totalLiquidity = LiquidityAmounts.getLiquidityForAmounts(
            currentTickRatio,
            lowerTickRatio,
            upperTickRatio,
            totalToken0Amount,
            totalToken1Amount
        );
        uint128 liquidityForUniswapPosition = uint128(
            FullMath.mulDiv(totalLiquidity, internalRatioParams.uniswapPoolRatio, DENOMINATOR)
        );

        (requiredToken0Amount, requiredToken1Amount) = LiquidityAmounts.getAmountsForLiquidity(
            currentTickRatio,
            lowerTickRatio,
            upperTickRatio,
            liquidityForUniswapPosition
        );
    }

    function _mintUniV3Position(
        int24 tick,
        int24 lowerTick,
        int24 upperTick,
        uint256 deadline,
        bytes memory options
    ) internal returns (InternalRatioParams memory internalRatioParams) {
        uint256[] memory tokensForMint = new uint256[](2);
        {
            uint160 lowerTickRatio = TickMath.getSqrtRatioAtTick(lowerTick);
            uint160 upperTickRatio = TickMath.getSqrtRatioAtTick(upperTick);
            uint160 currentTickRatio = TickMath.getSqrtRatioAtTick(tick);

            uint256 targetToken0 = FullMath.mulDiv(currentTickRatio, DENOMINATOR, upperTickRatio) >> 1;
            uint256 targetToken1 = FullMath.mulDiv(lowerTickRatio, DENOMINATOR, currentTickRatio) >> 1;
            internalRatioParams = InternalRatioParams({
                token0MoneyRatio: targetToken0,
                token1MoneyRatio: targetToken1,
                uniswapPoolRatio: DENOMINATOR - targetToken0 - targetToken1
            });

            (uint256 token0Amount, uint256 token1Amount) = _calculateTokensForUniV3(
                lowerTickRatio,
                upperTickRatio,
                currentTickRatio,
                internalRatioParams
            );
            tokensForMint[0] = token0Amount;
            tokensForMint[1] = token1Amount;
        }


        // pull tokens from moneyVault to erc20Vault if needed
        {
            bool needPullFromMoneyVault = false;
            uint256[] memory pullAmounts = new uint256[](2);
            (uint256[] memory erc20VaultTvl, ) = erc20Vault.tvl();
            for (uint256 i = 0; i < 2; i++) {
                if (tokensForMint[i] > erc20VaultTvl[i]) {
                    pullAmounts[i] = tokensForMint[i] - erc20VaultTvl[i];
                    needPullFromMoneyVault = true;
                }
            }
            if (needPullFromMoneyVault) {
                moneyVault.pull(address(erc20Vault), tokens, pullAmounts, options);
                (erc20VaultTvl, ) = erc20Vault.tvl();
                for (uint256 i = 0; i < 2; i++) {
                    if (erc20VaultTvl[i] < tokensForMint[i]) {
                        tokensForMint[i] = erc20VaultTvl[i];
                    }
                }
            }
        }

        require(tokensForMint[0] >= otherParams.minToken0ForOpening, ExceptionsLibrary.LIMIT_UNDERFLOW);
        require(tokensForMint[1] >= otherParams.minToken1ForOpening, ExceptionsLibrary.LIMIT_UNDERFLOW);


        // transfer tokens from erc20Vault to strategy address of needed amount for mint of position
        for (uint256 i = 0; i < 2; i++) {
            if (tokensForMint[i] > 0) {
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
    event RebalanceTokens(address indexed origin, ISwapRouter.ExactInputSingleParams swapParams);

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
