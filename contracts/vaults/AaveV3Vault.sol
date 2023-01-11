// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.9;

import "../interfaces/vaults/IAaveV3VaultGovernance.sol";
import "../libraries/ExceptionsLibrary.sol";
import "../libraries/external/FullMath.sol";
import "./IntegrationVault.sol";

contract AaveV3Vault is IAaveV3Vault, IntegrationVault {
    using SafeERC20 for IERC20;
    address[] internal _aTokens;
    uint256[] internal _tvls;
    uint256 private _lastTvlUpdateTimestamp;
    IPool private _pool;

    // -------------------  EXTERNAL, VIEW  -------------------

    /// @inheritdoc IVault
    function tvl() public view override returns (uint256[] memory minTokenAmounts, uint256[] memory maxTokenAmounts) {
        minTokenAmounts = _tvls;
        maxTokenAmounts = new uint256[](minTokenAmounts.length);
        uint256 timeElapsed = block.timestamp - _lastTvlUpdateTimestamp;
        uint256 factor = CommonLibrary.DENOMINATOR;
        if (timeElapsed > 0) {
            uint256 apy = IAaveV3VaultGovernance(address(_vaultGovernance)).delayedProtocolParams().estimatedAaveAPY;
            factor = CommonLibrary.DENOMINATOR + FullMath.mulDiv(apy, timeElapsed, CommonLibrary.YEAR);
        }
        for (uint256 i = 0; i < minTokenAmounts.length; i++) {
            maxTokenAmounts[i] = FullMath.mulDiv(factor, minTokenAmounts[i], CommonLibrary.DENOMINATOR);
        }
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public view override(IERC165, IntegrationVault) returns (bool) {
        return IntegrationVault.supportsInterface(interfaceId) || interfaceId == type(IAaveV3Vault).interfaceId;
    }

    // -------------------  EXTERNAL, MUTATING  -------------------

    /// @notice Update all tvls to current aToken balances.
    /// @inheritdoc IAaveV3Vault
    function updateTvls() external {
        _updateTvls();
    }

    /// @inheritdoc IAaveV3Vault
    function initialize(uint256 nft_, address[] memory vaultTokens_) external {
        _initialize(vaultTokens_, nft_);
        IPool pool = IAaveV3VaultGovernance(address(_vaultGovernance)).delayedProtocolParams().pool;
        _pool = pool;
        _aTokens = new address[](vaultTokens_.length);
        _tvls = new uint256[](vaultTokens_.length);
        for (uint256 i = 0; i < vaultTokens_.length; ++i) {
            address aToken = pool.getReserveData(vaultTokens_[i]).aTokenAddress;
            require(aToken != address(0), ExceptionsLibrary.ADDRESS_ZERO);
            _aTokens[i] = aToken;
        }
        _lastTvlUpdateTimestamp = block.timestamp;
    }

    // -------------------  INTERNAL, VIEW  -------------------

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
        address[] memory tokens = _aTokens;
        for (uint256 i = 0; i < tvlsLength; ++i) {
            _tvls[i] = IERC20(tokens[i]).balanceOf(address(this));
        }
        _lastTvlUpdateTimestamp = block.timestamp;
    }

    function _push(uint256[] memory tokenAmounts, bytes memory options)
        internal
        override
        returns (uint256[] memory actualTokenAmounts)
    {
        address[] memory tokens = _vaultTokens;
        uint16 referralCode = 0;
        if (options.length > 0) {
            referralCode = abi.decode(options, (uint16));
        }
        IPool pool = _pool;
        for (uint256 i = 0; i < tokens.length; ++i) {
            if (tokenAmounts[i] == 0) {
                continue;
            }
            address token = tokens[i];
            IERC20(token).safeIncreaseAllowance(address(pool), tokenAmounts[i]);
            pool.supply(token, tokenAmounts[i], address(this), referralCode);
            IERC20(token).safeApprove(address(pool), 0);
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
        address[] memory aTokens = _aTokens;
        actualTokenAmounts = new uint256[](tokenAmounts.length);
        IPool pool = _pool;
        uint256[] memory tvls = _tvls;
        for (uint256 i = 0; i < tokens.length; ++i) {
            if ((tvls[i] == 0) || (tokenAmounts[i] == 0)) {
                continue;
            }
            address token = tokens[i];
            uint256 balance = IERC20(aTokens[i]).balanceOf(address(this));
            uint256 amount = tokenAmounts[i] < balance ? tokenAmounts[i] : balance;
            actualTokenAmounts[i] = pool.withdraw(token, amount, to);
        }
        _updateTvls();
    }
}
