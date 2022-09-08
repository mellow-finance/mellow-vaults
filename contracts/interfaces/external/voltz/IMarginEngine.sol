// SPDX-License-Identifier: Apache-2.0

pragma solidity =0.8.9;
import "./IVAMM.sol";
import "./IPositionStructs.sol";
import "./utils/Position.sol";
import "./rate_oracles/IRateOracle.sol";
import "./fcms/IFCM.sol";
import "./IFactory.sol";
import "./IERC20Minimal.sol";
import "./utils/CustomErrors.sol";

interface IMarginEngine is IPositionStructs, CustomErrors {
    // structs

    function setPausability(bool state) external;

    struct MarginCalculatorParameters {
        /// @dev Upper bound of the underlying pool (e.g. Aave v2 USDC lending pool) APY from the initiation of the IRS AMM and until its maturity (18 decimals fixed point number)
        uint256 apyUpperMultiplierWad;
        /// @dev Lower bound of the underlying pool (e.g. Aave v2 USDC lending pool) APY from the initiation of the IRS AMM and until its maturity (18 decimals)
        uint256 apyLowerMultiplierWad;
        /// @dev The volatility of the underlying pool APY (settable by the owner of the Margin Engine) (18 decimals)
        int256 sigmaSquaredWad;
        /// @dev Margin Engine Parameter estimated via CIR model calibration (for details refer to litepaper) (18 decimals)
        int256 alphaWad;
        /// @dev Margin Engine Parameter estimated via CIR model calibration (for details refer to litepaper) (18 decimals)
        int256 betaWad;
        /// @dev Standard normal critical value used in the computation of the Upper APY Bound of the underlying pool
        int256 xiUpperWad;
        /// @dev Standard normal critical value used in the computation of the Lower APY Bound of the underlying pool
        int256 xiLowerWad;
        /// @dev Max term possible for a Voltz IRS AMM in seconds (18 decimals)
        int256 tMaxWad;
        /// @dev multiplier of the starting fixed rate (refer to the litepaper) if simulating a counterfactual fixed taker unwind (moving to the left along the VAMM) for purposes of calculating liquidation margin requirement
        uint256 devMulLeftUnwindLMWad;
        /// @dev multiplier of the starting fixed rate (refer to the litepaper) if simulating a counterfactual variable taker unwind (moving to the right along the VAMM) for purposes of calculating liquidation margin requirement
        uint256 devMulRightUnwindLMWad;
        /// @dev same as devMulLeftUnwindLMWad but for purposes of calculating the initial margin requirement
        uint256 devMulLeftUnwindIMWad;
        /// @dev same as devMulRightUnwindLMWad but for purposes of calculating the initial margin requirement
        uint256 devMulRightUnwindIMWad;
        /// @dev r_min from the litepaper eq. 11 for a scenario where counterfactual is a simulated fixed taker unwind (left unwind along the VAMM), used for liquidation margin calculation
        uint256 fixedRateDeviationMinLeftUnwindLMWad;
        /// @dev r_min from the litepaper eq. 11 for a scenario where counterfactual is a simulated variable taker unwind (right unwind along the VAMM), used for liquidation margin calculation
        uint256 fixedRateDeviationMinRightUnwindLMWad;
        /// @dev same as fixedRateDeviationMinLeftUnwindLMWad but for Initial Margin Requirement
        uint256 fixedRateDeviationMinLeftUnwindIMWad;
        /// @dev same as fixedRateDeviationMinRightUnwindLMWad but for Initial Margin Requirement
        uint256 fixedRateDeviationMinRightUnwindIMWad;
        /// @dev gamma from eqn. 12 [append this logic to the litepaper] from the litepaper, gamma is an adjustable parameter necessary to calculate scaled deviations to the fixed rate in counterfactual unwinds for minimum margin requirement calculations
        uint256 gammaWad;
        /// @dev settable parameter that ensures that minimumMarginRequirement is always above or equal to the minMarginToIncentiviseLiquidators which ensures there is always sufficient incentive for liquidators to liquidate positions given the fact their income is a proportion of position margin
        uint256 minMarginToIncentiviseLiquidators;
    }

    // Events
    event HistoricalApyWindowSetting(uint256 secondsAgo);
    event CacheMaxAgeSetting(uint256 cacheMaxAgeInSeconds);
    event RateOracle(uint256 cacheMaxAgeInSeconds);

    event ProtocolCollection(
        address sender,
        address indexed recipient,
        uint256 amount
    );
    event LiquidatorRewardSetting(uint256 liquidatorRewardWad);

    event VAMMSetting(IVAMM indexed vamm);

    event RateOracleSetting(IRateOracle indexed rateOracle);

    event FCMSetting(IFCM indexed fcm);

    event MarginCalculatorParametersSetting(
        MarginCalculatorParameters marginCalculatorParameters
    );

    event PositionMarginUpdate(
        address sender,
        address indexed owner,
        int24 indexed tickLower,
        int24 indexed tickUpper,
        int256 marginDelta
    );

    event HistoricalApy(uint256 value);

    event PositionSettlement(
        address indexed owner,
        int24 indexed tickLower,
        int24 indexed tickUpper,
        int256 settlementCashflow
    );

    event PositionLiquidation(
        address indexed owner,
        int24 indexed tickLower,
        int24 indexed tickUpper,
        address liquidator,
        int256 notionalUnwound,
        uint256 liquidatorReward
    );

    event PositionUpdate(
        address indexed owner,
        int24 indexed tickLower,
        int24 indexed tickUpper,
        uint128 _liquidity,
        int256 margin,
        int256 fixedTokenBalance,
        int256 variableTokenBalance,
        uint256 accumulatedFees
    );

    /// @dev emitted after the _isAlpha boolean is updated by the owner of the Margin Engine
    /// @dev _isAlpha boolean dictates whether the Margin Engine is in the Alpha State, i.e. margin updates can only be done via the periphery
    /// @dev additionally, the periphery has the logic to take care of lp margin caps in the Alpha State phase of the Margin Engine
    /// @dev __isAlpha is the newly set value for the _isAlpha boolean
    event IsAlpha(bool __isAlpha);

    // immutables

    /// @notice The Full Collateralisation Module (FCM)
    /// @dev The FCM is a smart contract that acts as an intermediary Position between the Voltz Core and traders who wish to take fully collateralised fixed taker positions
    /// @dev An example FCM is the AaveFCM.sol module which inherits from the IFCM interface, it lets fixed takers deposit underlying yield bearing tokens (e.g.) aUSDC as margin to enter into a fixed taker swap without the need to worry about liquidations
    /// @dev since the MarginEngine is confident the FCM is always fully collateralised, it does not let liquidators liquidate the FCM Position
    /// @return The Full Collateralisation Module linked to the MarginEngine
    function fcm() external view returns (IFCM);

    /// @notice The Factory
    /// @dev the factory that deployed the master Margin Engine
    function factory() external view returns (IFactory);

    /// @notice The address of the underlying (non-yield bearing) token - e.g. USDC
    /// @return The underlying ERC20 token (e.g. USDC)
    function underlyingToken() external view returns (IERC20Minimal);

    /// @notice The rateOracle contract which lets the protocol access historical apys in the yield bearing pools it is built on top of
    /// @return The underlying ERC20 token (e.g. USDC)
    function rateOracle() external view returns (IRateOracle);

    /// @notice The unix termStartTimestamp of the MarginEngine in Wad
    /// @return Term Start Timestamp in Wad
    function termStartTimestampWad() external view returns (uint256);

    /// @notice The unix termEndTimestamp of the MarginEngine in Wad
    /// @return Term End Timestamp in Wad
    function termEndTimestampWad() external view returns (uint256);

    /// @dev "constructor" for proxy instances
    function initialize(
        IERC20Minimal __underlyingToken,
        IRateOracle __rateOracle,
        uint256 __termStartTimestampWad,
        uint256 __termEndTimestampWad
    ) external;

    // view functions

    /// @notice The liquidator Reward Percentage (in Wad)
    /// @dev liquidatorReward (in wad) is the percentage of the margin (of a liquidated position) that is sent to the liquidator
    /// @dev following a successful liquidation that results in a trader/position unwind; example value:  2 * 10**16 => 2% of position margin is used to cover liquidator reward
    /// @return Liquidator Reward in Wad
    function liquidatorRewardWad() external view returns (uint256);

    /// @notice VAMM (Virtual Automated Market Maker) linked to the MarginEngine
    /// @dev The VAMM is responsible for pricing only (determining the effective fixed rate at which a given Interest Rate Swap notional will be executed)
    /// @return The VAMM
    function vamm() external view returns (IVAMM);

    /// @return If true, the Margin Engine Proxy is currently in alpha state, hence margin updates of LPs can only be done via the periphery. If false, lps can directly update their margin via Margin Engine.
    function isAlpha() external view returns (bool);

    /// @notice Returns the information about a position by the position's key
    /// @param _owner The address of the position owner
    /// @param _tickLower The lower tick boundary of the position
    /// @param _tickUpper The upper tick boundary of the position
    /// Returns position The Position.Info corresponding to the requested position
    function getPosition(
        address _owner,
        int24 _tickLower,
        int24 _tickUpper
    ) external returns (Position.Info memory position);

    /// @notice Gets the look-back window size that's used to request the historical APY from the rate Oracle
    /// @dev The historical APY of the Rate Oracle is necessary for MarginEngine computations
    /// @dev The look-back window is seconds from the current timestamp
    /// @dev This value is only settable by the the Factory owner and may be unique for each MarginEngine
    /// @dev When setting secondAgo, the setter needs to take into consideration the underlying volatility of the APYs in the reference yield-bearing pool (e.g. Aave v2 USDC)
    function lookbackWindowInSeconds() external view returns (uint256);

    // non-view functions

    /// @notice Sets secondsAgo: The look-back window size used to calculate the historical APY for margin purposes
    /// @param _secondsAgo the duration of the lookback window in seconds
    /// @dev Can only be set by the Factory Owner
    function setLookbackWindowInSeconds(uint256 _secondsAgo) external;

    /// @notice Set the MarginCalculatorParameters (each margin engine can have its own custom set of margin calculator parameters)
    /// @param _marginCalculatorParameters the MarginCalculatorParameters to set
    /// @dev marginCalculatorParameteres is of type MarginCalculatorParameters (refer to the definition of the struct for elaboration on what each parameter means)
    function setMarginCalculatorParameters(
        MarginCalculatorParameters memory _marginCalculatorParameters
    ) external;

    /// @notice Sets the liquidator reward: proportion of liquidated position's margin paid as a reward to the liquidator
    function setLiquidatorReward(uint256 _liquidatorRewardWad) external;

    /// @notice Function that sets the _isAlpha state variable, if it is set to true the protocol is in the Alpha State
    /// @dev if the Margin Engine is at the alpha state, lp margin updates can only be done via the periphery which in turn takes care of margin caps for the LPs
    /// @dev this function can only be called by the owner of the VAMM
    function setIsAlpha(bool __isAlpha) external;

    /// @notice updates the margin account of a position which can be uniquily identified with its _owner, tickLower, tickUpper
    /// @dev if the position has positive liquidity then before the margin update, we call the updatePositionTokenBalancesAndAccountForFees functon that calculates up to date
    /// @dev margin, fixed and variable token balances by taking into account the fee income from their tick range and fixed and variable deltas settled along their tick range
    /// @dev marginDelta is the delta applied to the current margin of a position, if the marginDelta is negative, the position is withdrawing margin, if the marginDelta is positive, the position is depositing funds in terms of the underlying tokens
    /// @dev if marginDelta is negative, we need to check if the msg.sender is either the _owner of the position or the msg.sender is apporved by the _owner to act on their behalf in Voltz Protocol
    /// @dev the approval logic is implemented in the Factory.sol
    /// @dev if marginDelta is negative, we additionally need to check if post the initial margin requirement is still satisfied post withdrawal
    /// @dev if marginDelta is positive, the depositor of the margin is either the msg.sender or the owner who interacted through an approved peripheral contract
    function updatePositionMargin(
        address _owner,
        int24 _tickLower,
        int24 _tickUpper,
        int256 marginDelta
    ) external;

    /// @notice Settles a Position
    /// @dev Can be called by anyone
    /// @dev A position cannot be settled before maturity
    /// @dev Steps to settle a position:
    /// @dev 1. Retrieve the current fixed and variable token growth inside the tick range of a position
    /// @dev 2. Calculate accumulated fixed and variable balances of the position since the last mint/poke/burn
    /// @dev 3. Update the postion's fixed and variable token balances
    /// @dev 4. Update the postion's fixed and varaible token growth inside last to enable future updates
    /// @dev 5. Calculates the settlement cashflow from all of the IRS contracts the position has entered since entering the AMM
    /// @dev 6. Updates the fixed and variable token balances of the position to be zero, adds the settlement cashflow to the position's current margin
    function settlePosition(
        address _owner,
        int24 _tickLower,
        int24 _tickUpper
    ) external;

    /// @notice Liquidate a Position
    /// @dev Steps to liquidate: update position's fixed and variable token balances to account for balances accumulated throughout the trades made since the last mint/burn/poke,
    /// @dev Check if the position is liquidatable by calling the isLiquidatablePosition function of the calculator, revert if that is not the case,
    /// @dev Calculate the liquidation reward = current margin of the position * liquidatorReward, subtract the liquidator reward from the position margin,
    /// @dev Burn the position's liquidity, unwind unnetted fixed and variable balances of a position, transfer the reward to the liquidator
    function liquidatePosition(
        address _owner,
        int24 _tickLower,
        int24 _tickUpper
    ) external returns (uint256);

    /// @notice Update a Position post VAMM induced mint or burn
    /// @dev Steps taken:
    /// @dev 1. Update position liquidity based on params.liquidityDelta
    /// @dev 2. Update fixed and variable token balances of the position based on how much has been accumulated since the last mint/burn/poke
    /// @dev 3. Update position's margin by taking into account the position accumulated fees since the last mint/burn/poke
    /// @dev 4. Update fixed and variable token growth + fee growth in the position info struct for future interactions with the position
    /// @param _params necessary for the purposes of referencing the position being updated (owner, tickLower, tickUpper, _) and the liquidity delta that needs to be applied to position._liquidity
    function updatePositionPostVAMMInducedMintBurn(
        IPositionStructs.ModifyPositionParams memory _params
    ) external returns (int256 _positionMarginRequirement);

    // @notive Update a position post VAMM induced swap
    /// @dev Since every position can also engage in swaps with the VAMM, this function needs to be invoked after non-external calls are made to the VAMM's swap function
    /// @dev This purpose of this function is to:
    /// @dev 1. updatePositionTokenBalancesAndAccountForFees
    /// @dev 2. update position margin to account for fees paid to execute the swap
    /// @dev 3. calculate the position margin requrement given the swap, check if the position marigin satisfies the most up to date requirement
    /// @dev 4. if all the requirements are satisfied then position gets updated to take into account the swap that it just entered, if the minimum margin requirement is not satisfied then the transaction will revert
    function updatePositionPostVAMMInducedSwap(
        address _owner,
        int24 _tickLower,
        int24 _tickUpper,
        int256 _fixedTokenDelta,
        int256 _variableTokenDelta,
        uint256 _cumulativeFeeIncurred,
        int256 _fixedTokenDeltaUnbalanced
    ) external returns (int256 _positionMarginRequirement);

    /// @notice function that can only be called by the owner enables collection of protocol generated fees from any give margin engine
    /// @param _recipient the address which collects the protocol generated fees
    /// @param _amount the amount in terms of underlying tokens collected from the protocol's earnings
    function collectProtocol(address _recipient, uint256 _amount) external;

    /// @notice sets the Virtual Automated Market Maker (VAMM) attached to the MarginEngine
    /// @dev the VAMM is responsible for price discovery, whereas the management of the underlying collateral and liquidations are handled by the Margin Engine
    function setVAMM(IVAMM _vAMM) external;

    /// @notice sets the Virtual Automated Market Maker (VAMM) attached to the MarginEngine
    /// @dev the VAMM is responsible for price discovery, whereas the management of the underlying collateral and liquidations are handled by the Margin Engine
    function setRateOracle(IRateOracle __rateOracle) external;

    /// @notice sets the Full Collateralisation Module
    function setFCM(IFCM _newFCM) external;

    /// @notice transfers margin in terms of underlying tokens to a trader from the Full Collateralisation Module
    /// @dev post maturity date of the MarginEngine, the traders from the Full Collateralisation module will be able to settle with the MarginEngine
    /// @dev to ensure their fixed yield is guaranteed, in order to collect the funds from the MarginEngine, the FCM needs to invoke the transferMarginToFCMTrader function whcih is only callable by the FCM attached to a particular Margin Engine
    function transferMarginToFCMTrader(address _account, uint256 _marginDelta)
        external;

    /// @notice Gets the maximum age of the cached historical APY value can be without being refreshed
    function cacheMaxAgeInSeconds() external view returns (uint256);

    /// @notice Sets the maximum age that the cached historical APY value
    /// @param _cacheMaxAgeInSeconds The new maximum age that the historical APY cache can be before being considered stale
    function setCacheMaxAgeInSeconds(uint256 _cacheMaxAgeInSeconds) external;

    /// @notice Get Historical APY
    /// @dev The lookback window used by this function is determined by `lookbackWindowInSeconds`
    /// @dev refresh the historical apy cache if necessary
    /// @return historicalAPY (Wad)
    function getHistoricalApy() external returns (uint256);

    /// @notice Computes the historical APY value of the RateOracle, without updating the cached value
    /// @dev The lookback window used by this function is determined by `lookbackWindowInSeconds`
    function getHistoricalApyReadOnly() external view returns (uint256);

    function getPositionMarginRequirement(
        address _recipient,
        int24 _tickLower,
        int24 _tickUpper,
        bool _isLM
    ) external returns (uint256);
}
