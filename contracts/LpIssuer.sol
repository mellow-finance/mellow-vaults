// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./libraries/Common.sol";
import "./interfaces/IVault.sol";
import "./interfaces/IProtocolGovernance.sol";
import "./DefaultAccessControl.sol";
import "./LpIssuerGovernance.sol";

contract LpIssuer is ERC20, DefaultAccessControl, LpIssuerGovernance {
    using SafeERC20 for IERC20;

    GovernanceParams private _governanceParams;
    uint256 private _limitPerAddress;

    constructor(
        string memory name_,
        string memory symbol_,
        IVault gatewayVault,
        IProtocolGovernance protocolGovernance,
        uint256 limitPerAddress,
        address admin
    )
        ERC20(name_, symbol_)
        DefaultAccessControl(admin)
        LpIssuerGovernance(GovernanceParams({protocolGovernance: protocolGovernance, gatewayVault: gatewayVault}))
    {
        _governanceParams = GovernanceParams({gatewayVault: gatewayVault, protocolGovernance: protocolGovernance});
        _limitPerAddress = limitPerAddress;
    }

    function setLimit(uint256 newLimitPerAddress) external {
        require(isAdmin(), "ADM");
        _limitPerAddress = newLimitPerAddress;
    }

    function deposit(
        uint256[] calldata tokenAmounts,
        bool optimized,
        bytes memory options
    ) external {
        address[] memory tokens = governanceParams().gatewayVault.vaultGovernance().vaultTokens();
        for (uint256 i = 0; i < tokens.length; i++) {
            IERC20(tokens[i]).safeTransferFrom(msg.sender, address(governanceParams().gatewayVault), tokenAmounts[i]);
        }
        uint256[] memory tvl = governanceParams().gatewayVault.tvl();
        uint256[] memory actualTokenAmounts = governanceParams().gatewayVault.push(
            tokens,
            tokenAmounts,
            optimized,
            options
        );
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
        require(amountToMint + balanceOf(msg.sender) <= _limitPerAddress, "LPA");
        if (amountToMint > 0) {
            _mint(msg.sender, amountToMint);
        }

        emit Deposit(msg.sender, tokens, actualTokenAmounts, amountToMint);
    }

    function withdraw(
        address to,
        uint256 lpTokenAmount,
        bool optimized,
        bytes memory options
    ) external {
        require(totalSupply() > 0, "TS");
        address[] memory tokens = governanceParams().gatewayVault.vaultGovernance().vaultTokens();
        uint256[] memory tokenAmounts = new uint256[](tokens.length);
        uint256[] memory tvl = governanceParams().gatewayVault.tvl();
        for (uint256 i = 0; i < tokens.length; i++) {
            tokenAmounts[i] = (lpTokenAmount * tvl[i]) / totalSupply();
        }
        uint256[] memory actualTokenAmounts = governanceParams().gatewayVault.pull(
            address(this),
            tokens,
            tokenAmounts,
            optimized,
            options
        );
        uint256 protocolExitFee = governanceParams().protocolGovernance.protocolExitFee();
        address protocolTreasury = governanceParams().protocolGovernance.protocolTreasury();
        uint256[] memory exitFees = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            if (actualTokenAmounts[i] == 0) {
                continue;
            }
            exitFees[i] = (actualTokenAmounts[i] * protocolExitFee) / Common.DENOMINATOR;
            actualTokenAmounts[i] -= exitFees[i];
            IERC20(tokens[i]).safeTransfer(protocolTreasury, exitFees[i]);
            IERC20(tokens[i]).safeTransfer(to, actualTokenAmounts[i]);
        }
        _burn(msg.sender, lpTokenAmount);
        emit Withdraw(msg.sender, tokens, actualTokenAmounts, lpTokenAmount);
        emit ExitFeeCollected(msg.sender, protocolTreasury, tokens, exitFees);
    }

    event Deposit(address indexed from, address[] tokens, uint256[] actualTokenAmounts, uint256 lpTokenMinted);
    event Withdraw(address indexed from, address[] tokens, uint256[] actualTokenAmounts, uint256 lpTokenBurned);
    event ExitFeeCollected(address indexed from, address to, address[] tokens, uint256[] amounts);
}
