// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../interfaces/vaults/IERC20Vault.sol";
import "../interfaces/vaults/IIntegrationVault.sol";

import "../interfaces/utils/ILpCallback.sol";

import "../interfaces/adapters/IAdapter.sol";

import "../libraries/ExceptionsLibrary.sol";
import "../libraries/UniswapCalculations.sol";

import "../libraries/external/FullMath.sol";
import "../libraries/external/LiquidityAmounts.sol";
import "../libraries/external/TickMath.sol";

import "../utils/DefaultAccessControlLateInit.sol";

/*
    The contract represents a base strategy operating on a set of positions within a specific AMM.
    The AMM itself is exclusively defined by the corresponding adapter, while the rebalancing logic is determined by 
    an external operator-strategy contract, which calls the rebalance function of this BaseAmmStrategy.
    
    Each position is defined by ticks, as well as by the capital ratio relative to the total capital of the corresponding ERC20RootVault.
*/
contract BaseAmmStrategy is DefaultAccessControlLateInit, ILpCallback {
    /// @dev Structure defining information about a position - the lower and upper ticks of the position, as well as
    /// the capital ratio within the position relative to the total capital of the corresponding ERC20RootVault.
    /// @param tickLower The lower tick of the position.
    /// @param tickUpper The upper tick of the position.
    /// @param capitalRatioX96 The capital ratio within the position relative to the total capital of the ERC20RootVault, scaled by 2^96.
    struct Position {
        int24 tickLower;
        int24 tickUpper;
        uint256 capitalRatioX96;
    }

    /// @dev Structure containing information about token swapping method during rebalancing process.
    /// @param router The address of the router contract for token swapping.
    /// @param tokenInIndex The index of the token to be swapped.
    /// @param amountIn The amount of token to be swapped in.
    /// @param amountOutMin The minimum acceptable amount of token to be received in the swap.
    /// @param data Additional data needed for the token swap.
    struct SwapData {
        address router;
        uint256 tokenInIndex;
        uint256 amountIn;
        uint256 amountOutMin;
        bytes data;
    }

    /// @dev Structure containing mutable parameters of the strategy.
    /// @param securityParams Parameters for protecting against MEV manipulations.
    /// @param maxPriceSlippageX96 Parameter for protecting against price slippage during token swaps.
    /// @param maxTickDeviation Parameter determining the maximum deviation between spot ticks before and after the swap.
    /// @param minCapitalRatioDeviationX96 Minimum deficiency expressed as a fraction of the capital, from which liquidity will be added to the position during rebalancing.
    /// @param minSwapAmounts Minimum amounts of tokens for swaps to occur.
    /// @param maxCapitalRemainderRatioX96 Maximum portion that should remain in the ERC20Vault after a swap.
    /// @param initialLiquidity Initial amount of liquidity in the newly minted position.
    struct MutableParams {
        bytes securityParams;
        uint256 maxPriceSlippageX96;
        int24 maxTickDeviation;
        uint256 minCapitalRatioDeviationX96;
        uint256[] minSwapAmounts;
        uint256 maxCapitalRemainderRatioX96;
        uint128 initialLiquidity;
    }

    /// @dev Structure containing immutable parameters of the strategy.
    /// @param adapter Adapter for interacting with the AMM protocol and corresponding AMM vaults.
    /// @param pool Pool for which the strategy operates, as well as all AMM vaults.
    /// @param erc20Vault Address of the ERC20 vault, serving as a buffer for deposits/withdrawals and swaps.
    /// @param ammVaults Array of AMM vaults.
    struct ImmutableParams {
        IAdapter adapter;
        address pool;
        IERC20Vault erc20Vault;
        IIntegrationVault[] ammVaults;
    }

    /// @dev Structure containing storage with all necessary nested structures for the strategy.
    /// @param immutableParams Immutable parameters of the strategy.
    /// @param mutableParams Mutable parameters of the strategy.
    struct Storage {
        ImmutableParams immutableParams;
        MutableParams mutableParams;
    }

    uint256 public constant Q96 = 2**96;
    bytes32 public constant STORAGE_SLOT = keccak256("strategy.storage");

    function _contractStorage() internal pure returns (Storage storage s) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            s.slot := slot
        }
    }

    /// @dev Function for initializing the strategy.
    /// It performs validation of all parameters.
    /// This function can only be called once.
    /// @param admin The address of the admin for the strategy.
    /// @param immutableParams Immutable parameters of the strategy.
    /// @param mutableParams Mutable parameters of the strategy.
    function initialize(
        address admin,
        ImmutableParams memory immutableParams,
        MutableParams memory mutableParams
    ) external {
        if (
            address(immutableParams.adapter) == address(0) &&
            address(immutableParams.pool) == address(0) &&
            address(immutableParams.erc20Vault) == address(0)
        ) revert(ExceptionsLibrary.ADDRESS_ZERO);
        if (immutableParams.ammVaults.length == 0) revert(ExceptionsLibrary.INVALID_LENGTH);
        for (uint256 i = 0; i < immutableParams.ammVaults.length; i++) {
            if (address(immutableParams.ammVaults[i]) == address(0)) {
                revert(ExceptionsLibrary.ADDRESS_ZERO);
            }
        }
        _contractStorage().immutableParams = immutableParams;
        validateMutableParams(mutableParams);
        _contractStorage().mutableParams = mutableParams;
        DefaultAccessControlLateInit.init(admin);
    }

    /// @dev Function for updating the mutable parameters of the strategy.
    /// It can only be called by an address with the ADMIN_ROLE role.
    /// @param mutableParams The new mutable parameters of the strategy.
    function updateMutableParams(MutableParams memory mutableParams) external {
        _requireAdmin();
        validateMutableParams(mutableParams);
        _contractStorage().mutableParams = mutableParams;
    }

    /// @dev Function for validating the mutable parameters.
    /// @param mutableParams The mutable parameters to validate.
    /// It reverts with an error if the conditions are not met.
    function validateMutableParams(MutableParams memory mutableParams) public view {
        Storage storage s = _contractStorage();
        s.immutableParams.adapter.validateSecurityParams(mutableParams.securityParams);

        if (mutableParams.maxPriceSlippageX96 > Q96 / 2) revert(ExceptionsLibrary.LIMIT_OVERFLOW);
        if (mutableParams.maxTickDeviation < 0) revert(ExceptionsLibrary.LIMIT_UNDERFLOW);
        if (mutableParams.minCapitalRatioDeviationX96 > Q96 / 2) revert(ExceptionsLibrary.LIMIT_OVERFLOW);
        if (mutableParams.minSwapAmounts.length != 2) revert(ExceptionsLibrary.INVALID_LENGTH);
        if (mutableParams.maxCapitalRemainderRatioX96 > Q96 / 2) revert(ExceptionsLibrary.LIMIT_OVERFLOW);
        if (mutableParams.initialLiquidity == 0) revert(ExceptionsLibrary.VALUE_ZERO);
    }

    /// @dev Function for retrieving the mutable parameters of the strategy.
    /// @return mutableParams The mutable parameters of the strategy.
    function getMutableParams() public view returns (MutableParams memory) {
        return _contractStorage().mutableParams;
    }

    /// @dev Function for retrieving the immutable parameters of the strategy.
    /// @return immutableParams The immutable parameters of the strategy.
    function getImmutableParams() public view returns (ImmutableParams memory) {
        return _contractStorage().immutableParams;
    }

    /// @dev Function for retrieving the current state of positions in the strategy.
    /// @param s The storage struct containing all necessary information for the strategy, including both immutable and mutable parameters.
    /// @return currentState An array of Position structs containing information about positions in all ammVaults, in the order specified in immutableParams.
    function getCurrentState(Storage memory s) public view returns (Position[] memory currentState) {
        IIntegrationVault[] memory ammVaults = s.immutableParams.ammVaults;
        currentState = new Position[](ammVaults.length);
        (uint160 sqrtPriceX96, ) = s.immutableParams.adapter.slot0EnsureNoMEV(
            s.immutableParams.pool,
            s.mutableParams.securityParams
        );
        uint256 priceX96 = FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, Q96);

        uint256 totalCapitalInToken1 = 0;
        for (uint256 i = 0; i < ammVaults.length; i++) {
            (uint256[] memory tvl, ) = ammVaults[i].tvl();
            uint256 capitalInToken1 = FullMath.mulDiv(tvl[0], priceX96, Q96) + tvl[1];
            totalCapitalInToken1 += capitalInToken1;
            currentState[i].capitalRatioX96 = capitalInToken1;
            (currentState[i].tickLower, currentState[i].tickUpper, ) = s.immutableParams.adapter.positionInfo(
                s.immutableParams.adapter.tokenId(address(ammVaults[i]))
            );
        }

        {
            (uint256[] memory tvl, ) = s.immutableParams.erc20Vault.tvl();
            totalCapitalInToken1 += FullMath.mulDiv(tvl[0], priceX96, Q96) + tvl[1];
        }

        require(totalCapitalInToken1 > 0, ExceptionsLibrary.INVALID_VALUE);

        for (uint256 i = 0; i < ammVaults.length; i++) {
            currentState[i].capitalRatioX96 = FullMath.mulDiv(
                currentState[i].capitalRatioX96,
                Q96,
                totalCapitalInToken1
            );
        }
    }

    /// @notice This function performs rebalancing of positions within the strategy.
    /// It can only be called by an address with the ADMIN_ROLE or OPERATOR roles.
    /// @param targetState An array of Position structs representing the target positions and the desired capital allocation among them.
    /// Each Position struct contains:
    /// - tickLower: The lower tick of the position.
    /// - tickUpper: The upper tick of the position.
    /// - capitalRatioX96: The capital ratio within the position relative to the total capital of the ERC20RootVault, scaled by 2^96.
    /// @param swapData A SwapData struct containing data necessary for token swapping during rebalancing.
    /// The SwapData struct includes:
    /// - router: The address of the router contract for token swapping.
    /// - tokenInIndex: The index of the token to be swapped.
    /// - amountIn: The amount of token to be swapped in.
    /// - amountOutMin: The minimum acceptable amount of token to be received in the swap.
    /// - data: Additional data needed for the token swap.
    /// @dev This function performs the rebalancing process according to the specified targetState and swapData.
    /// It adjusts the positions within the strategy to match the targetState, performing token swaps as necessary.
    /// The rebalancing process is executed to ensure the strategy maintains its desired allocation of capital across its positions.
    function rebalance(Position[] memory targetState, SwapData calldata swapData) external {
        _requireAtLeastOperator();
        Storage memory s = _contractStorage();
        _compound(s);
        _positionsRebalance(targetState, getCurrentState(s), s);
        _swap(swapData, s);
        _ratioRebalance(targetState, s);
    }

    /// @notice This function allows for manual movement of liquidity between integration vaults.
    /// It can only be called by an address with the ADMIN_ROLE role.
    /// Usage of this function is intended for emergency cases.
    /// @param fromVault The integration vault from which liquidity will be pulled.
    /// @param toVault The integration vault to which liquidity will be deposited.
    /// @param tokenAmounts An array containing the amounts of tokens to be moved.
    /// @param vaultOptions Additional options for vault manipulation.
    function manualPull(
        IIntegrationVault fromVault,
        IIntegrationVault toVault,
        uint256[] memory tokenAmounts,
        bytes memory vaultOptions
    ) external {
        _requireAdmin();
        fromVault.pull(address(toVault), fromVault.vaultTokens(), tokenAmounts, vaultOptions);
    }

    /// @notice This callback function is used for pushing tokens into AMM vaults.
    /// It is called within the deposit wrapper or ERC20RootVault under certain conditions.
    /// It can be called by any user.
    /// @inheritdoc ILpCallback
    function depositCallback() external {
        ImmutableParams memory immutableParams = _contractStorage().immutableParams;
        IERC20Vault erc20Vault = immutableParams.erc20Vault;
        IIntegrationVault[] memory ammVaults = immutableParams.ammVaults;
        uint256 n = ammVaults.length;
        (uint256[] memory erc20Tvl, ) = erc20Vault.tvl();
        address[] memory tokens = erc20Vault.vaultTokens();
        for (uint256 i = 0; i < n; i++) {
            uint256[] memory actualAmounts = erc20Vault.pull(address(ammVaults[i]), tokens, erc20Tvl, "");
            erc20Tvl[0] -= actualAmounts[0];
            erc20Tvl[1] -= actualAmounts[1];
        }
    }

    /// @inheritdoc ILpCallback
    function withdrawCallback() external {}

    /// @dev This function iterates through all AMM vaults associated with the strategy and collects rewards and fees using delegatecall to the adapter.
    /// @param s The storage struct containing all necessary information for the strategy, including both immutable and mutable parameters.
    /// It reverts with an INVALID_STATE error if the delegatecall fails.
    function _compound(Storage memory s) private {
        for (uint256 i = 0; i < s.immutableParams.ammVaults.length; i++) {
            (bool success, ) = address(s.immutableParams.adapter).delegatecall(
                abi.encodeWithSelector(IAdapter.compound.selector, s.immutableParams.ammVaults[i])
            );
            require(success, ExceptionsLibrary.INVALID_STATE);
        }
    }

    /// @dev Private function for rebalancing positions to the state described by the targetState array.
    /// @param targetState An array of Position structs representing the target positions and the desired capital allocation among them.
    /// @param currentState An array of Position structs representing the current positions and capital allocation in the strategy.
    /// @param s The storage struct containing all necessary information for the strategy, including both immutable and mutable parameters.
    /// @notice This function compares the current positions (currentState) with the target positions (targetState) and rebalances the strategy accordingly.
    function _positionsRebalance(
        Position[] memory targetState,
        Position[] memory currentState,
        Storage memory s
    ) private {
        IIntegrationVault[] memory ammVaults = s.immutableParams.ammVaults;
        require(ammVaults.length == targetState.length, ExceptionsLibrary.INVALID_LENGTH);
        IERC20Vault erc20Vault = s.immutableParams.erc20Vault;
        address pool = s.immutableParams.pool;
        address[] memory tokens = erc20Vault.vaultTokens();
        for (uint256 i = 0; i < currentState.length; i++) {
            if (
                currentState[i].tickLower != targetState[i].tickLower ||
                currentState[i].tickUpper != targetState[i].tickUpper
            ) {
                (, uint256[] memory pullingAmounts) = ammVaults[i].tvl();
                pullingAmounts[0] <<= 1;
                pullingAmounts[1] <<= 1;
                ammVaults[i].pull(address(erc20Vault), tokens, pullingAmounts, "");
                if (targetState[i].tickLower == targetState[i].tickUpper) {
                    continue;
                }
                (bool success, bytes memory data) = address(s.immutableParams.adapter).delegatecall(
                    abi.encodeWithSelector(
                        IAdapter.mint.selector,
                        pool,
                        targetState[i].tickLower,
                        targetState[i].tickUpper,
                        s.mutableParams.initialLiquidity,
                        address(this)
                    )
                );
                if (!success) revert(ExceptionsLibrary.INVALID_STATE);
                uint256 newNft = abi.decode(data, (uint256));
                (success, ) = address(s.immutableParams.adapter).delegatecall(
                    abi.encodeWithSelector(IAdapter.swapNft.selector, address(this), ammVaults[i], newNft)
                );
                if (!success) revert(ExceptionsLibrary.INVALID_STATE);
            } else if (currentState[i].capitalRatioX96 > targetState[i].capitalRatioX96) {
                (, uint256[] memory tvl) = ammVaults[i].tvl();
                for (uint256 j = 0; j < tvl.length; j++) {
                    tvl[j] = FullMath.mulDiv(
                        tvl[j],
                        currentState[i].capitalRatioX96 - targetState[i].capitalRatioX96,
                        currentState[i].capitalRatioX96
                    );
                }
                ammVaults[i].pull(address(erc20Vault), tokens, tvl, "");
            }
        }
    }

    /// @dev This function performs token swapping according to the logic described in the swapData struct.
    /// @param swapData A SwapData struct containing data necessary for token swapping.
    /// @param s The storage struct containing all necessary information for the strategy, including both immutable and mutable parameters.
    function _swap(SwapData calldata swapData, Storage memory s) private {
        IERC20Vault erc20Vault = s.immutableParams.erc20Vault;
        address[] memory tokens = erc20Vault.vaultTokens();
        if (swapData.amountIn < s.mutableParams.minSwapAmounts[swapData.tokenInIndex]) return;
        address tokenIn = tokens[swapData.tokenInIndex];
        address tokenOut = tokens[swapData.tokenInIndex ^ 1];
        (uint160 sqrtPriceX96, int24 tick) = s.immutableParams.adapter.slot0(s.immutableParams.pool);
        uint256 priceBeforeX96 = FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, Q96);
        if (swapData.tokenInIndex == 1) {
            priceBeforeX96 = FullMath.mulDiv(Q96, Q96, priceBeforeX96);
        }
        uint256 tokenInBefore = IERC20(tokenIn).balanceOf(address(erc20Vault));
        uint256 tokenOutBefore = IERC20(tokenOut).balanceOf(address(erc20Vault));

        erc20Vault.externalCall(
            tokenIn,
            IERC20.approve.selector,
            abi.encode(address(swapData.router), swapData.amountIn)
        );
        erc20Vault.externalCall(address(swapData.router), bytes4(swapData.data[:4]), swapData.data[4:]);
        erc20Vault.externalCall(tokenIn, IERC20.approve.selector, abi.encode(address(swapData.router), 0));

        uint256 tokenInDelta = tokenInBefore - IERC20(tokenIn).balanceOf(address(erc20Vault));
        uint256 tokenOutDelta = IERC20(tokenOut).balanceOf(address(erc20Vault)) - tokenOutBefore;
        require(tokenOutDelta >= swapData.amountOutMin, ExceptionsLibrary.LIMIT_UNDERFLOW);

        uint256 swapPriceX96 = FullMath.mulDiv(tokenOutDelta, Q96, tokenInDelta);
        require(
            swapPriceX96 >= FullMath.mulDiv(priceBeforeX96, Q96 - s.mutableParams.maxPriceSlippageX96, Q96),
            ExceptionsLibrary.LIMIT_UNDERFLOW
        );
        (, int24 tickAfter) = s.immutableParams.adapter.slot0(s.immutableParams.pool);
        if (tick == tickAfter) return;
        require(
            tick + s.mutableParams.maxTickDeviation >= tickAfter &&
                tickAfter + s.mutableParams.maxTickDeviation >= tick,
            ExceptionsLibrary.LIMIT_OVERFLOW
        );
    }

    /// @dev Private function for pushing tokens from erc20Vault into AMM vaults.
    /// It is called from the _ratioRebalance function, where additional computations take place (separated due to stack-too-deep).
    /// @param targetState An array of Position structs representing the target positions and the desired capital allocation among them.
    /// @param s The storage struct containing all necessary information for the strategy, including both immutable and mutable parameters.
    /// @param tvls An array of arrays containing the tvls for each AMM vault.
    /// @param priceX96 The price of token1 relative to token0, scaled by 2^96.
    /// @param minCapitalDeviationInToken1 The minimum capital deviation in token1.
    /// @param capitalInToken1 The capital in token1.
    /// @param sqrtRatioX96 The square root of the price ratio, scaled by 2^96.
    /// @param tokens An array containing the addresses of tokens involved in the rebalancing.
    function _pushIntoPositions(
        Position[] memory targetState,
        Storage memory s,
        uint256[][] memory tvls,
        uint256 priceX96,
        uint256 minCapitalDeviationInToken1,
        uint256 capitalInToken1,
        uint160 sqrtRatioX96,
        address[] memory tokens
    ) private {
        for (uint256 i = 0; i < s.immutableParams.ammVaults.length; i++) {
            uint256 requiredCapitalInToken1;
            {
                uint256[] memory tvl = tvls[i];
                uint256 vaultCapitalInToken1 = FullMath.mulDiv(tvl[0], priceX96, Q96) + tvl[1];
                uint256 expectedCapitalInToken1 = FullMath.mulDiv(targetState[i].capitalRatioX96, capitalInToken1, Q96);
                if (vaultCapitalInToken1 + minCapitalDeviationInToken1 > expectedCapitalInToken1) continue;
                requiredCapitalInToken1 = expectedCapitalInToken1 - vaultCapitalInToken1;
            }
            if (requiredCapitalInToken1 == 0) continue;

            uint256 targetRatioOfToken1X96 = UniswapCalculations.calculateTargetRatioOfToken1(
                UniswapCalculations.PositionParams({
                    sqrtLowerPriceX96: TickMath.getSqrtRatioAtTick(targetState[i].tickLower),
                    sqrtUpperPriceX96: TickMath.getSqrtRatioAtTick(targetState[i].tickUpper),
                    sqrtPriceX96: sqrtRatioX96
                }),
                priceX96
            );
            uint256[] memory amounts = new uint256[](2);
            amounts[1] = FullMath.mulDiv(targetRatioOfToken1X96, requiredCapitalInToken1, Q96);
            amounts[0] = FullMath.mulDiv(requiredCapitalInToken1 - amounts[1], Q96, priceX96);
            s.immutableParams.erc20Vault.pull(address(s.immutableParams.ammVaults[i]), tokens, amounts, "");
        }
        {
            uint256 maxAllowedCapitalOnERC20Vault = FullMath.mulDiv(
                capitalInToken1,
                s.mutableParams.maxCapitalRemainderRatioX96,
                Q96
            );
            (uint256[] memory erc20Tvl, ) = s.immutableParams.erc20Vault.tvl();
            uint256 erc20Capital = FullMath.mulDiv(erc20Tvl[0], priceX96, Q96) + erc20Tvl[1];
            require(erc20Capital <= maxAllowedCapitalOnERC20Vault, "Too much liquidity on erc20Vault");
        }
    }

    /// @dev Private function for pushing tokens from erc20Vault into AMM vaults.
    /// @param targetState An array of Position structs representing the target positions and the desired capital allocation among them.
    /// @param s The storage struct containing all necessary information for the strategy, including both immutable and mutable parameters.
    function _ratioRebalance(Position[] memory targetState, Storage memory s) private {
        uint256 n = s.immutableParams.ammVaults.length;
        uint256[][] memory tvls = new uint256[][](n);
        (uint256[] memory totalTvl, ) = s.immutableParams.erc20Vault.tvl();
        for (uint256 i = 0; i < n; i++) {
            (uint256[] memory tvl, ) = s.immutableParams.ammVaults[i].tvl();
            totalTvl[0] += tvl[0];
            totalTvl[1] += tvl[1];
            tvls[i] = tvl;
        }

        (uint160 sqrtRatioX96, ) = s.immutableParams.adapter.getOraclePrice(s.immutableParams.pool);
        uint256 priceX96 = FullMath.mulDiv(sqrtRatioX96, sqrtRatioX96, Q96);
        uint256 capitalInToken1 = FullMath.mulDiv(totalTvl[0], priceX96, Q96) + totalTvl[1];
        _pushIntoPositions(
            targetState,
            s,
            tvls,
            priceX96,
            FullMath.mulDiv(s.mutableParams.minCapitalRatioDeviationX96, capitalInToken1, Q96),
            capitalInToken1,
            sqrtRatioX96,
            s.immutableParams.erc20Vault.vaultTokens()
        );
    }
}
