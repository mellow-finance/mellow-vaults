// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../libraries/ExceptionsLibrary.sol";
import "../interfaces/vaults/IGearboxRootVault.sol";
import "./DefaultAccessControl.sol";

contract GearboxDepositHelper is DefaultAccessControl {
    using SafeERC20 for IERC20;
    using SafeERC20 for IGearboxRootVault;

    uint256 public constant D9 = 10**9;
    
    constructor(address admin) DefaultAccessControl(admin) {}

    uint256 maxDeltaD;

    function changeMaxDeltaD(uint256 newMaxDeltaD_) external {
        _requireAdmin();
        maxDeltaD = newMaxDeltaD_;
    }

    function deposit(
        IGearboxRootVault vault,
        uint256[] calldata tokenAmounts,
        uint256 minLpTokens,
        bytes calldata vaultOptions
    ) external returns (uint256[] memory actualTokenAmounts) {

        _checkIfDepositIsPossible(vault);

        address[] memory tokens = vault.vaultTokens();
        require(tokens.length == tokenAmounts.length, ExceptionsLibrary.INVALID_LENGTH);
        for (uint256 i = 0; i < tokens.length; ++i) {
            IERC20(tokens[i]).safeTransferFrom(msg.sender, address(this), tokenAmounts[i]);
            IERC20(tokens[i]).safeIncreaseAllowance(address(vault), tokenAmounts[i]);
        }

        (actualTokenAmounts, ) = vault.deposit(tokenAmounts, minLpTokens, vaultOptions);
        for (uint256 i = 0; i < tokens.length; ++i) {
            IERC20(tokens[i]).safeApprove(address(vault), 0);
            IERC20(tokens[i]).safeTransfer(msg.sender, IERC20(tokens[i]).balanceOf(address(this)));
        }

        uint256 lpTokenMinted = vault.balanceOf(address(this));
        vault.safeTransfer(msg.sender, lpTokenMinted);

        emit Deposit(msg.sender, address(vault), tokens, actualTokenAmounts, lpTokenMinted);
    }

    function _checkIfDepositIsPossible(IGearboxRootVault vault) internal view {
        IGearboxVault gearboxVault = vault.gearboxVault();
        address creditAccount = gearboxVault.getCreditAccount();
        if (creditAccount == address(0)) {
            return;
        }
        address curveAdapter = gearboxVault.helper().curveAdapter();
        if (address(curveAdapter) != address(0)) {
            ICurvePool curvePool = ICurvePool(gearboxVault.creditManager().adapterToContract(curveAdapter));
            uint256 balance0 = curvePool.balances(uint256(0)) * 10**(18 - ERC20(curvePool.coins(uint256(0))).decimals());
            uint256 balance1 = curvePool.balances(uint256(1)) * 10**(18 - ERC20(curvePool.coins(uint256(1))).decimals());
            
            require(FullMath.mulDiv(balance0, maxDeltaD, D9) > balance1);
            require(FullMath.mulDiv(balance1, maxDeltaD, D9) > balance0);

        }
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
