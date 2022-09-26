// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/vaults/IERC20Vault.sol";
import "../interfaces/vaults/IVoltzVault.sol";
import "../interfaces/external/voltz/IMarginEngine.sol";
import "../interfaces/external/voltz/IPeriphery.sol";
import "../interfaces/external/voltz/IVAMM.sol";
import "../libraries/ExceptionsLibrary.sol";
import "../libraries/CommonLibrary.sol";
import "../libraries/external/FullMath.sol";
import "../utils/DefaultAccessControl.sol";
import "@prb/math/contracts/PRBMathSD59x18.sol";
import "hardhat/console.sol";

contract LPOptimiserStrategy is DefaultAccessControl {
    using SafeERC20 for IERC20;

    // IMMUTABLES
    address[] public _tokens;
    IERC20Vault public immutable _erc20Vault;

    // INTERNAL STATE

    IVoltzVault internal _vault;
    uint256[] internal _pullExistentials;
    IMarginEngine internal _marginEngine;
    IPeriphery internal _periphery;
    IVAMM internal _vamm;
    IVoltzVault.TickRange internal _currentPosition;

    // MUTABLE PARAMS

    uint256 internal _sigmaWad; // y (standard deviation parameter in wad 10^18)
    int256 internal _max_possible_lower_bound_wad; // should be in fixed rate

    int24 internal _logProximity; // x (closeness parameter in wad 10^18) in log base 1.0001
    int24 internal _currentTick;
    int24 internal _tickLower;
    int24 internal _tickUpper;
    int24 internal _tickSpacing;

    // GETTERS AND SETTERS

    function setSigmaWad(uint256 sigmaWad) public {
        _requireAtLeastOperator();
        _sigmaWad = sigmaWad;
    }

    // refactor max_possible_lower_bound_wad into camelCase
    function setMaxPossibleLowerBound(int256 max_possible_lower_bound_wad) public {
        _requireAtLeastOperator();
        _max_possible_lower_bound_wad = max_possible_lower_bound_wad;
    }

    function setLogProx(int24 logProx) public {
        _requireAtLeastOperator();
        _logProximity = logProx;
    }

    function getSigmaWad() public view returns (uint256) {
        return _sigmaWad;
    }

    function getMaxPossibleLowerBound() public view returns (int256) {
        return _max_possible_lower_bound_wad;
    }

    function getLogProx() public view returns (int24) {
        return _logProximity;
    }

    // EVENTS

    event Rebalanced(int24 newTickLowerMul, int24 newTickUpperMul);

    // Allows you to keep track of the smart contract activity in subgraph
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
        _currentPosition = vault_.currentPosition();
        _tokens = vault_.vaultTokens();
        _pullExistentials = vault_.pullExistentials();

        emit StrategyDeployment(erc20vault_, vault_, admin_);
    }

    function setConstants(
        int24 logProx,
        uint256 sigmaWad,
        int256 max_possible_lower_bound_wad,
        int24 tickSpacing
    ) public {
        _requireAtLeastOperator();
        _logProximity = logProx;
        _sigmaWad = sigmaWad;
        _max_possible_lower_bound_wad = max_possible_lower_bound_wad;
        _tickSpacing = tickSpacing;
    }

    function setTickValues(
        int24 currentTick,
        int24 tickLower,
        int24 tickUpper
    ) public {
        _requireAtLeastOperator();
        _currentTick = currentTick;
        _tickLower = tickLower;
        _tickUpper = tickUpper;
    }

    /// @notice Get the current tick and position ticks and decide whether to rebalance
    function rebalanceCheck() public view returns (bool) {
        // 1. Get current position, lower, and upper ticks
        // _currentPosition = _vault.currentPosition();
        // _tickLower = _currentPosition.tickLower;
        // _tickUpper = _currentPosition.tickUpper;

        // 2. Get current tick
        // _currentTick = _periphery.getCurrentTick(_marginEngine);

        // 3. Compare current fixed rate to lower and upper bounds
        if (_tickLower - _logProximity <= _currentTick && _currentTick <= _tickUpper + _logProximity) {
            // 4.1. If current fixed rate is within bounds, return false (don't rebalance)
            return false;
        } else {
            // 4.2. If current fixed rate is outside bounds, return true (do rebalance)
            return true;
        }
    }

    /// @notice Get the nearest tick multiple given a tick and tick spacing
    function nearestTickMultiple(int24 newTick, int24 tickSpacing) public pure returns (int24) {
        return
            (newTick /
                tickSpacing +
                ((((newTick % tickSpacing) + tickSpacing) % tickSpacing) >= tickSpacing / 2 ? int24(1) : int24(0))) *
            tickSpacing;
    }

    /// @notice Set new optimimal tick range based on current tick
    /// @param currentFixedRateWad currentFixedRate which is passed in from a 7-day rolling avg. historical fixed rate.
    function rebalance(uint256 currentFixedRateWad) public returns (int24 newTickLowerMul, int24 newTickUpperMul) {
        _requireAtLeastOperator();

        // 0. Get tickspacing from vamm
        // _tickSpacing = _vamm.tickSpacing(_vamm);

        // 1. Get the new tick lower
        // write UTs to check for underflow
        int256 deltaWad = int256(currentFixedRateWad) - int256(_sigmaWad);
        int256 newFixedLowerWad = 0;
        if (deltaWad > 0) {
            // delta is greater than 0 => choose delta
            if (deltaWad < _max_possible_lower_bound_wad) {
                newFixedLowerWad = deltaWad;
            } else {
                newFixedLowerWad = _max_possible_lower_bound_wad;
            }
        } else {
            // delta is less than or equal to 0 => choose 0
            newFixedLowerWad = 0;
        }
        // 2. Get the new tick upper
        int256 newFixedUpperWad = newFixedLowerWad + 2 * int256(_sigmaWad);

        // 3. Convert new fixed lower rate back to tick
        int256 newTickLowerWad = -PRBMathSD59x18.div(
            PRBMathSD59x18.log2(int256(newFixedUpperWad)),
            PRBMathSD59x18.log2(1000100000000000000)
        );

        // 4. Convert new fixed upper rate back to tick
        int256 newTickUpperWad = -PRBMathSD59x18.div(
            PRBMathSD59x18.log2(int256(newFixedLowerWad)),
            PRBMathSD59x18.log2(1000100000000000000)
        );

        int256 newTickLower = newTickLowerWad / 1e18;
        int256 newTickUpper = newTickUpperWad / 1e18;

        newTickLowerMul = nearestTickMultiple(int24(newTickLower), _tickSpacing);
        newTickUpperMul = nearestTickMultiple(int24(newTickUpper), _tickSpacing);

        // Update the global upper and lower tick variables
        _tickLower = newTickLowerMul;
        _tickUpper = newTickUpperMul;

        // Call to VoltzVault contract to update the position lower and upper ticks
        // _vault.rebalance(IVoltzVault.TickRange(_tickLower, _tickUpper));

        emit Rebalanced(newTickLowerMul, newTickUpperMul);
        return (newTickLowerMul, newTickUpperMul);
    }
}
