// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
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
    uint256 _proximity; // x (closeness parameter)
    uint256 _sigma; // y (standard deviation parameter)
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

        // 1. Get current position, lower, and upper ticks
        // _currentPosition = _vault.currentPosition(); // this and 2 lines below will depend on how Alex structures the VoltzVault contract
        // int24 _tickLower = _currentPosition.tickLower; 
        // int24 _tickUpper = _currentPosition.tickUpper;
        uint256 _tickLower = 0;
        uint256 _tickUpper = 8000;
        // 2. Get current tick
        // int24 _currentTick = _marginEngine.getCurrentTick(); // should this be _periphery.getCurrentTick()?
        uint256 _currentTick = 4000;
        // 3. Convert ticks to fixed rates
        uint256 _currentFixedRateWad = PRBMathUD60x18.pow(
            2,
            _currentTick
        );
        uint256 _currentFixedLowWad = PRBMathUD60x18.pow(
            2,
            _tickLower
        );
        uint256 _currentFixedHighWad = PRBMathUD60x18.pow(
            PRBMathUD60x18.mul(1.0001, 1e18), 
            _tickUpper
        );
        // 4. Compare current fixed rate to lower and upper bounds
        if (
            PRBMathUD60x18.div(_currentFixedLowWad, _proximity) < _currentFixedRateWad 
            && PRBMathUD60x18.mul(_currentFixedHighWad, _proximity) > _currentFixedRateWad
            ) {
            // 4.1. If current fixed rate is within bounds, return false (don't rebalance)
            return (false);
        } else {
            // 4.2. If current fixed rate is outside bounds, return true (do rebalance)
            return (true);
        }
    }

    // /// @notice Set new optimimal tick range based on current tick
    // function rebalance () public returns (int24 newTickLower, int24 newTickUpper) {
    //     _requireAtLeastOperator();
    //     if (rebalanceCheck()) {
    //         // 1. Get the current fixed rate
    //         int24 _currentTick = _marginEngine.getCurrentTick();
    //         // 2. Convert current tick to fixed rate
    //         uint256 _currentFixedRateWad = PRBMathUD60x18.pow( mul(1.0001, 1e18), -_currentTick);
    //         // 3. Get the new tick lower
    //         int24 _newFixedLower = min(max(0, _currentFixedRateWad - _sigma), _max_possible_lower_bound);
    //         // 4. Get the new tick upper
    //         int24 _newFixedUpper = _newFixedLower + PRBMathUD60x18.mul(_sigma, 2);
    //         // 5. Convert new fixed lower back to tick
    //         int24 _newTickLower = -log2(_newFixedLower).div(
    //             log2(mul(1.0001, 1e18) )
    //         );
    //         return _newTickLower, _newTickUpper;
    //     } else {
    //         revert ExceptionsLibrary.rebalanceNotNeeded();
    //       }
    //     }


//--------------------// Don't need the below functions// ---------------------//

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
