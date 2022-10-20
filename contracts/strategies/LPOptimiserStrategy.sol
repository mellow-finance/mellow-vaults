// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/vaults/IERC20Vault.sol";
import "../interfaces/vaults/IVoltzVault.sol";
import "../utils/DefaultAccessControl.sol";
import "../interfaces/utils/ILpCallback.sol";

contract LPOptimiserStrategy is DefaultAccessControl, ILpCallback {
    using SafeERC20 for IERC20;

    // IMMUTABLES
    address[] public _tokens;
    IERC20Vault public immutable _erc20Vault;

    // INTERNAL STATE
    IVoltzVault internal _vault;
    IMarginEngine internal _marginEngine;
    IPeriphery internal _periphery;
    IVAMM internal _vamm;

    // MUTABLE PARAMS
    uint256 internal _sigmaWad; // y (standard deviation parameter in wad 10^18)
    int256 internal _maxPossibleLowerBoundWad; // Maximum Possible Fixed Rate Lower bounds when initiating a rebalance
    int24 internal _logProximity; // x (closeness parameter in wad 10^18) in log base 1.0001

    // CONSTANTS
    uint256 internal constant MINIMUM_FIXED_RATE = 1e16;
    uint256 internal constant LOG_BASE = 1000100000000000000;

    // GETTERS AND SETTERS
    function setSigmaWad(uint256 sigmaWad) public {
        _requireAtLeastOperator();
        _sigmaWad = sigmaWad;
    }

    function setMaxPossibleLowerBound(int256 maxPossibleLowerBoundWad) public {
        _requireAtLeastOperator();
        _maxPossibleLowerBoundWad = maxPossibleLowerBoundWad;
    }

    function setLogProx(int24 logProx) public {
        _requireAtLeastOperator();
        require(logProx <= 0, ExceptionsLibrary.INVALID_VALUE);

        _logProximity = logProx;
    }

    function getSigmaWad() public view returns (uint256) {
        return _sigmaWad;
    }

    function getMaxPossibleLowerBound() public view returns (int256) {
        return _maxPossibleLowerBoundWad;
    }

    function getLogProx() public view returns (int24) {
        return _logProximity;
    }

    // EVENTS
    event RebalancedTicks(int24 newTickLower, int24 newTickUpper);

    event StrategyDeployment(IERC20Vault erc20vault_, IVoltzVault vault_, address admin_);

    /// @notice Constructor for a new contract
    /// @param erc20vault_ Reference to ERC20 Vault
    /// @param vault_ Reference to Voltz Vault
    constructor(
        IERC20Vault erc20vault_,
        IVoltzVault vault_,
        address admin_
    ) DefaultAccessControl(admin_) {
        _erc20Vault = erc20vault_;
        _vault = vault_;
        _marginEngine = IMarginEngine(vault_.marginEngine());
        _periphery = IPeriphery(vault_.periphery());
        _vamm = IVAMM(vault_.vamm());
        _tokens = vault_.vaultTokens();

        emit StrategyDeployment(erc20vault_, vault_, admin_);
    }

    /// @notice Get the current tick and position ticks and decide whether to rebalance
    /// @return bool True if rebalanceTicks should be called, false otherwise
    function rebalanceCheck() public view returns (bool) {
        // 1. Get current position, lower, and upper ticks form VoltzVault.sol
        IVoltzVault.TickRange memory currentPosition = _vault.currentPosition();

        // 2. Get current tick
        int24 currentTick = _periphery.getCurrentTick(_marginEngine);

        // 3. Compare current fixed rate to lower and upper bounds
        int24 logProximity = _logProximity;
        if (
            currentPosition.tickLower - logProximity <= currentTick &&
            currentTick <= currentPosition.tickUpper + logProximity
        ) {
            // 4.1. If current fixed rate is within bounds, return false (don't rebalance)
            return false;
        } else {
            // 4.2. If current fixed rate is outside bounds, return true (do rebalance)
            return true;
        }
    }

    /// @notice Get the nearest tick multiple given a tick and tick spacing
    /// @param newTick The tick to be rounded to the closest multiple of tickSpacing
    /// @param tickSpacing The tick spacing of the vamm being used for this strategy
    /// @return int24 The nearest tick multiple for newTick
    function nearestTickMultiple(int24 newTick, int24 tickSpacing) public pure returns (int24) {
        return
            (newTick /
                tickSpacing +
                ((((newTick % tickSpacing) + tickSpacing) % tickSpacing) >= tickSpacing / 2 ? int24(1) : int24(0))) *
            tickSpacing;
    }

    /// @notice Convert a fixed rate to a tick in wad
    /// @param fixedRateWad The fixed rate to be converted to a tick in wad
    /// @return int256 The tick in wad
    function convertFixedRateToTick(int256 fixedRateWad) public view returns (int256) {
        _requireAtLeastOperator();
        return -PRBMathSD59x18.div(PRBMathSD59x18.log2(int256(fixedRateWad)), PRBMathSD59x18.log2(int256(LOG_BASE)));
    }

    /// @notice Set new optimal tick range based on current twap tick given that we are using the offchain moving average of the fixed rate in the current iteration
    /// @param currentFixedRateWad currentFixedRate which is passed in from a 7-day rolling avg. historical fixed rate.
    /// @return newTickLower The new lower tick for the rebalanced position
    /// @return newTickUpper The new upper tick for the rebalanced position
    function rebalanceTicks(uint256 currentFixedRateWad) public returns (int24 newTickLower, int24 newTickUpper) {
        _requireAtLeastOperator();

        uint256 sigmaWad = _sigmaWad;

        // 0. Get tickspacing from vamm
        int24 tickSpacing = _vamm.tickSpacing();

        // 1. Get the new tick lower
        int256 deltaWad = int256(currentFixedRateWad) - int256(sigmaWad);
        int256 newFixedLowerWad;
        if (deltaWad > int256(MINIMUM_FIXED_RATE)) {
            // delta is greater than MINIMUM_FIXED_RATE (0.01) => choose delta
            int256 maxPossibleLowerBoundWad = _maxPossibleLowerBoundWad;
            if (deltaWad < maxPossibleLowerBoundWad) {
                newFixedLowerWad = deltaWad;
            } else {
                newFixedLowerWad = maxPossibleLowerBoundWad;
            }
        } else {
            // delta is less than or equal to MINIMUM_FIXED_RATE (0.01) => choose MINIMUM_FIXED_RATE (0.01)
            newFixedLowerWad = int256(MINIMUM_FIXED_RATE);
        }
        // 2. Get the new tick upper
        int256 newFixedUpperWad = newFixedLowerWad + 2 * int256(sigmaWad);

        // 3. Convert new fixed lower rate back to tick
        int256 newTickLowerWad = convertFixedRateToTick(newFixedUpperWad);

        // 4. Convert new fixed upper rate back to tick
        int256 newTickUpperWad = convertFixedRateToTick(newFixedLowerWad);

        // 5. Scale ticks from wad
        int256 newTickLowerExact = newTickLowerWad / 1e18;
        int256 newTickUpperExact = newTickUpperWad / 1e18;

        // 6. The underlying Voltz VAMM accepts only ticks multiple of tickSpacing
        // Hence, we get the nearest usable tick
        newTickLower = nearestTickMultiple(int24(newTickLowerExact), tickSpacing);
        newTickUpper = nearestTickMultiple(int24(newTickUpperExact), tickSpacing);

        // Call to VoltzVault contract to update the position lower and upper ticks
        _vault.rebalance(IVoltzVault.TickRange(newTickLower, newTickUpper));

        emit RebalancedTicks(newTickLower, newTickUpper);
        return (newTickLower, newTickUpper);
    }

    /// @notice Callback function called after for ERC20RootVault::deposit
    function depositCallback() external override {
        address[] memory tokens = _tokens;
        IERC20Vault erc20Vault = _erc20Vault;

        // 1. Get balance of erc20 vault
        uint256[] memory balances = new uint256[](1);
        balances[0] = IERC20(tokens[0]).balanceOf(address(erc20Vault));

        // 2. Pull balance from erc20 vault into voltz vault
        erc20Vault.pull(address(_vault), tokens, balances, "");
    }

    /// @notice Callback function called after for ERC20RootVault::withdraw
    function withdrawCallback() external override {
        // Do nothing on withdraw
    }
}
