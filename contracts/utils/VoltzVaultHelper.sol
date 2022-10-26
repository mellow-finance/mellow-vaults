// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../libraries/ExceptionsLibrary.sol";

import "../vaults/VoltzVault.sol";

contract VoltzVaultHelper {
    using SafeERC20 for IERC20;
    using SafeCastUni for uint128;
    using SafeCastUni for int128;
    using SafeCastUni for uint256;
    using SafeCastUni for int256;
    using PRBMathSD59x18 for int256;
    using PRBMathUD60x18 for uint256;

    /// @dev The Voltz Vault on Mellow
    VoltzVault private _vault;

    /// @dev The margin engine of Voltz Protocol
    IMarginEngine private _marginEngine;
    /// @dev The rate oracle of Voltz Protocol
    IRateOracle private _rateOracle;
    /// @dev The periphery of Voltz Protocol
    IPeriphery private _periphery;

    /// @dev The underlying token of the Voltz pool
    address private _underlyingToken;

    /// @dev The unix termStartTimestamp of the MarginEngine in Wad
    uint256 private _termStartTimestampWad;
    /// @dev The unix termEndTimestamp of the MarginEngine in Wad
    uint256 private _termEndTimestampWad;

    /// @dev The multiplier used to decide how much margin is left in partially unwound positions on Voltz (in wad)
    uint256 private _marginMultiplierPostUnwindWad;
    /// @dev The decimal delta used to compute lower and upper limits of estimated APY: (1 +/- delta) * estimatedAPY (in wad)
    uint256 private _estimatedAPYDecimalDeltaWad;

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

    // -------------------  EXTERNAL, VIEW  -------------------

    /// @notice Returns the associated Voltz Vault contract
    function vault() external view returns (IVoltzVault) {
        return _vault;
    }

    /// @notice Returns the multiplier used to decide how much margin is
    /// @notice left in partially unwound positions on Voltz (in wad)
    function marginMultiplierPostUnwindWad() external view returns (uint256) {
        return _marginMultiplierPostUnwindWad;
    }

    /// @notice Returns the decimal delta used to compute lower and upper limits of
    /// @notice estimated APY: (1 +/- delta) * estimatedAPY (in wad)
    function estimatedAPYDecimalDeltaWad() external view returns (uint256) {
        return _estimatedAPYDecimalDeltaWad;
    }

    /// @notice Computes liqudity value for a given liquidity notional
    function getLiquidityFromNotional(int256 liquidityNotionalDelta) external view returns (uint128) {
        if (liquidityNotionalDelta != 0) {
            VoltzVault.TickRange memory currentPosition_ = _vault.currentPosition();
            uint160 sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(currentPosition_.tickLower);
            uint160 sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(currentPosition_.tickUpper);

            uint128 liquidity = _periphery.getLiquidityForNotional(
                sqrtRatioAX96,
                sqrtRatioBX96,
                (liquidityNotionalDelta < 0)
                    ? (-liquidityNotionalDelta).toUint256()
                    : liquidityNotionalDelta.toUint256()
            );

            return liquidity;
        }

        return 0;
    }

    // -------------------  EXTERNAL, MUTATING  -------------------

    /// @notice Initializes the contract
    /// @dev It requires the vault to be already initialized. Can
    /// @dev only be called by the Voltz Vault Governance
    function initialize() external {
        require(address(_vault) == address(0), ExceptionsLibrary.INIT);

        VoltzVault vault_ = VoltzVault(msg.sender);
        _vault = vault_;

        IMarginEngine marginEngine = vault_.marginEngine();
        _marginEngine = marginEngine;

        _rateOracle = vault_.rateOracle();
        _periphery = vault_.periphery();

        _underlyingToken = address(marginEngine.underlyingToken());
        _termStartTimestampWad = marginEngine.termStartTimestampWad();
        _termEndTimestampWad = marginEngine.termEndTimestampWad();

        _marginMultiplierPostUnwindWad = vault_.marginMultiplierPostUnwindWad();
    }

    /// @notice Sets the multiplier used to decide how much margin is
    /// @notice left in partially unwound positions on Voltz (in wad)
    function setMarginMultiplierPostUnwindWad(uint256 marginMultiplierPostUnwindWad_) external onlyVault {
        _marginMultiplierPostUnwindWad = marginMultiplierPostUnwindWad_;
    }

    /// @notice Sets the decimal delta used to compute lower and upper limits of
    /// @notice estimated APY: (1 +/- delta) * estimatedAPY (in wad)
    function setEstimatedAPYDecimalDeltaWad(uint256 estimatedAPYDecimalDeltaWad_) external onlyVault {
        _estimatedAPYDecimalDeltaWad = estimatedAPYDecimalDeltaWad_;
    }

    /// @notice Calculates the TVL value
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
    ) external returns (int256 tvl) {
        VoltzVault vault_ = _vault;
        VoltzVault.TickRange memory currentPosition = vault_.currentPosition();

        // Calculate estimated variable factor between start and end
        uint256 estimatedVariableFactorStartEndWad;
        estimatedVariableFactorStartEndWad = _estimateVariableFactor();

        Position.Info memory currentPositionInfo_ = _marginEngine.getPosition(
            address(vault_),
            currentPosition.tickLower,
            currentPosition.tickUpper
        );

        tvl = IERC20(_underlyingToken).balanceOf(address(vault_)).toInt256();

        // Aggregate estimated settlement cashflows into TVL
        tvl +=
            calculateSettlementCashflow(
                aggregatedInactiveFixedTokenBalance + currentPositionInfo_.fixedTokenBalance,
                fixedFactor(_termStartTimestampWad, _termEndTimestampWad),
                aggregatedInactiveVariableTokenBalance + currentPositionInfo_.variableTokenBalance,
                estimatedVariableFactorStartEndWad
            ) +
            aggregatedInactiveMargin +
            currentPositionInfo_.margin;
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
        VoltzVault vault_ = _vault;
        VoltzVault.TickRange memory currentPosition = vault_.currentPosition();
        if (currentPositionInfo_.variableTokenBalance != 0) {
            // keep k * initial margin requirement, withdraw the rest
            // need to track to redeem the rest at maturity
            uint256 positionMarginRequirementInitial = _marginEngine.getPositionMarginRequirement(
                address(vault_),
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

    // -------------------  INTERNAL, MUTATING  -------------------

    /// @notice Estimates the variable factor from the start
    /// @notice to the end of the pool
    function _estimateVariableFactor() internal returns (uint256 estimatedVariableFactorStartEndWad) {
        uint256 termCurrentTimestampWad = Time.blockTimestampScaled();
        uint256 termEndTimestampWad = _termEndTimestampWad;
        if (termCurrentTimestampWad > termEndTimestampWad) {
            termCurrentTimestampWad = termEndTimestampWad;
        }

        uint256 variableFactorStartCurrentWad = _rateOracle.variableFactorNoCache(
            _termStartTimestampWad,
            termCurrentTimestampWad
        );

        uint256 historicalAPYWad = _marginEngine.getHistoricalApy();
        uint256 estimatedVariableFactorCurrentEndWad = historicalAPYWad.mul(
            accrualFact(termEndTimestampWad - termCurrentTimestampWad)
        );

        // Estimated Variable Factor
        estimatedVariableFactorStartEndWad = variableFactorStartCurrentWad + estimatedVariableFactorCurrentEndWad;
    }
}
