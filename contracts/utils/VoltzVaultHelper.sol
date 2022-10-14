// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "@prb/math/contracts/PRBMathSD59x18.sol";
import "@prb/math/contracts/PRBMathUD60x18.sol";

import "../libraries/ExceptionsLibrary.sol";

import "../vaults/VoltzVaultGovernance.sol";
import "../vaults/VoltzVault.sol";

import "../interfaces/external/voltz/IMarginEngine.sol";
import "../interfaces/external/voltz/rate_oracles/IRateOracle.sol";
import "../interfaces/external/voltz/IPeriphery.sol";

import "../interfaces/external/voltz/utils/Time.sol";
import "../interfaces/external/voltz/utils/Position.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "hardhat/console.sol";

contract VoltzVaultHelper {
    using SafeERC20 for IERC20;
    using SafeCastUni for uint128;
    using SafeCastUni for int128;
    using SafeCastUni for uint256;
    using SafeCastUni for int256;
    using PRBMathSD59x18 for int256;
    using PRBMathUD60x18 for uint256;

    /// @dev The Voltz Vault on Mellow
    VoltzVault public _vault;

    /// @dev The margin engine of Voltz Protocol
    IMarginEngine public _marginEngine;
    /// @dev The rate oracle of Voltz Protocol
    IRateOracle public _rateOracle;
    /// @dev The periphery of Voltz Protocol
    IPeriphery public _periphery;

    /// @dev The underlying token of the Voltz pool
    address public _underlyingToken;

    /// @dev The unix termStartTimestamp of the MarginEngine in Wad
    uint256 _termStartTimestampWad;
    /// @dev The unix termEndTimestamp of the MarginEngine in Wad
    uint256 _termEndTimestampWad;

    /// @dev The multiplier used to decide how much margin is left in partially unwound positions on Voltz (in wad)
    uint256 public _marginMultiplierPostUnwindWad;
    /// @dev The lookback window used to compute the historical APY that estimates the APY from current to the end of Voltz pool (in seconds)
    uint256 public _lookbackWindowInSeconds;
    /// @dev The decimal delta used to compute lower and upper limits of estimated APY: (1 +/- delta) * estimatedAPY (in wad)
    uint256 public _estimatedAPYDecimalDeltaWad;

    uint256 public constant SECONDS_IN_YEAR_IN_WAD = 31536000e18;
    uint256 public constant ONE_HUNDRED_IN_WAD = 100e18;

    modifier onlyVault() {
        require(msg.sender == address(_vault), "Only Vault");
        _;
    }

    // -------------------  PUBLIC, PURE  -------------------

    /// @notice Calculate the remaining cashflow to settle a position
    /// @param fixedTokenBalance The current balance of the fixed side of the position
    /// @param fixedFactorStartEndWad The fixed factor between the start and end of the pool (in wad)
    /// @param variableTokenBalance The current balance of the variable side of the position
    /// @param variableFactorStartEndWad The factor that expresses the variable rate between the start and end of the pool (in wad)
    /// @return cashflow The remaining cashflow of the position
    function calculateSettlementCashflow(
        int256 fixedTokenBalance,
        uint256 fixedFactorStartEndWad,
        int256 variableTokenBalance,
        uint256 variableFactorStartEndWad
    ) public pure returns (int256 cashflow) {
        // Fixed Cashflow
        int256 fixedTokenBalanceWad = fixedTokenBalance.fromInt();
        int256 fixedCashflowBalanceWad = fixedTokenBalanceWad.mul(int256(fixedFactorStartEndWad));
        int256 fixedCashflowBalance = fixedCashflowBalanceWad.toInt();

        // Variable Cashflow
        int256 variableTokenBalanceWad = variableTokenBalance.fromInt();
        int256 variableCashflowBalanceWad = variableTokenBalanceWad.mul(int256(variableFactorStartEndWad));
        int256 variableCashflowBalance = variableCashflowBalanceWad.toInt();

        cashflow = fixedCashflowBalance + variableCashflowBalance;
    }

    /// @notice Divide a given time in seconds by the number of seconds in a year
    /// @param timeInSecondsAsWad A time in seconds in Wad (i.e. scaled up by 10^18)
    /// @return timeInYearsWad An annualised factor of timeInSeconds, also in Wad
    function accrualFact(uint256 timeInSecondsAsWad) public pure returns (uint256 timeInYearsWad) {
        timeInYearsWad = timeInSecondsAsWad.div(SECONDS_IN_YEAR_IN_WAD);
    }

    /// @notice Calculate the fixed factor for a position - that is, the percentage earned over
    /// @notice the specified period of time, assuming 1% per year
    /// @param termStartTimestampWad When does the period of time begin, in wei-seconds
    /// @param termEndTimestampWad When does the period of time end, in wei-seconds
    /// @return fixedFactorWad The fixed factor for the position (in Wad)
    function fixedFactor(uint256 termStartTimestampWad, uint256 termEndTimestampWad)
        public
        pure
        returns (uint256 fixedFactorWad)
    {
        require(termStartTimestampWad <= termEndTimestampWad, ExceptionsLibrary.TIMESTAMP);
        uint256 timeInSecondsWad = termEndTimestampWad - termStartTimestampWad;
        fixedFactorWad = accrualFact(timeInSecondsWad).div(ONE_HUNDRED_IN_WAD);
    }

    // -------------------  EXTERNAL, MUTATING  -------------------

    /// @notice Initializes the contract
    /// @dev It requires the vault to be already initialized. Can
    /// @dev only be called by the Voltz Vault Governance
    function initialize() external {
        require(address(_vault) == address(0), ExceptionsLibrary.INIT);
        _vault = VoltzVault(msg.sender);

        _marginEngine = _vault.marginEngine();
        _rateOracle = _vault.rateOracle();
        _periphery = _vault.periphery();

        _underlyingToken = address(_marginEngine.underlyingToken());

        _termStartTimestampWad = _marginEngine.termStartTimestampWad();
        _termEndTimestampWad = _marginEngine.termEndTimestampWad();

        _marginMultiplierPostUnwindWad = _vault.marginMultiplierPostUnwindWad();
        _lookbackWindowInSeconds = _vault.lookbackWindow();
        _estimatedAPYDecimalDeltaWad = _vault.estimatedAPYDecimalDeltaWad();
    }

    /// @notice Sets the multiplier used to decide how much margin is
    /// @notice left in partially unwound positions on Voltz (in wad)
    function setMarginMultiplierPostUnwindWad(uint256 marginMultiplierPostUnwindWad_) external onlyVault {
        _marginMultiplierPostUnwindWad = marginMultiplierPostUnwindWad_;
    }

    /// @notice Sets the lookback window used to compute the historical APY that
    /// @notice estimates the APY from current to the end of Voltz pool (in seconds)
    function setLookbackWindow(uint256 lookbackWindowInSeconds_) external onlyVault {
        _lookbackWindowInSeconds = lookbackWindowInSeconds_;
    }

    /// @notice Sets the decimal delta used to compute lower and upper limits of
    /// @notice estimated APY: (1 +/- delta) * estimatedAPY (in wad)
    function setEstimatedAPYDecimalDeltaWad(uint256 estimatedAPYDecimalDeltaWad_) external onlyVault {
        _estimatedAPYDecimalDeltaWad = estimatedAPYDecimalDeltaWad_;
    }

    /// @notice Calculates the TVL values
    /// @param aggregatedInactiveFixedTokenBalance Sum of fixed token balances of all
    /// positions in the trackedPositions array, apart from the balance of the currently
    /// active position
    /// @param aggregatedInactiveVariableTokenBalance Sum of variable token balances of all
    /// positions in the trackedPositions array, apart from the balance of the currently
    /// active position
    /// @param aggregatedInactiveMargin Sum of margins of all positions in the trackedPositions
    /// array apart from the margin of the currently active position
    function calculateTVL(
        int256 aggregatedInactiveFixedTokenBalance,
        int256 aggregatedInactiveVariableTokenBalance,
        int256 aggregatedInactiveMargin
    ) external returns (int256 minTVL, int256 maxTVL) {
        VoltzVault.TickRange memory currentPosition = _vault.currentPosition();

        // Calculate estimated variable factor between start and end
        uint256 estimatedVariableFactorStartEndLowerWad;
        uint256 estimatedVariableFactorStartEndUpperWad;
        (
            estimatedVariableFactorStartEndLowerWad,
            estimatedVariableFactorStartEndUpperWad
        ) = _estimateVariableFactorLowerUpper();

        Position.Info memory currentPositionInfo_ = _marginEngine.getPosition(
            address(_vault),
            currentPosition.tickLower,
            currentPosition.tickUpper
        );

        minTVL = IERC20(_underlyingToken).balanceOf(address(_vault)).toInt256();
        maxTVL = minTVL;

        // Aggregate estimated settlement cashflows into TVL
        minTVL +=
            calculateSettlementCashflow(
                aggregatedInactiveFixedTokenBalance + currentPositionInfo_.fixedTokenBalance,
                fixedFactor(_termStartTimestampWad, _termEndTimestampWad),
                aggregatedInactiveVariableTokenBalance + currentPositionInfo_.variableTokenBalance,
                estimatedVariableFactorStartEndLowerWad
            ) +
            aggregatedInactiveMargin +
            currentPositionInfo_.margin;

        maxTVL +=
            calculateSettlementCashflow(
                aggregatedInactiveFixedTokenBalance + currentPositionInfo_.fixedTokenBalance,
                fixedFactor(_termStartTimestampWad, _termEndTimestampWad),
                aggregatedInactiveVariableTokenBalance + currentPositionInfo_.variableTokenBalance,
                estimatedVariableFactorStartEndUpperWad
            ) +
            aggregatedInactiveMargin +
            currentPositionInfo_.margin;

        if (minTVL > maxTVL) {
            (minTVL, maxTVL) = (maxTVL, minTVL);
        }
    }

    /// @notice Calculates the margin that must be kept in the
    /// @notice current position of the Vault
    /// @param currentPositionInfo_ The Info of the current position
    /// @return trackPosition Whether the current position must be tracked or not
    /// @return marginToKeep Margin that must be kept in the current position
    function getMarginToKeep(Position.Info memory currentPositionInfo_)
        external
        returns (bool trackPosition, uint256 marginToKeep)
    {
        VoltzVault.TickRange memory currentPosition = _vault.currentPosition();
        if (currentPositionInfo_.variableTokenBalance != 0) {
            // keep k * initial margin requirement, withdraw the rest
            // need to track to redeem the rest at maturity
            uint256 positionMarginRequirementInitial = _marginEngine.getPositionMarginRequirement(
                address(_vault),
                currentPosition.tickLower,
                currentPosition.tickUpper,
                false
            );

            marginToKeep = _marginMultiplierPostUnwindWad.mul(positionMarginRequirementInitial);

            if (marginToKeep <= positionMarginRequirementInitial) {
                marginToKeep = positionMarginRequirementInitial + 1;
            }

            trackPosition = true;
        } else {
            if (currentPositionInfo_.fixedTokenBalance > 0) {
                // withdraw all margin
                // need to track to redeem ft cashflow at maturity
                marginToKeep = 1;
                trackPosition = true;
            } else {
                // withdraw everything up to amount that covers negative ft
                // no need to track for later settlement
                // since vt = 0, margin requirement initial is equal to fixed cashflow
                uint256 fixedFactorValueWad = fixedFactor(_termStartTimestampWad, _termEndTimestampWad);
                uint256 positionMarginRequirementInitial = ((-currentPositionInfo_.fixedTokenBalance).toUint256() *
                    fixedFactorValueWad).toUint();
                marginToKeep = positionMarginRequirementInitial + 1;
            }
        }
    }

    /// @notice Returns Position.Info of current position
    function getVaultPosition(VoltzVault.TickRange memory position) external returns (Position.Info memory) {
        return _marginEngine.getPosition(address(_vault), position.tickLower, position.tickUpper);
    }

    // -------------------  INTERNAL, VIEW  -------------------

    /// @notice Estimates the lower and upper variable factors from the start
    /// @notice to the end of the pool
    function _estimateVariableFactorLowerUpper()
        internal
        view
        returns (uint256 estimatedVariableFactorStartEndLowerWad, uint256 estimatedVariableFactorStartEndUpperWad)
    {
        uint256 termCurrentTimestampWad = Time.blockTimestampScaled();
        if (termCurrentTimestampWad > _termEndTimestampWad) {
            termCurrentTimestampWad = _termEndTimestampWad;
        }

        uint256 variableFactorStartCurrentWad = _rateOracle.variableFactorNoCache(
            _termStartTimestampWad,
            termCurrentTimestampWad
        );

        // TO DO: call historical apy on margin engine
        uint256 historicalAPYWad = _rateOracle.getApyFromTo(
            termCurrentTimestampWad.toUint() - _lookbackWindowInSeconds,
            termCurrentTimestampWad.toUint()
        );
        uint256 estimatedVariableFactorCurrentEndWad = historicalAPYWad.mul(
            accrualFact(_termEndTimestampWad - termCurrentTimestampWad)
        );

        // Estimated Lower APY
        estimatedVariableFactorStartEndLowerWad =
            variableFactorStartCurrentWad +
            estimatedVariableFactorCurrentEndWad.mul(
                (_estimatedAPYDecimalDeltaWad <= PRBMathUD60x18.fromUint(1))
                    ? PRBMathUD60x18.fromUint(1) - _estimatedAPYDecimalDeltaWad
                    : 0
            );

        // Estimated Upper APY
        estimatedVariableFactorStartEndUpperWad =
            variableFactorStartCurrentWad +
            estimatedVariableFactorCurrentEndWad.mul(PRBMathUD60x18.fromUint(1) + _estimatedAPYDecimalDeltaWad);
    }
}
