// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "../interfaces/external/voltz/utils/SafeCastUni.sol";
import "../interfaces/vaults/IERC20Vault.sol";
import "../interfaces/vaults/IVoltzVault.sol";
import "../interfaces/external/voltz/IMarginEngine.sol";
import "../interfaces/utils/ILpCallback.sol";
import "../libraries/ExceptionsLibrary.sol";
import "../libraries/CommonLibrary.sol";
import "../libraries/external/FullMath.sol";
import "../utils/DefaultAccessControl.sol";
import "@prb/math/contracts/PRBMathSD59x18.sol";
import "hardhat/console.sol";

contract LPOptimiserStrategy is DefaultAccessControl, ILpCallback {
    using SafeERC20 for IERC20;

    // IMMUTABLES
    address[] public _tokens;
    IERC20Vault public immutable _erc20Vault;

    // INTERNAL STATE

    IVoltzVault internal _vault;
    uint256[] internal _pullExistentials;
    IMarginEngine internal _marginEngine;
    IVoltzVault.TickRange internal _currentPosition;

    // MUTABLE PARAMS

    uint256 _lastSignal;
    uint256 _lastLeverage;
    int24 _logProximity; // x (closeness parameter in wad 10^18) in log base 1.0001
    uint256 _sigmaWad; // y (standard deviation parameter in wad 10^18)
    uint256 _max_possible_lower_bound; // should be in fixed rate
    uint256 _k_unwind_parameter; // parameter for k*leverage (for unwinding so this needs to be sent to the contract vault but not used in the strategy vault)

    uint256 _lastFixedLow;
    uint256 _lastFixedHigh;

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
        _currentPosition = vault_.currentPosition();
        _tokens = vault_.vaultTokens();
        _pullExistentials = vault_.pullExistentials();
    }

    function setLogProximity(int24 logProx) public {
        _requireAtLeastOperator();
        _logProximity = logProx;
    }

    /// @notice Get the current tick and position ticks and decide whether to rebalance
    function rebalanceCheck() public view returns (bool) {

        // Setting _proximity, ticklower, tickUpper, current tick here for testing purposes but this should be set as a variable
        int24 _tickLower = 0;
        int24 _tickUpper = 6000;
        int24 _currentTick = 7000;

        // 1. Get current position, lower, and upper ticks (uncomment once you have the logic nailed down)
        // _currentPosition = _vault.currentPosition();
        // int24 _tickLower = _currentPosition.tickLower;
        // int24 _tickUpper = _currentPosition.tickUpper;

        // 2. Get current tick
        // int24 _currentTick = _periphery.getCurrentTick(_marginEngine.address());

        // 3. Compare current fixed rate to lower and upper bounds
        if (
            _tickLower - _logProximity <= _currentTick &&
            _currentTick <= _tickUpper + _logProximity
            
            ) {
            // 4.1. If current fixed rate is within bounds, return false (don't rebalance)
            return (false);
        } else {
            // 4.2. If current fixed rate is outside bounds, return true (do rebalance)
            return (true);
        }
    }

    /// @notice Get the nearest tick multiple given a tick and tick spacing
    function nearestTickMultiple(int24 newTick, int24 tickSpacing) internal pure returns (int24) {
     return (newTick / tickSpacing + (newTick % tickSpacing >= tickSpacing/2 ? int24(1) : int24(0)) ) * tickSpacing;
    }

    /// @notice Set new optimimal tick range based on current tick
    /// @param currentFixedRateWad currentFixedRate which is passed in from a 7-day rolling avg. historical fixed rate.
    // Q: Is the range or the actual fixed rate passed to the strategy vault?
    function rebalance (int256 currentFixedRateWad) public returns (int256 newTickLower, int256 newTickUpper) {
        _requireAtLeastOperator();
        // Set for testing purposes
        _sigmaWad = 100000000000000000; // received in WAD
        _max_possible_lower_bound = 1500000000000000000; // ideally receive this in a fixed rate
        int24 _tickSpacing = 60;
        int24 _newTickLower = 2000;

        // console.log('my console logs start here:');
        // console.logInt(PRBMathSD59x18.log2(currentFixedRateWad));
        // console.logInt(PRBMathSD59x18.log2(1000100000000000000));
        // console.logInt(-PRBMathSD59x18.div(PRBMathSD59x18.log2(currentFixedRateWad), PRBMathSD59x18.log2(1000100000000000000)));
        // console.log(PRBMathUD60x18.mul(_sigmaWad, 2000000000000000000));
        // console.logInt(nearestTickMultiple(_newTickLower, _tickSpacing));

        if (rebalanceCheck()) {
            // 0. Get tickspacing from vamm
            // int24 _tickSpacing = _vamm.tickSpacing(_vamm.address());

            // 1. Get the new tick lower
            // uint256 _newFixedLowerWad = Math.min(Math.max(0, uint256(currentFixedRateWad) - _sigmaWad), _max_possible_lower_bound);
            uint256 deltaWad = uint256(currentFixedRateWad) - _sigmaWad;
            console.log(deltaWad);
            uint256 _newFixedLowerWad =  0;
            if (deltaWad > 0) {
                // delta is greater than 0 => choose delta
                if (deltaWad < _max_possible_lower_bound) {
                    _newFixedLowerWad = deltaWad;
                } else {
                    _newFixedLowerWad = _max_possible_lower_bound;
                }
            } else {
                // delta is less than 0 => choose 0
                if (_max_possible_lower_bound > 0) {
                    _newFixedLowerWad = 0;
                } else {
                    _newFixedLowerWad = _max_possible_lower_bound;
                }
            }
            // 2. Get the new tick upper
            console.log(_newFixedLowerWad);
            uint256 _newFixedUpperWad = _newFixedLowerWad + 2 * _sigmaWad;
            console.log(_newFixedUpperWad);
            // 3. Convert new fixed lower rate back to tick
            int256 _newTickLowerWad = -PRBMathSD59x18.div(PRBMathSD59x18.log2(int256(_newFixedUpperWad)), 
                                                        PRBMathSD59x18.log2(1000100000000000000)
                                                        );
            console.logInt(_newTickLowerWad);
            // 4. Convert new fixed upper rate back to tick
            int256 _newTickUpperWad = -PRBMathSD59x18.div(PRBMathSD59x18.log2(int256(_newFixedLowerWad)),
                                                        PRBMathSD59x18.log2(1000100000000000000)
                                                        );
            console.logInt(_newTickUpperWad);

            int256 _newTickLower = _newTickLowerWad/1e18;
            int256 _newTickUpper = _newTickUpperWad/1e18;

            console.logInt(_newTickLower);
            console.logInt(_newTickUpper);

            int24 _newTickLowerMul = nearestTickMultiple(int24(_newTickLower), _tickSpacing);
            int24 _newTickUpperMul = nearestTickMultiple(int24(_newTickUpper), _tickSpacing);

            console.logInt(_newTickLowerMul);
            console.logInt(_newTickUpperMul);


            return (_newTickLowerMul, _newTickUpperMul);
        } else {
            revert(ExceptionsLibrary.REBALANCE_NOT_NEEDED);
          }
        }


//--------------------// Don't need the below functions // ---------------------//

    /// @notice Get new signal and act according to it
    /// @param signal New signal (1 - short/fixed, 2 - long/variable, 3 - exit)
    /// @param leverage Leverage you take for this trade (in wad)
    /// @param marginUpdate This flags that this update is triggered by deposit/withdrawal
    function update(
        uint256 signal, 
        uint256 leverage,
        bool marginUpdate
    ) public {
        _requireAtLeastOperator();

        require (signal == 1 || signal == 2 || signal == 3, ExceptionsLibrary.INVALID_VALUE);
        require (leverage > 0, ExceptionsLibrary.INVALID_VALUE);

        if (!marginUpdate && signal == _lastSignal && _lastLeverage == leverage) {
            return;
        }

        Position.Info memory position = _marginEngine.getPosition(
            address(_vault), 
            _currentPosition.low, 
            _currentPosition.high
        );

        uint256[] memory tokenAmounts = new uint256[](1);

        {
            bytes memory options = abi.encode(
                0,
                 position.variableTokenBalance,
                0,
                false,
                0,
                0,
                false,
                0
            );

            _vault.pull(
                address(_erc20Vault),
                _tokens,
                tokenAmounts,
                options
            );
        }

        if (signal == 1) {
            int256 notional = FullMath.mulDivSigned(position.margin, leverage, CommonLibrary.D18);

            bytes memory options = abi.encode(
                0,
                notional,
                0,
                false,
                0,
                0,
                false,
                0
            );

            _vault.push(
                _tokens,
                tokenAmounts,
                options
            );
        }

        if (signal == 2) {
            int256 notional = FullMath.mulDivSigned(position.margin, leverage, CommonLibrary.D18);

            bytes memory options = abi.encode(
                0,
                -notional,
                0,
                false,
                0,
                0,
                false,
                0
            );

            _vault.push(
                _tokens,
                tokenAmounts,
                options
            );
        }

        _lastSignal = signal;
        _lastLeverage = leverage;
    }

    function settle() public {
        _requireAtLeastOperator();

        uint256[] memory tokenAmounts = new uint256[](1);
        tokenAmounts[0] = type(uint256).max;

        bytes memory options = abi.encode(
                0,
                0,
                0,
                false,
                0,
                0,
                true,
                1
            );

        _vault.pull(
            address(_erc20Vault),
            _tokens,
            tokenAmounts,
            options
        );
    }

    /// @notice Callback function called after for ERC20RootVault::deposit
    function depositCallback() external {
        update(_lastSignal, _lastLeverage, true);
    }

    /// @notice Callback function called after for ERC20RootVault::withdraw
    function withdrawCallback() external {
        update(_lastSignal, _lastLeverage, true);
    }
}
