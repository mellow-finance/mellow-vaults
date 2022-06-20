// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import "../interfaces/external/univ3/INonfungiblePositionManager.sol";
import "../interfaces/external/univ3/IUniswapV3Pool.sol";
import "../interfaces/external/univ3/IUniswapV3Factory.sol";
import "../interfaces/external/univ3/ISwapRouter.sol";
import "../interfaces/vaults/IERC20Vault.sol";
import "../libraries/ExceptionsLibrary.sol";
import "../libraries/CommonLibrary.sol";
import "../libraries/external/FullMath.sol";
import "../libraries/external/TickMath.sol";
import "../libraries/external/OracleLibrary.sol";
import "../utils/DefaultAccessControlLateInit.sol";
import "../utils/ContractMeta.sol";

contract HStrategy is ContractMeta, DefaultAccessControlLateInit {
    using SafeERC20 for IERC20;

    struct OtherParams {
        uint256 minToken0ForOpening;
        uint256 minToken1ForOpening;
    }

    struct StrategyParams {
        uint256 deltaBurn;
        uint256 deltaMint;
        uint256 deltaBi;
    }

    IERC20Vault public erc20Vault;
    IIntegrationVault public moneyVault;
    address[] public tokens;

    INonfungiblePositionManager public positionManager;
    IUniswapV3Pool public pool;
    uint256 public uniV3Nft;

    bytes4 public constant APPROVE_SELECTOR = 0x095ea7b3;
    bytes4 public constant EXACT_INPUT_SINGLE_SELECTOR = ISwapRouter.exactInputSingle.selector;
    ISwapRouter public router;

    uint256 public lastRebalanceTick;

    OtherParams public otherParams;
    StrategyParams public strategyParams;

    constructor(INonfungiblePositionManager positionManager_, ISwapRouter router_) {
        require(address(positionManager_) != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        require(address(router_) != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        positionManager = positionManager_;
        DefaultAccessControlLateInit.init(address(this));
        lastRebalanceTick = 0;
        router = router_;
    }

    function initialize(
        INonfungiblePositionManager positionManager_,
        address[] memory tokens_, // array of tokens, that we want operate
        IERC20Vault erc20Vault_, // vault to make transfers
        IIntegrationVault moneyVault_, // aave vault
        uint24 fee_, // fee of univ3 pool
        address admin_ // admin of the strategy
    ) external {
        DefaultAccessControlLateInit.init(admin_); // call once is checked here
        address[] memory erc20Tokens = erc20Vault_.vaultTokens();
        address[] memory moneyTokens = moneyVault_.vaultTokens();
        require(tokens_.length == 2, ExceptionsLibrary.INVALID_LENGTH);
        require(erc20Tokens.length == 2, ExceptionsLibrary.INVALID_LENGTH);
        require(moneyTokens.length == 2, ExceptionsLibrary.INVALID_LENGTH);
        for (uint256 i = 0; i < 2; i++) {
            require(erc20Tokens[i] == tokens_[i], ExceptionsLibrary.INVARIANT);
            require(moneyTokens[i] == tokens_[i], ExceptionsLibrary.INVARIANT);
        }
        positionManager = positionManager_;
        erc20Vault = erc20Vault_;
        moneyVault = moneyVault_;
        tokens = tokens_;
        IUniswapV3Factory factory = IUniswapV3Factory(positionManager_.factory());
        pool = IUniswapV3Pool(factory.getPool(tokens[0], tokens[1], fee_));
        require(address(pool) != address(0), ExceptionsLibrary.ADDRESS_ZERO);
    }

    function createStrategy(
        address[] memory tokens_,
        IERC20Vault erc20Vault_,
        IIntegrationVault moneyVault_,
        uint24 fee_,
        address admin_
    ) external returns (HStrategy strategy) {
        strategy = HStrategy(Clones.clone(address(this)));
        strategy.initialize(positionManager, tokens_, erc20Vault_, moneyVault_, fee_, admin_);
    }

    function updateOtherParams(OtherParams calldata newOtherParams) external {
        _requireAdmin();
        require(
            (newOtherParams.minToken0ForOpening > 0) &&
                (newOtherParams.minToken1ForOpening > 0) &&
                (newOtherParams.minToken0ForOpening <= 1000000000) &&
                (newOtherParams.minToken1ForOpening <= 1000000000),
            ExceptionsLibrary.INVARIANT
        );
        otherParams = newOtherParams;
        // TODO:
        // add emit of event
    }

    function updateStrategyParams(StrategyParams calldata newStrategyParams) external {
        _requireAdmin();
        require(
            newStrategyParams.deltaBi > 0 && newStrategyParams.deltaMint > 0 && newStrategyParams.deltaBurn > 0,
            ExceptionsLibrary.INVARIANT
        );
        strategyParams = newStrategyParams;
        // TODO:
        // add emit of event
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

    // TODO
    function rebalance() external {}

    // TODO
    function _burnRebalance() internal {}

    /// @dev swaps one token to another to get needed ratio of tokens
    /// @param targetToken0 wx * capital in token0
    /// @param targetToken1 wy * capital in token1
    /// @param minTokenAmounts slippage protection for swap
    function _rebalanceTokens(
        uint256 targetToken0,
        uint256 targetToken1,
        uint256[] memory minTokenAmounts
    ) internal {
        (uint256[] memory moneyVaultTvls, ) = moneyVault.tvl();
        (uint256 sqrtX96Price, , , , , , ) = pool.slot0();
        uint256 priceX96 = FullMath.mulDiv(sqrtX96Price, sqrtX96Price, CommonLibrary.Q96);
        int256 deltaAmount = int256(FullMath.mulDiv(targetToken1, priceX96, CommonLibrary.Q96) * moneyVaultTvls[0]) -
            int256(targetToken0 * moneyVaultTvls[1]);

        ISwapRouter.ExactInputSingleParams memory swapParams;
        uint256 tokenInIndex = 0;
        uint256 amountIn = 0;

        if (deltaAmount > 0) {
            amountIn = FullMath.mulDiv(uint256(deltaAmount), CommonLibrary.Q96, priceX96);
            tokenInIndex = 0;
        } else {
            amountIn = uint256(-deltaAmount);
            tokenInIndex = 1;
        }

        if (amountIn == 0) {
            return;
        }

        swapParams = ISwapRouter.ExactInputSingleParams({
            tokenIn: tokens[tokenInIndex],
            tokenOut: tokens[tokenInIndex ^ 1],
            fee: pool.fee(),
            recipient: address(erc20Vault),
            deadline: block.timestamp + 1,
            amountIn: amountIn,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });

        bytes memory data = abi.encode(swapParams);
        erc20Vault.externalCall(tokens[tokenInIndex], APPROVE_SELECTOR, abi.encode(address(router), amountIn)); // approve
        bytes memory routerResult = erc20Vault.externalCall(address(router), EXACT_INPUT_SINGLE_SELECTOR, data); //swap
        erc20Vault.externalCall(tokens[tokenInIndex], APPROVE_SELECTOR, abi.encode(address(router), 0)); // reset allowance

        uint256 amountOut = abi.decode(routerResult, (uint256));
        require(minTokenAmounts[tokenInIndex ^ 1] <= amountOut, ExceptionsLibrary.LIMIT_UNDERFLOW);
    }

    // TODO
    function _mintRebalance() internal view {
        if (uniV3Nft == 0) {}
        (, , , , , , , , , , , uint128 to) = positionManager.positions(uniV3Nft);
    }

    // mints new nft for given positions
    function _mintNewNft(
        int24 lowerTick,
        int24 upperTick,
        uint256 deadline
    ) internal returns (uint256 newNft) {
        OtherParams memory params = otherParams;
        IERC20(tokens[0]).safeApprove(address(positionManager), params.minToken0ForOpening);
        IERC20(tokens[1]).safeApprove(address(positionManager), params.minToken1ForOpening);
        (newNft, , , ) = positionManager.mint(
            INonfungiblePositionManager.MintParams({
                token0: tokens[0],
                token1: tokens[1],
                fee: pool.fee(),
                tickLower: lowerTick,
                tickUpper: upperTick,
                amount0Desired: params.minToken0ForOpening,
                amount1Desired: params.minToken1ForOpening,
                amount0Min: 0,
                amount1Min: 0,
                recipient: address(this),
                deadline: deadline
            })
        );
        IERC20(tokens[0]).safeApprove(address(positionManager), 0);
        IERC20(tokens[1]).safeApprove(address(positionManager), 0);
    }

    function _contractName() internal pure override returns (bytes32) {
        return bytes32("HStrategy");
    }

    function _contractVersion() internal pure override returns (bytes32) {
        return bytes32("1.0.0");
    }
}
