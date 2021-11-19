// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./interfaces/external/aave/ILendingPool.sol";
import "./interfaces/IAaveVaultGovernance.sol";
import "./Vault.sol";

/// @notice Vault that interfaces Aave protocol in the integration layer.
contract AaveVault is Vault {
    address[] internal _aTokens;
    uint256[] internal _tvls;

    /// @notice Creates a new contract.
    /// @param vaultGovernance_ Reference to VaultGovernance for this vault
    /// @param vaultTokens_ ERC20 tokens under Vault management
    constructor(IVaultGovernance vaultGovernance_, address[] memory vaultTokens_)
        Vault(vaultGovernance_, vaultTokens_)
    {
        _aTokens = new address[](vaultTokens_.length);
        for (uint256 i = 0; i < _vaultTokens.length; i++) {
            // TODO: check if token doesn't exist
            _aTokens[i] = _getAToken(_vaultTokens[i]);
            _tvls.push(0);
        }
    }

    /// @inheritdoc Vault
    function tvl() public view override returns (uint256[] memory tokenAmounts) {
        return _tvls;
    }

    function updateTvls() public {
        for (uint256 i = 0; i < _tvls.length; i++) {
            _tvls[i] = IERC20(_aTokens[i]).balanceOf(address(this));
        }
    }

    function _push(uint256[] memory tokenAmounts, bytes memory)
        internal
        override
        returns (uint256[] memory actualTokenAmounts)
    {
        address[] memory tokens = _vaultTokens;
        for (uint256 i = 0; i < _aTokens.length; i++) {
            if (tokenAmounts[i] == 0) {
                continue;
            }
            address token = tokens[i];
            _allowTokenIfNecessary(token);
            // TODO: Check what is 0
            _lendingPool().deposit(tokens[i], tokenAmounts[i], address(this), 0);
        }
        // TODO: Check price manipulation here for LPIssuer
        updateTvls();
        actualTokenAmounts = tokenAmounts;
    }

    function _pull(
        address to,
        uint256[] memory tokenAmounts,
        bytes memory
    ) internal override returns (uint256[] memory actualTokenAmounts) {
        address[] memory tokens = _vaultTokens;
        for (uint256 i = 0; i < _aTokens.length; i++) {
            if ((_tvls[i] == 0) || (tokenAmounts[i] == 0)) {
                continue;
            }
            _lendingPool().withdraw(tokens[i], tokenAmounts[i], to);
        }
        updateTvls();
        actualTokenAmounts = tokenAmounts;
    }

    function _getAToken(address token) internal view returns (address) {
        DataTypes.ReserveData memory data = _lendingPool().getReserveData(token);
        return data.aTokenAddress;
    }

    function _allowTokenIfNecessary(address token) internal {
        if (IERC20(token).allowance(address(_lendingPool()), address(this)) < type(uint256).max / 2) {
            IERC20(token).approve(address(_lendingPool()), type(uint256).max);
        }
    }

    function _lendingPool() internal view returns (ILendingPool) {
        return IAaveVaultGovernance(address(_vaultGovernance)).delayedProtocolParams().lendingPool;
    }
}
