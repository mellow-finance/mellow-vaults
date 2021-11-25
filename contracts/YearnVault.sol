// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./interfaces/external/aave/ILendingPool.sol";
import "./interfaces/external/yearn/IYearnVault.sol";
import "./interfaces/IYearnVaultGovernance.sol";
import "./Vault.sol";

/// @notice Vault that interfaces Yearn protocol in the integration layer.
contract YearnVault is Vault {
    address[] private _yTokens;

    /// @notice Creates a new contract.
    /// @param vaultGovernance_ Reference to VaultGovernance for this vault
    /// @param vaultTokens_ ERC20 tokens under Vault management
    constructor(IVaultGovernance vaultGovernance_, address[] memory vaultTokens_)
        Vault(vaultGovernance_, vaultTokens_)
    {
        _yTokens = new address[](vaultTokens_.length);
        for (uint256 i = 0; i < _vaultTokens.length; i++) {
            _yTokens[i] = _yearnVaultRegistry().latestVault(_vaultTokens[i]);
            require(_yTokens[i] != address(0), "VDE");
        }
    }

    /// @notice Returns Yearn protocol vaults used by this contract
    function yTokens() external view returns (address[] memory) {
        return _yTokens;
    }

    /// @inheritdoc Vault
    function tvl() public view override returns (uint256[] memory tokenAmounts) {
        address[] memory tokens = _vaultTokens;
        tokenAmounts = new uint256[](tokens.length);
        for (uint256 i = 0; i < _yTokens.length; i++) {
            IYearnVault yToken = IYearnVault(_yTokens[i]);
            /// TODO: Verify it's not subject to manipulation like in Cream hack
            tokenAmounts[i] = (yToken.balanceOf(address(this)) * yToken.pricePerShare()) / (10**yToken.decimals());
        }
    }

    function _push(uint256[] memory tokenAmounts, bytes memory)
        internal
        override
        returns (uint256[] memory actualTokenAmounts)
    {
        address[] memory tokens = _vaultTokens;
        for (uint256 i = 0; i < _yTokens.length; i++) {
            if (tokenAmounts[i] == 0) {
                continue;
            }

            address token = tokens[i];
            IYearnVault yToken = IYearnVault(_yTokens[i]);
            _allowTokenIfNecessary(token, address(yToken));
            yToken.deposit(tokenAmounts[i], address(this));
        }
        actualTokenAmounts = tokenAmounts;
    }

    function _pull(
        address to,
        uint256[] memory tokenAmounts,
        bytes memory options
    ) internal override returns (uint256[] memory actualTokenAmounts) {
        uint256 maxLoss = abi.decode(options, (uint256));
        for (uint256 i = 0; i < _yTokens.length; i++) {
            if (tokenAmounts[i] == 0) {
                continue;
            }

            IYearnVault yToken = IYearnVault(_yTokens[i]);
            uint256 yTokenAmount = ((tokenAmounts[i] * (10**yToken.decimals())) / yToken.pricePerShare());
            uint256 balance = yToken.balanceOf(address(this));
            if (yTokenAmount > balance) {
                yTokenAmount = balance;
            }
            if (yTokenAmount == 0) {
                continue;
            }
            yToken.withdraw(yTokenAmount, to, maxLoss);
            (tokenAmounts[i], address(this));
        }
        actualTokenAmounts = tokenAmounts;
    }

    function _allowTokenIfNecessary(address token, address yToken) internal {
        if (IERC20(token).allowance(address(this), yToken) < type(uint256).max / 2) {
            IERC20(token).approve(yToken, type(uint256).max);
        }
    }

    function _yearnVaultRegistry() internal view returns (IYearnVaultRegistry) {
        return IYearnVaultGovernance(address(_vaultGovernance)).delayedProtocolParams().yearnVaultRegistry;
    }
}
