// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IVault.sol";
import "./interfaces/IGatewayVault.sol";
import "./interfaces/IGatewayVaultGovernance.sol";
import "./Vault.sol";

/// @notice Vault that combines several integration layer Vaults into one Vault.
contract GatewayVault is IGatewayVault, Vault {
    using SafeERC20 for IERC20;
    uint256[] internal _subvaultNfts;
    mapping(uint256 => uint256) internal _subvaultNftsIndex;

    /// @notice Creates a new contract.
    /// @dev All subvault nfts must be owned by this vault before.
    /// @param vaultGovernance_ Reference to VaultGovernance for this vault
    /// @param vaultTokens_ ERC20 tokens under Vault management
    constructor(IVaultGovernance vaultGovernance_, address[] memory vaultTokens_)
        Vault(vaultGovernance_, vaultTokens_)
    {}

    /// @inheritdoc IGatewayVault
    function subvaultNfts() external view returns (uint256[] memory) {
        return _subvaultNfts;
    }

    /// @inheritdoc Vault
    function tvl() public view override(IVault, Vault) returns (uint256[] memory tokenAmounts) {
        IVaultRegistry registry = _vaultGovernance.internalParams().registry;
        tokenAmounts = new uint256[](_vaultTokens.length);
        for (uint256 i = 0; i < _subvaultNfts.length; i++) {
            IVault vault = IVault(registry.vaultForNft(_subvaultNfts[i]));
            address[] memory vTokens = vault.vaultTokens();
            uint256[] memory vTokenAmounts = vault.tvl();
            uint256[] memory pTokenAmounts = Common.projectTokenAmounts(_vaultTokens, vTokens, vTokenAmounts);
            for (uint256 j = 0; j < _vaultTokens.length; j++) {
                tokenAmounts[j] += pTokenAmounts[j];
            }
        }
    }

    /// @inheritdoc IGatewayVault
    function subvaultTvl(uint256 vaultNum) public view override returns (uint256[] memory) {
        IVaultRegistry registry = _vaultGovernance.internalParams().registry;
        IVault vault = IVault(registry.vaultForNft(_subvaultNfts[vaultNum]));
        address[] memory pTokens = vault.vaultTokens();
        uint256[] memory vTokenAmounts = vault.tvl();
        return Common.projectTokenAmounts(_vaultTokens, pTokens, vTokenAmounts);
    }

    /// @inheritdoc IGatewayVault
    function subvaultsTvl() public view override returns (uint256[][] memory tokenAmounts) {
        IVaultRegistry registry = _vaultGovernance.internalParams().registry;
        address[] memory tokens = _vaultTokens;
        tokenAmounts = new uint256[][](_subvaultNfts.length);
        for (uint256 i = 0; i < _subvaultNfts.length; i++) {
            IVault vault = IVault(registry.vaultForNft(_subvaultNfts[i]));
            address[] memory vTokens = vault.vaultTokens();
            uint256[] memory vTokenAmounts = vault.tvl();
            uint256[] memory pTokenAmounts = Common.projectTokenAmounts(tokens, vTokens, vTokenAmounts);
            tokenAmounts[i] = new uint256[](tokens.length);
            for (uint256 j = 0; j < tokens.length; j++) {
                tokenAmounts[i][j] = pTokenAmounts[j];
            }
        }
    }

    /// @inheritdoc IGatewayVault
    function hasSubvault(address vault) external view override returns (bool) {
        IVaultRegistry registry = _vaultGovernance.internalParams().registry;
        uint256 nft = registry.nftForVault(vault);
        return (_subvaultNftsIndex[nft] > 0 || _subvaultNfts[0] == nft);
    }

    /// @inheritdoc IGatewayVault
    function addSubvaults(uint256[] memory nfts) external {
        require(msg.sender == address(_vaultGovernance), "RVG");
        require(_subvaultNfts.length == 0, "SBIN");
        require(nfts.length > 0, "SBL");
        for (uint256 i = 0; i < nfts.length; i++) {
            require(nfts[i] > 0, "NFT0");
            _subvaultNfts.push(nfts[i]);
            _subvaultNftsIndex[nfts[i]] = i;
        }
    }

    function _push(uint256[] memory tokenAmounts, bytes memory options)
        internal
        override
        returns (uint256[] memory actualTokenAmounts)
    {
        require(_subvaultNfts.length > 0, "INIT");
        bool optimized;
        bytes[] memory vaultsOptions;
        (optimized, vaultsOptions) = _parseOptions(options);

        IVaultRegistry registry = _vaultGovernance.internalParams().registry;
        uint256[][] memory tvls = subvaultsTvl();
        uint256[] memory totalTvl = new uint256[](_vaultTokens.length);
        uint256[][] memory amountsByVault = Common.splitAmounts(tokenAmounts, tvls);
        IGatewayVaultGovernance.DelayedStrategyParams memory strategyParams = IGatewayVaultGovernance(
            address(_vaultGovernance)
        ).delayedStrategyParams(_selfNft());
        if (optimized && strategyParams.redirects.length > 0) {
            for (uint256 i = 0; i < _subvaultNfts.length; i++) {
                if (strategyParams.redirects[i] == 0) {
                    continue;
                }
                for (uint256 j = 0; j < _vaultTokens.length; j++) {
                    uint256 vaultIndex = _subvaultNftsIndex[strategyParams.redirects[i]];
                    amountsByVault[vaultIndex][j] += amountsByVault[i][j];
                    amountsByVault[i][j] = 0;
                }
            }
        }
        actualTokenAmounts = new uint256[](_vaultTokens.length);
        for (uint256 i = 0; i < _subvaultNfts.length; i++) {
            if (optimized && (strategyParams.redirects[i] != 0)) {
                continue;
            }
            IVault vault = IVault(registry.vaultForNft(_subvaultNfts[i]));
            for (uint256 j = 0; j < _vaultTokens.length; j++) {
                if (amountsByVault[i][j] > 0) {
                    _allowTokenIfNecessary(_vaultTokens[j], address(vault));
                }
            }
            uint256[] memory actualVaultTokenAmounts = vault.transferAndPush(
                address(this),
                _vaultTokens,
                amountsByVault[i],
                vaultsOptions[i]
            );
            for (uint256 j = 0; j < _vaultTokens.length; j++) {
                actualTokenAmounts[j] += actualVaultTokenAmounts[j];
                totalTvl[j] += tvls[i][j];
            }
        }
        uint256[] memory _limits = IGatewayVaultGovernance(address(_vaultGovernance)).strategyParams(_selfNft()).limits;
        for (uint256 i = 0; i < _vaultTokens.length; i++) {
            require(totalTvl[i] + actualTokenAmounts[i] < _limits[i], "LIM");
        }
    }

    function _pull(
        address to,
        uint256[] memory tokenAmounts,
        bytes memory options
    ) internal override returns (uint256[] memory actualTokenAmounts) {
        (bool optimized, bytes[] memory vaultsOptions) = _parseOptions(options);

        require(_subvaultNfts.length > 0, "INIT");
        IVaultRegistry registry = _vaultGovernance.internalParams().registry;
        uint256[][] memory tvls = subvaultsTvl();
        uint256[][] memory amountsByVault = Common.splitAmounts(tokenAmounts, tvls);
        uint256[] memory _redirects = IGatewayVaultGovernance(address(_vaultGovernance))
            .delayedStrategyParams(_selfNft())
            .redirects;

        if (optimized && (_redirects.length > 0)) {
            for (uint256 i = 0; i < _subvaultNfts.length; i++) {
                if (_redirects[i] == 0) {
                    continue;
                }
                for (uint256 j = 0; j < _vaultTokens.length; j++) {
                    uint256 vaultIndex = _subvaultNftsIndex[_redirects[i]];
                    amountsByVault[vaultIndex][j] += amountsByVault[i][j];
                    amountsByVault[i][j] = 0;
                }
            }
        }
        actualTokenAmounts = new uint256[](_vaultTokens.length);
        for (uint256 i = 0; i < _subvaultNfts.length; i++) {
            IVault vault = IVault(registry.vaultForNft(_subvaultNfts[i]));
            uint256[] memory actualVaultTokenAmounts = vault.pull(
                to,
                _vaultTokens,
                amountsByVault[i],
                vaultsOptions[i]
            );
            for (uint256 j = 0; j < _vaultTokens.length; j++) {
                actualTokenAmounts[j] += actualVaultTokenAmounts[j];
            }
        }
    }

    function _allowTokenIfNecessary(address token, address to) internal {
        if (IERC20(token).allowance(address(to), address(this)) < type(uint256).max / 2) {
            IERC20(token).approve(address(to), type(uint256).max);
        }
    }

    function _parseOptions(bytes memory options) internal view returns (bool, bytes[] memory) {
        if (options.length == 0) {
            return (false, new bytes[](_subvaultNfts.length));
        }
        return abi.decode(options, (bool, bytes[]));
    }

    event CollectProtocolFees(address protocolTreasury, address[] tokens, uint256[] amounts);
    event CollectStrategyFees(address strategyTreasury, address[] tokens, uint256[] amounts);
}
