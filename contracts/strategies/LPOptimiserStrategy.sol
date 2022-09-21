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
import "@prb/math/contracts/PRBMathUD60x18.sol";
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
    uint256 _logProximityWad; // x (closeness parameter in wad 10^18) in log base 1.0001
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

    /// @notice Get the current tick and position ticks and decide whether to rebalance
    function rebalanceCheck() public returns (bool) {
        // TODO: NEED TO HANDLE THE MULTIPLICATIONS AND CONVERSIONS FROM FIXED TO FLOATING POINT PROPERLY

        // 1. Get current position, lower, and upper ticks (uncomment once you have the logic nailed down)
        // _currentPosition = _vault.currentPosition();
        // int24 _tickLower = _currentPosition.tickLower;
        // int24 _tickUpper = _currentPosition.tickUpper;

        // Setting _proximity, ticklower and tickUpper here for testing purposes but this should be set as a variable
        _logProximityWad = 960000000000000000; // 0.96 in wad
        uint256 _tickLower = 0;
        uint256 _tickUpper = 8000;

        uint256 _tickLowerWad = PRBMathUD60x18.mul(_tickLower, 1000000000000000000);
        uint256 _tickUpperWad = PRBMathUD60x18.mul(_tickUpper, 1000000000000000000);

        // 2. Get current tick
        // int24 _currentTick = _marginEngine.getCurrentTick(); // should this be _periphery.getCurrentTick()?
        // Set the current tick for testing purposes
        uint256 _currentTick = 4000;
        uint256 _currentTickWad = PRBMathUD60x18.mul(_currentTick, 1000000000000000000);

        // 3. Compare current fixed rate to lower and upper bounds
        if (
            _tickLowerWad - _logProximityWad <= _currentTickWad &&
            _currentTickWad <= _tickUpperWad + _logProximityWad
            
            ) {
            // 4.1. If current fixed rate is within bounds, return false (don't rebalance)
            return (false);
        } else {
            // 4.2. If current fixed rate is outside bounds, return true (do rebalance)
            return (true);
        }
    }

    /// @notice Set new optimimal tick range based on current tick
    /// @param _currentFixedRateWad currentFixedRate which is passed in from a 7-day rolling avg. historical fixed rate.
    // Q: Is the range or the actual fixed rate passed to the strategy vault?
    function rebalance (uint256 _currentFixedRateWad) public returns (int256 newTickLower, int256 newTickUpper) {
        _requireAtLeastOperator();
        if (rebalanceCheck()) {
            // 1. Get the current fixed rate
            // int24 _currentTick = _periphery.getCurrentTick(_marginEngine.address());
            // 2. Convert current tick to fixed rate (this is retrieved off chain and passed in as argument)
            // uint256 _currentFixedRateWad = PRBMathUD60x18.pow( 1000100000000000000, -_currentTick);
            // 3. Get the new tick lower (min and max should be handled by Math.sol)
            uint256 _newFixedLowerWad = Math.min(Math.max(0, _currentFixedRateWad - _sigmaWad), _max_possible_lower_bound);
            // 4. Get the new tick upper
            uint256 _newFixedUpperWad = _newFixedLowerWad + PRBMathUD60x18.mul(_sigmaWad, 2);
            // 5. Convert new fixed lower back to tick (minus sign is missing for newTickLower and newTickUpper)
            int256 _newTickLower = -SafeCastUni.toInt256(PRBMathUD60x18.div(PRBMathUD60x18.log2(_newFixedLowerWad), 
                                                        PRBMathUD60x18.log2(1000100000000000000)
                                                        )); 
            // 6. Convert new fixed upper back to tick
            int256 _newTickUpper = -SafeCastUni.toInt256(PRBMathUD60x18.div(PRBMathUD60x18.log2(_newFixedUpperWad),
                                                        PRBMathUD60x18.log2(1000100000000000000)
                                                        ));
            return (_newTickLower, _newTickUpper);
        } else {
            revert (ExceptionsLibrary.REBALANCE_NOT_NEEDED);
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
