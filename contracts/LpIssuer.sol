// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./interfaces/IVault.sol";

contract LpIssuer is ERC20 {
    IVault private _gatewayVault;
    using SafeERC20 for IERC20;

    constructor(
        string memory name_,
        string memory symbol_,
        IVault gatewayVault
    ) ERC20(name_, symbol_) {
        _gatewayVault = gatewayVault;
    }

    function deposit(uint256[] calldata tokenAmounts) external {
        address[] memory tokens = _gatewayVault.vaultTokens();
        for (uint256 i = 0; i < tokens.length; i++) {
            IERC20(tokens[i]).safeTransferFrom(msg.sender, address(_gatewayVault), tokenAmounts[i]);
        }
        uint256[] memory tvl = _gatewayVault.tvl();
        uint256[] memory actualTokenAmounts = _gatewayVault.push(tokens, tokenAmounts);
        uint256 amountToMint;
        if (totalSupply() == 0) {
            for (uint256 i = 0; i < tokens.length; i++) {
                // TODO: check if there could be smth better
                if (actualTokenAmounts[i] > amountToMint) {
                    amountToMint = actualTokenAmounts[i]; // some number correlated to invested assets volume
                }
            }
        }
        for (uint256 i = 0; i < tokens.length; i++) {
            if (tvl[i] > 0) {
                uint256 newMint = (actualTokenAmounts[i] * totalSupply()) / tvl[i];
                // TODO: check this algo. The assumption is that everything is rounded down.
                // So that max token has the least error. Think about the case when one token is dust.
                if (newMint > amountToMint) {
                    amountToMint = newMint;
                }
            }
            if (tokenAmounts[i] > actualTokenAmounts[i]) {
                IERC20(tokens[i]).safeTransfer(msg.sender, tokenAmounts[i] - actualTokenAmounts[i]);
            }
        }
        if (amountToMint > 0) {
            _mint(msg.sender, amountToMint);
        }

        emit Deposit(msg.sender, tokens, actualTokenAmounts, amountToMint);
    }

    function withdraw(address to, uint256 lpTokenAmount) external {
        require(totalSupply() > 0, "TS");
        address[] memory tokens = _gatewayVault.vaultTokens();
        uint256[] memory tokenAmounts = new uint256[](tokens.length);
        uint256[] memory tvl = _gatewayVault.tvl();
        for (uint256 i = 0; i < tokens.length; i++) {
            tokenAmounts[i] = (lpTokenAmount * tvl[i]) / totalSupply();
        }
        uint256[] memory actualTokenAmounts = _gatewayVault.pull(to, tokens, tokenAmounts);
        _burn(msg.sender, lpTokenAmount);
        emit Withdraw(msg.sender, tokens, actualTokenAmounts, lpTokenAmount);
    }

    event Deposit(address from, address[] tokens, uint256[] actualTokenAmounts, uint256 lpTokenMinted);
    event Withdraw(address from, address[] tokens, uint256[] actualTokenAmounts, uint256 lpTokenBurned);
}
