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
            _currentPosition.tickLower, 
            _currentPosition.tickUpper
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
