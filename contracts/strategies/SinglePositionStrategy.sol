// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.9;

import "@openzeppelin/contracts/utils/Multicall.sol";

import "../utils/ContractMeta.sol";
import "../utils/SinglePositionRebalancer.sol";
import "../utils/DefaultAccessControlLateInit.sol";

contract SinglePositionStrategy is ContractMeta, Multicall, DefaultAccessControlLateInit {
    using SafeERC20 for IERC20;

    uint256 public constant DENOMINATOR = 1000_000_000;
    uint256 public constant MAX_MINTING_PARAMS = 1000_000_000;

    /// @param tokens sorted array of length two with addresses of tokens of the strategy
    /// @param erc20Vault erc20Vault of the root vault system
    /// @param router uniV3 router for swapping tokens
    /// @param rebalancer address of helper needed to process rebalance
    /// @param uniV3Vaults array of uniV3Vault of the root vault system sorted by fees of pools
    /// @param tickSpacing LCM of all tick spacings over all uniV3Vaults pools
    struct ImmutableParams {
        address token0;
        address token1;
        address router;
        IERC20Vault erc20Vault;
        IUniV3Vault uniV3Vault;
        SinglePositionRebalancer rebalancer;
    }

    /// @param maxTickDeviation upper bound for an absolute deviation between the spot price and the price for a given number of seconds ago
    /// @param averageTickTimespan delta in seconds, passed to the oracle to get the average tick over the last averageTickTimespan seconds
    /// @param amount0ForMint amount of token0 is tried to be deposited on the new position
    /// @param amount1ForMint amount of token1 is tried to be deposited on the new position
    /// @param erc20CapitalRatioD ratio of tokens kept in the erc20 vault instead of univ3
    /// @param swapPool uniswapV3 Pool needed to process swaps and for calculations of average tick
    struct MutableParams {
        int24 maxTickDeviation;
        int24 tickSpacing;
        uint24 swapFee;
        uint32 averageTickTimespan;
        uint256 amount0ForMint;
        uint256 amount1ForMint;
        uint256 erc20CapitalRatioD;
        uint256 swapSlippageD;
    }

    // Immutable params
    ImmutableParams public immutableParams;

    // Mutable params
    MutableParams public mutableParams;

    /// @notice current positions in uniV3Vaults
    SinglePositionRebalancer.Interval public interval;

    // -------------------  EXTERNAL, MUTATING  -------------------

    /// @notice constructs a strategy
    constructor() {
        DefaultAccessControlLateInit.init(address(this));
    }

    /// @notice initializes the strategy
    /// @param immutableParams_ structure with all immutable params of the strategy
    /// @param mutableParams_ structure with all mutable params of strategy for initial set
    /// @param admin the addres of the admin of the strategy
    function initialize(
        ImmutableParams memory immutableParams_,
        MutableParams memory mutableParams_,
        address admin
    ) external {
        require(immutableParams_.token0 != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        require(immutableParams_.token1 != address(0), ExceptionsLibrary.ADDRESS_ZERO);

        require(immutableParams_.router != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        require(address(immutableParams_.rebalancer) != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        require(admin != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        require(mutableParams_.tickSpacing < TickMath.MAX_TICK / 4, ExceptionsLibrary.LIMIT_OVERFLOW);

        {
            require(address(immutableParams_.erc20Vault) != address(0), ExceptionsLibrary.ADDRESS_ZERO);
            address[] memory erc20VaultTokens = immutableParams_.erc20Vault.vaultTokens();
            require(erc20VaultTokens.length == 2, ExceptionsLibrary.INVALID_LENGTH);
            require(erc20VaultTokens[0] == immutableParams_.token0, ExceptionsLibrary.INVARIANT);
            require(erc20VaultTokens[1] == immutableParams_.token1, ExceptionsLibrary.INVARIANT);
        }

        {
            require(address(immutableParams_.uniV3Vault) != address(0), ExceptionsLibrary.ADDRESS_ZERO);
            address[] memory uniV3VaultTokens = immutableParams_.uniV3Vault.vaultTokens();
            require(uniV3VaultTokens.length == 2, ExceptionsLibrary.INVALID_LENGTH);
            require(uniV3VaultTokens[0] == immutableParams_.token0, ExceptionsLibrary.INVARIANT);
            require(uniV3VaultTokens[1] == immutableParams_.token1, ExceptionsLibrary.INVARIANT);
        }

        immutableParams_.rebalancer = immutableParams_.rebalancer.createRebalancer(address(this));
        immutableParams = immutableParams_;
        checkMutableParams(mutableParams_);
        mutableParams = mutableParams_;
        DefaultAccessControlLateInit.init(admin);
    }

    /// @notice creates the clone of the strategy
    /// @param immutableParams_ structure with all immutable params of the strategy
    /// @param mutableParams_ structure with all mutable params of strategy for initial set
    /// @param admin the addres of the admin of the strategy
    /// @return strategy new cloned strategy with for given params
    function createStrategy(
        ImmutableParams memory immutableParams_,
        MutableParams memory mutableParams_,
        address admin
    ) external returns (SinglePositionStrategy strategy) {
        strategy = SinglePositionStrategy(Clones.clone(address(this)));
        strategy.initialize(immutableParams_, mutableParams_, admin);
    }

    /// @notice updates parameters of the strategy. Can be called only by admin
    /// @param mutableParams_ the new parameters
    function updateMutableParams(MutableParams memory mutableParams_) external {
        _requireAdmin();
        checkMutableParams(mutableParams_);
        mutableParams = mutableParams_;
        emit UpdateMutableParams(tx.origin, msg.sender, mutableParams_);
    }

    function getData(ImmutableParams memory immutableParams_)
        public
        view
        returns (SinglePositionRebalancer.StrategyData memory data)
    {
        MutableParams memory mutableParams_ = mutableParams;
        SinglePositionRebalancer.Interval memory interval_ = interval;

        address[] memory tokens = new address[](2);
        tokens[0] = immutableParams_.token0;
        tokens[1] = immutableParams_.token1;
        data = SinglePositionRebalancer.StrategyData({
            lowerTick: interval_.lowerTick,
            upperTick: interval_.upperTick,
            maxTickDeviation: mutableParams_.maxTickDeviation,
            tickSpacing: mutableParams_.tickSpacing,
            swapFee: mutableParams_.swapFee,
            averageTickTimespan: mutableParams_.averageTickTimespan,
            erc20Vault: immutableParams_.erc20Vault,
            uniV3Vault: immutableParams_.uniV3Vault,
            router: immutableParams_.router,
            amount0ForMint: mutableParams_.amount0ForMint,
            amount1ForMint: mutableParams_.amount1ForMint,
            erc20CapitalRatioD: mutableParams_.erc20CapitalRatioD,
            swapSlippageD: mutableParams_.swapSlippageD,
            tokens: tokens
        });
    }

    /// @notice rebalance method. Need to be called if the new position is needed
    /// @param restrictions the restrictions of the amount of tokens to be transferred and positions to be minted
    /// @return actualAmounts actual transferred token amounts and minted positions
    function rebalance(SinglePositionRebalancer.Restrictions memory restrictions)
        external
        returns (SinglePositionRebalancer.Restrictions memory actualAmounts)
    {
        _requireAtLeastOperator();
        ImmutableParams memory immutableParams_ = immutableParams;
        SinglePositionRebalancer.StrategyData memory data = getData(immutableParams_);
        actualAmounts = SinglePositionRebalancer(immutableParams_.rebalancer).processRebalance(data, restrictions);
        if (actualAmounts.newInterval.lowerTick < actualAmounts.newInterval.upperTick) {
            interval = actualAmounts.newInterval;
        }

        emit Rebalance(msg.sender, tx.origin, restrictions, actualAmounts);
    }

    // -------------------  EXTERNAL, VIEW  -------------------

    /// @notice the function checks that mutableParams_ pass the necessary checks
    /// @param mutableParams_ params to be checked
    function checkMutableParams(MutableParams memory mutableParams_) public pure {
        require(mutableParams_.maxTickDeviation > 0, ExceptionsLibrary.LIMIT_UNDERFLOW);
        require(mutableParams_.averageTickTimespan > 0, ExceptionsLibrary.VALUE_ZERO);
        require(mutableParams_.erc20CapitalRatioD <= DENOMINATOR, ExceptionsLibrary.LIMIT_OVERFLOW);

        require(mutableParams_.amount0ForMint > 0, ExceptionsLibrary.VALUE_ZERO);
        require(mutableParams_.amount0ForMint <= MAX_MINTING_PARAMS, ExceptionsLibrary.LIMIT_OVERFLOW);
        require(mutableParams_.amount1ForMint > 0, ExceptionsLibrary.VALUE_ZERO);
        require(mutableParams_.amount1ForMint <= MAX_MINTING_PARAMS, ExceptionsLibrary.LIMIT_OVERFLOW);
    }

    // -------------------  INTERNAL, VIEW  -------------------

    function _contractName() internal pure override returns (bytes32) {
        return bytes32("SinglePositionStrategy");
    }

    function _contractVersion() internal pure override returns (bytes32) {
        return bytes32("1.0.0");
    }

    /// @notice Emitted when Strategy mutableParams are set.
    /// @param origin Origin of the transaction (tx.origin)
    /// @param sender Sender of the call (msg.sender)
    /// @param mutableParams Updated mutableParams
    event UpdateMutableParams(address indexed origin, address indexed sender, MutableParams mutableParams);

    /// @notice Emitted when Strategy mutableParams are set.
    /// @param origin Origin of the transaction (tx.origin)
    /// @param sender Sender of the call (msg.sender)
    /// @param expectedAmounts expected amounts to be transferred and positions to be minted
    /// @param actualAmounts actual transferred amounts and minted positions
    event Rebalance(
        address indexed sender,
        address indexed origin,
        SinglePositionRebalancer.Restrictions expectedAmounts,
        SinglePositionRebalancer.Restrictions actualAmounts
    );
}
