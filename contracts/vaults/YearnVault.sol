// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.9;

import "../interfaces/external/yearn/IYearnProtocolVault.sol";
import "../interfaces/vaults/IYearnVaultGovernance.sol";
import "../interfaces/vaults/IYearnVault.sol";
import "../libraries/external/FullMath.sol";
import "./IntegrationVault.sol";

/// @notice Vault that interfaces Yearn protocol in the integration layer.
/// @dev Notes:
/// **TVL**
///
/// The TVL of the vault is updated after each deposit withdraw.
///
/// **yTokens**
/// yTokens are fixed at the token creation and addresses are taken from YearnVault governance and if missing there
/// - in YearnVaultRegistry.
/// So essentially each yToken is fixed for life of the YearnVault. If the yToken is missing for some vaultToken,
/// the YearnVault cannot be created.
///
/// **Push / Pull**
/// There are some deposit limits imposed by Yearn vaults.
/// The contract's vaultTokens are fully allowed to corresponding yTokens.

contract YearnVault is IYearnVault, IntegrationVault {
    using SafeERC20 for IERC20;
    uint256 public constant DEFAULT_MAX_LOSS = 10000; // 10000%%

    address[] private _yTokens;

    /// @notice Yearn protocol vaults used by this contract
    function yTokens() external view returns (address[] memory) {
        return _yTokens;
    }

    // -------------------  EXTERNAL, VIEW  -------------------

    /// @inheritdoc IVault
    function tvl() public view override returns (uint256[] memory minTokenAmounts, uint256[] memory maxTokenAmounts) {
        address[] memory tokens = _vaultTokens;
        minTokenAmounts = new uint256[](tokens.length);
        for (uint256 i = 0; i < _yTokens.length; ++i) {
            IYearnProtocolVault yToken = IYearnProtocolVault(_yTokens[i]);
            minTokenAmounts[i] = FullMath.mulDiv(
                yToken.balanceOf(address(this)),
                yToken.pricePerShare(),
                10**yToken.decimals()
            );
        }
        maxTokenAmounts = minTokenAmounts;
    }

    /// @inheritdoc IntegrationVault
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(IERC165, IntegrationVault)
        returns (bool)
    {
        return super.supportsInterface(interfaceId) || type(IYearnVault).interfaceId == interfaceId;
    }

    // -------------------  EXTERNAL, MUTATING  -------------------
    /// @inheritdoc IYearnVault
    function initialize(uint256 nft_, address[] memory vaultTokens_) external {
        _initialize(vaultTokens_, nft_);
        _yTokens = new address[](vaultTokens_.length);
        for (uint256 i = 0; i < vaultTokens_.length; ++i) {
            _yTokens[i] = IYearnVaultGovernance(address(msg.sender)).yTokenForToken(vaultTokens_[i]);
            require(_yTokens[i] != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        }
    }

    // -------------------  INTERNAL, VIEW  -----------------------
    function _isReclaimForbidden(address token) internal view override returns (bool) {
        uint256 len = _yTokens.length;
        for (uint256 i = 0; i < len; ++i) {
            if (_yTokens[i] == token) {
                return true;
            }
        }
        return false;
    }

    // -------------------  INTERNAL, MUTATING  -------------------

    function _push(uint256[] memory tokenAmounts, bytes memory)
        internal
        override
        returns (uint256[] memory actualTokenAmounts)
    {
        address[] memory tokens = _vaultTokens;
        actualTokenAmounts = tokenAmounts;
        for (uint256 i = 0; i < _yTokens.length; ++i) {
            if (tokenAmounts[i] == 0) {
                continue;
            }

            address token = tokens[i];
            IYearnProtocolVault yToken = IYearnProtocolVault(_yTokens[i]);
            IERC20(token).safeIncreaseAllowance(address(yToken), tokenAmounts[i]);
            try yToken.deposit(tokenAmounts[i], address(this)) returns (uint256) {} catch (bytes memory) {
                actualTokenAmounts[i] = 0;
            }
            IERC20(token).safeApprove(address(yToken), 0);
        }
    }

    function _pull(
        address to,
        uint256[] memory tokenAmounts,
        bytes memory options
    ) internal override returns (uint256[] memory actualTokenAmounts) {
        actualTokenAmounts = new uint256[](tokenAmounts.length);
        uint256 maxLoss = options.length > 0 ? abi.decode(options, (uint256)) : DEFAULT_MAX_LOSS;
        for (uint256 i = 0; i < _yTokens.length; ++i) {
            if (tokenAmounts[i] == 0) continue;

            IYearnProtocolVault yToken = IYearnProtocolVault(_yTokens[i]);
            uint256 yTokenAmount = FullMath.mulDiv(tokenAmounts[i], (10**yToken.decimals()), yToken.pricePerShare());
            uint256 balance = yToken.balanceOf(address(this));
            if (yTokenAmount > balance) {
                yTokenAmount = balance;
            }

            if (yTokenAmount == 0) continue;

            actualTokenAmounts[i] = yToken.withdraw(yTokenAmount, to, maxLoss);
        }
    }
}
