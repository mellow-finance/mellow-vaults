// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.9;

import "../interfaces/external/aave/ILendingPool.sol";
import "../interfaces/vaults/IAaveVaultGovernance.sol";
import "../interfaces/vaults/IAaveVault.sol";
import "../libraries/ExceptionsLibrary.sol";
import "../libraries/external/FullMath.sol";
import "./IntegrationVault.sol";

/// @notice Vault that interfaces Aave protocol in the integration layer.
/// @dev Notes:
/// **TVL**
///
/// The TVL of the vault is cached and updated after each deposit withdraw.
/// So essentially `tvl` call doesn't take into account accrued interest / donations to Aave since the
/// last `deposit` / `withdraw`
///
/// **aTokens**
/// aTokens are fixed at the token creation and addresses are taken from Aave Lending Pool.
/// So essentially each aToken is fixed for life of the AaveVault. If the aToken is missing for some vaultToken,
/// the AaveVault cannot be created.
///
/// **Push / Pull**
/// It is assumed that any amounts of tokens can be deposited / withdrawn from Aave.
/// The contract's vaultTokens are fully allowed to Aave Lending Pool.
contract AaveVault is IAaveVault, IntegrationVault {
    using SafeERC20 for IERC20;
    address[] internal _aTokens;
    uint256[] internal _tvls;
    uint256 private _lastTvlUpdateTimestamp;
    ILendingPool private _lendingPool;

    // -------------------  EXTERNAL, VIEW  -------------------

    /// @inheritdoc IVault
    function tvl() public view override returns (uint256[] memory minTokenAmounts, uint256[] memory maxTokenAmounts) {
        minTokenAmounts = _tvls;
        maxTokenAmounts = new uint256[](minTokenAmounts.length);
        uint256 timeElapsed = block.timestamp - _lastTvlUpdateTimestamp;
        uint256 factor = CommonLibrary.DENOMINATOR;
        if (timeElapsed > 0) {
            uint256 apy = IAaveVaultGovernance(address(_vaultGovernance)).delayedProtocolParams().estimatedAaveAPY;
            factor = CommonLibrary.DENOMINATOR + FullMath.mulDiv(apy, timeElapsed, CommonLibrary.YEAR);
        }
        for (uint256 i = 0; i < minTokenAmounts.length; i++) {
            maxTokenAmounts[i] = FullMath.mulDiv(factor, minTokenAmounts[i], CommonLibrary.DENOMINATOR);
        }
    }

    /// @inheritdoc IAaveVault
    function lendingPool() external view returns (ILendingPool) {
        return _lendingPool;
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public view override(IERC165, IntegrationVault) returns (bool) {
        return IntegrationVault.supportsInterface(interfaceId) || interfaceId == type(IAaveVault).interfaceId;
    }

    // -------------------  EXTERNAL, MUTATING  -------------------

    /// @notice Update all tvls to current aToken balances.
    /// @inheritdoc IAaveVault
    function updateTvls() external {
        _updateTvls();
    }

    /// @inheritdoc IAaveVault
    function initialize(uint256 nft_, address[] memory vaultTokens_) external {
        _initialize(vaultTokens_, nft_);
        _lendingPool = IAaveVaultGovernance(address(_vaultGovernance)).delayedProtocolParams().lendingPool;
        _aTokens = new address[](vaultTokens_.length);
        for (uint256 i = 0; i < vaultTokens_.length; ++i) {
            address aToken = _getAToken(vaultTokens_[i]);
            require(aToken != address(0), ExceptionsLibrary.ADDRESS_ZERO);
            _aTokens[i] = aToken;
            _tvls.push(0);
        }
        _lastTvlUpdateTimestamp = block.timestamp;
    }

    // -------------------  INTERNAL, VIEW  -------------------

    function _getAToken(address token) internal view returns (address) {
        DataTypes.ReserveData memory data = _lendingPool.getReserveData(token);
        return data.aTokenAddress;
    }

    function _isReclaimForbidden(address token) internal view override returns (bool) {
        uint256 len = _aTokens.length;
        for (uint256 i = 0; i < len; ++i) {
            if (_aTokens[i] == token) {
                return true;
            }
        }
        return false;
    }

    // -------------------  INTERNAL, MUTATING  -------------------

    function _updateTvls() private {
        uint256 tvlsLength = _tvls.length;
        for (uint256 i = 0; i < tvlsLength; ++i) {
            _tvls[i] = IERC20(_aTokens[i]).balanceOf(address(this));
        }
        _lastTvlUpdateTimestamp = block.timestamp;
    }

    function _push(uint256[] memory tokenAmounts, bytes memory options)
        internal
        override
        returns (uint256[] memory actualTokenAmounts)
    {
        address[] memory tokens = _vaultTokens;
        uint256 referralCode = 0;
        if (options.length > 0) {
            referralCode = abi.decode(options, (uint256));
        }

        for (uint256 i = 0; i < _aTokens.length; ++i) {
            if (tokenAmounts[i] == 0) {
                continue;
            }
            address token = tokens[i];
            IERC20(token).safeIncreaseAllowance(address(_lendingPool), tokenAmounts[i]);
            _lendingPool.deposit(tokens[i], tokenAmounts[i], address(this), uint16(referralCode));
            IERC20(token).safeApprove(address(_lendingPool), 0);
        }
        _updateTvls();
        actualTokenAmounts = tokenAmounts;
    }

    function _pull(
        address to,
        uint256[] memory tokenAmounts,
        bytes memory
    ) internal override returns (uint256[] memory actualTokenAmounts) {
        address[] memory tokens = _vaultTokens;
        actualTokenAmounts = new uint256[](tokenAmounts.length);
        for (uint256 i = 0; i < _aTokens.length; ++i) {
            if ((_tvls[i] == 0) || (tokenAmounts[i] == 0)) {
                continue;
            }
            uint256 balance = IERC20(_aTokens[i]).balanceOf(address(this));
            uint256 amount = tokenAmounts[i] < balance ? tokenAmounts[i] : balance;
            actualTokenAmounts[i] = _lendingPool.withdraw(tokens[i], amount, to);
        }
        _updateTvls();
    }
}
