// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../libraries/ExceptionsLibrary.sol";

import "../interfaces/vaults/IERC20RootVault.sol";
import "../interfaces/utils/ILpCallback.sol";

import "./DefaultAccessControl.sol";

contract DepositWrapper is DefaultAccessControl {
    using SafeERC20 for IERC20;
    using SafeERC20 for IERC20RootVault;

    struct StrategyInfo {
        address strategy;
        bool needToCallCallback;
    }

    mapping(address => StrategyInfo) public depositInfo;

    constructor(address admin) DefaultAccessControl(admin) {}

    // -------------------  EXTERNAL, MUTATING  -------------------

    function deposit(
        IERC20RootVault vault,
        uint256[] calldata tokenAmounts,
        uint256 minLpTokens,
        bytes calldata vaultOptions
    ) external returns (uint256[] memory actualTokenAmounts) {
        StrategyInfo memory strategyInfo = depositInfo[address(vault)];
        require(strategyInfo.strategy != address(0), ExceptionsLibrary.ADDRESS_ZERO);

        address[] memory tokens = vault.vaultTokens();
        require(tokens.length == tokenAmounts.length, ExceptionsLibrary.INVALID_LENGTH);
        for (uint256 i = 0; i < tokens.length; ++i) {
            IERC20(tokens[i]).safeTransferFrom(msg.sender, address(this), tokenAmounts[i]);
            IERC20(tokens[i]).safeIncreaseAllowance(address(vault), tokenAmounts[i]);
        }

        actualTokenAmounts = vault.deposit(tokenAmounts, minLpTokens, vaultOptions);
        if (strategyInfo.needToCallCallback) {
            ILpCallback(strategyInfo.strategy).depositCallback();
        }

        for (uint256 i = 0; i < tokens.length; ++i) {
            IERC20(tokens[i]).safeApprove(address(vault), 0);
            IERC20(tokens[i]).safeTransfer(msg.sender, IERC20(tokens[i]).balanceOf(address(this)));
        }

        uint256 lpTokenMinted = vault.balanceOf(address(this));
        vault.safeTransfer(msg.sender, lpTokenMinted);

        emit Deposit(msg.sender, address(vault), tokens, actualTokenAmounts, lpTokenMinted);
    }

    function addNewStrategy(
        address vault,
        address strategy,
        bool needToCallCallback
    ) external {
        _requireAdmin();
        depositInfo[vault] = StrategyInfo({strategy: strategy, needToCallCallback: needToCallCallback});
    }

    /// @notice Emitted when liquidity is deposited
    /// @param from The source address for the liquidity
    /// @param tokens ERC20 tokens deposited
    /// @param actualTokenAmounts Token amounts deposited
    /// @param lpTokenMinted LP tokens received by the liquidity provider
    event Deposit(
        address indexed from,
        address indexed to,
        address[] tokens,
        uint256[] actualTokenAmounts,
        uint256 lpTokenMinted
    );
}