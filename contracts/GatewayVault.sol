// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IVault.sol";
import "./interfaces/IGatewayVault.sol";
import "./interfaces/IGatewayVaultGovernance.sol";
import "./Vault.sol";

contract GatewayVault is IGatewayVault, Vault {
    using SafeERC20 for IERC20;
    uint256[] private _vaultNfts;
    mapping(uint256 => uint256) private _vaultNftsIndex;
    bool initialized;

    /// @notice Creates a new contract
    /// @dev All subvault nfts must be owned by this vault before
    /// @param vaultGovernance_ Reference to VaultGovernance for this vault
    /// @param vaultTokens_ ERC20 tokens under Vault management
    constructor(IVaultGovernance vaultGovernance_, address[] memory vaultTokens_)
        Vault(vaultGovernance_, vaultTokens_)
    {}

    /// @notice Build and fixes the structure of subvaults
    /// @param vaultNfts_ nfts of the subvaults
    /// @param strategy address of the strategy contract (or strategist external account if the strategy is manual)
    function initialize(uint256[] memory vaultNfts_, address strategy) external {
        require(!initialized, "INIT");
        IVaultRegistry registry = _vaultGovernance.internalParams().registry;
        uint256 nft = registry.nftForVault(this);
        require(nft > 0, "RGST");
        require(registry.ownerOf(nft) == msg.sender, "OW");
        _vaultNfts = vaultNfts_;
        for (uint256 i = 0; i < _vaultNfts.length; i++) {
            require(registry.ownerOf(_vaultNfts[i]) == address(this), "OWT");
            registry.approve(strategy, _vaultNfts[i]);
            _vaultNftsIndex[_vaultNfts[i]] = i;
        }
        initialized = true;
    }

    /// @inheritdoc Vault
    function tvl() public view override(IVault, Vault) returns (uint256[] memory tokenAmounts) {
        IVaultRegistry registry = _vaultGovernance.internalParams().registry;
        tokenAmounts = new uint256[](_vaultTokens.length);
        for (uint256 i = 0; i < _vaultNfts.length; i++) {
            IVault vault = IVault(registry.vaultForNft(_vaultNfts[i]));
            address[] memory vTokens = vault.vaultTokens();
            uint256[] memory vTokenAmounts = vault.tvl();
            uint256[] memory pTokenAmounts = Common.projectTokenAmounts(_vaultTokens, vTokens, vTokenAmounts);
            for (uint256 j = 0; j < _vaultTokens.length; j++) {
                tokenAmounts[j] += pTokenAmounts[j];
            }
        }
    }

    /// @inheritdoc Vault
    function earnings() public view override(IVault, Vault) returns (uint256[] memory tokenAmounts) {
        address[] memory tokens = _vaultTokens;
        IVaultRegistry registry = _vaultGovernance.internalParams().registry;
        tokenAmounts = new uint256[](tokens.length);
        for (uint256 i = 0; i < _vaultNfts.length; i++) {
            IVault vault = IVault(registry.vaultForNft(_vaultNfts[i]));
            address[] memory vTokens = vault.vaultTokens();
            uint256[] memory vTokenAmounts = vault.earnings();
            uint256[] memory pTokenAmounts = Common.projectTokenAmounts(tokens, vTokens, vTokenAmounts);
            for (uint256 j = 0; j < tokens.length; j++) {
                tokenAmounts[j] += pTokenAmounts[j];
            }
        }
    }

    function vaultTvl(uint256 vaultNum) public view override returns (uint256[] memory) {
        IVaultRegistry registry = _vaultGovernance.internalParams().registry;
        IVault vault = IVault(registry.vaultForNft(_vaultNfts[vaultNum]));
        address[] memory pTokens = vault.vaultTokens();
        uint256[] memory vTokenAmounts = vault.tvl();
        return Common.projectTokenAmounts(_vaultTokens, pTokens, vTokenAmounts);
    }

    function vaultsTvl() public view override returns (uint256[][] memory tokenAmounts) {
        IVaultRegistry registry = _vaultGovernance.internalParams().registry;
        address[] memory tokens = _vaultTokens;
        tokenAmounts = new uint256[][](_vaultNfts.length);
        for (uint256 i = 0; i < _vaultNfts.length; i++) {
            IVault vault = IVault(registry.vaultForNft(_vaultNfts[i]));
            address[] memory vTokens = vault.vaultTokens();
            uint256[] memory vTokenAmounts = vault.tvl();
            uint256[] memory pTokenAmounts = Common.projectTokenAmounts(tokens, vTokens, vTokenAmounts);
            tokenAmounts[i] = new uint256[](tokens.length);
            for (uint256 j = 0; j < tokens.length; j++) {
                tokenAmounts[i][j] = pTokenAmounts[j];
            }
        }
    }

    function vaultEarnings(uint256 vaultNum) public view override returns (uint256[] memory) {
        IVaultRegistry registry = _vaultGovernance.internalParams().registry;
        IVault vault = IVault(registry.vaultForNft(_vaultNfts[vaultNum]));
        address[] memory pTokens = vault.vaultTokens();
        uint256[] memory vTokenAmounts = vault.earnings();
        return Common.projectTokenAmounts(_vaultTokens, pTokens, vTokenAmounts);
    }

    function hasSubvault(address vault) external view override returns (bool) {
        IVaultRegistry registry = _vaultGovernance.internalParams().registry;
        uint256 nft = registry.nftForVault(IVault(vault));
        return (_vaultNftsIndex[nft] > 0 || _vaultNfts[0] == nft);
    }

    function _push(
        uint256[] memory tokenAmounts,
        bool optimized,
        bytes memory options
    ) internal override returns (uint256[] memory actualTokenAmounts) {
        IVaultRegistry registry = _vaultGovernance.internalParams().registry;
        uint256[][] memory tvls = vaultsTvl();
        uint256[] memory totalTvl = new uint256[](_vaultTokens.length);
        uint256[][] memory amountsByVault = Common.splitAmounts(tokenAmounts, tvls);
        IGatewayVaultGovernance.DelayedStrategyParams memory strategyParams = IGatewayVaultGovernance(
            address(_vaultGovernance)
        ).delayedStrategyParams(_selfNft());
        if (optimized && strategyParams.redirects.length > 0) {
            for (uint256 i = 0; i < _vaultNfts.length; i++) {
                if (strategyParams.redirects[i] == 0) {
                    continue;
                }
                for (uint256 j = 0; j < _vaultTokens.length; j++) {
                    uint256 vaultIndex = _vaultNftsIndex[strategyParams.redirects[i]];
                    amountsByVault[vaultIndex][j] += amountsByVault[i][j];
                    amountsByVault[i][j] = 0;
                }
            }
        }
        bytes[] memory vaultsOptions = _parseOptions(options);
        actualTokenAmounts = new uint256[](_vaultTokens.length);
        for (uint256 i = 0; i < _vaultNfts.length; i++) {
            if (optimized && (strategyParams.redirects[i] != 0)) {
                continue;
            }
            IVault vault = IVault(registry.vaultForNft(_vaultNfts[i]));
            uint256[] memory actualVaultTokenAmounts = vault.push(
                _vaultTokens,
                amountsByVault[i],
                optimized,
                vaultsOptions[i]
            );
            for (uint256 j = 0; j < _vaultTokens.length; j++) {
                actualTokenAmounts[j] += actualVaultTokenAmounts[j];
                totalTvl[j] += tvls[i][j];
            }
        }
        uint256[] memory _limits = IGatewayVaultGovernance(address(_vaultGovernance)).strategyParams(_selfNft()).limits;
        for (uint256 i = 0; i < _vaultTokens.length; i++) {
            require(totalTvl[i] + actualTokenAmounts[i] < _limits[i], "L");
        }
    }

    function _pull(
        address to,
        uint256[] memory tokenAmounts,
        bool optimized,
        bytes memory options
    ) internal override returns (uint256[] memory actualTokenAmounts) {
        IVaultRegistry registry = _vaultGovernance.internalParams().registry;
        uint256[][] memory tvls = vaultsTvl();
        uint256[][] memory amountsByVault = Common.splitAmounts(tokenAmounts, tvls);
        uint256[] memory _redirects = IGatewayVaultGovernance(address(_vaultGovernance))
            .delayedStrategyParams(_selfNft())
            .redirects;

        if (optimized && (_redirects.length > 0)) {
            for (uint256 i = 0; i < _vaultNfts.length; i++) {
                if (_redirects[i] == 0) {
                    continue;
                }
                for (uint256 j = 0; j < _vaultTokens.length; j++) {
                    uint256 vaultIndex = _vaultNftsIndex[_redirects[i]];
                    amountsByVault[vaultIndex][j] += amountsByVault[i][j];
                    amountsByVault[i][j] = 0;
                }
            }
        }
        bytes[] memory vaultsOptions = _parseOptions(options);
        actualTokenAmounts = new uint256[](_vaultTokens.length);
        for (uint256 i = 0; i < _vaultNfts.length; i++) {
            IVault vault = IVault(registry.vaultForNft(_vaultNfts[i]));
            uint256[] memory actualVaultTokenAmounts = vault.pull(
                to,
                _vaultTokens,
                amountsByVault[i],
                optimized,
                vaultsOptions[i]
            );
            for (uint256 j = 0; j < _vaultTokens.length; j++) {
                actualTokenAmounts[j] += actualVaultTokenAmounts[j];
            }
        }
    }

    function _collectEarnings(address to, bytes memory options)
        internal
        override
        returns (uint256[] memory collectedEarnings)
    {
        IVaultRegistry registry = _vaultGovernance.internalParams().registry;
        address[] memory tokens = _vaultTokens;
        collectedEarnings = new uint256[](tokens.length);
        bytes[] memory vaultsOptions = _parseOptions(options);
        for (uint256 i = 0; i < _vaultNfts.length; i++) {
            IVault vault = IVault(registry.vaultForNft(_vaultNfts[i]));
            address[] memory vTokens = vault.vaultTokens();
            uint256[] memory vTokenAmounts = vault.collectEarnings(address(this), vaultsOptions[i]);
            uint256[] memory pTokenAmounts = Common.projectTokenAmounts(tokens, vTokens, vTokenAmounts);
            for (uint256 j = 0; j < tokens.length; j++) {
                collectedEarnings[j] += pTokenAmounts[j];
            }
        }
        uint256[] memory fees = _collectFees(collectedEarnings);
        for (uint256 i = 0; i < tokens.length; i++) {
            collectedEarnings[i] -= fees[i];
            IERC20(tokens[i]).safeTransfer(to, collectedEarnings[i]);
        }
    }

    function _collectFees(uint256[] memory collectedEarnings) internal returns (uint256[] memory collectedFees) {
        address[] memory tokens = _vaultTokens;
        collectedFees = new uint256[](tokens.length);
        IProtocolGovernance governance = _vaultGovernance.internalParams().protocolGovernance;
        address protocolTres = governance.protocolTreasury();
        uint256 protocolPerformanceFee = governance.protocolPerformanceFee();
        uint256 strategyPerformanceFee = governance.strategyPerformanceFee();
        address strategyTres = _vaultGovernance.strategyTreasury(_selfNft());
        uint256[] memory strategyFees = new uint256[](tokens.length);
        uint256[] memory protocolFees = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            IERC20 token = IERC20(tokens[i]);
            protocolFees[i] = (collectedEarnings[i] * protocolPerformanceFee) / Common.DENOMINATOR;
            strategyFees[i] = (collectedEarnings[i] * strategyPerformanceFee) / Common.DENOMINATOR;
            token.safeTransfer(strategyTres, strategyFees[i]);
            token.safeTransfer(protocolTres, protocolFees[i]);
            collectedFees[i] = protocolFees[i] + strategyFees[i];
        }
        emit CollectStrategyFees(strategyTres, tokens, strategyFees);
        emit CollectProtocolFees(protocolTres, tokens, protocolFees);
    }

    function _parseOptions(bytes memory options) internal view returns (bytes[] memory vaultOptions) {
        if (options.length == 0) {
            return new bytes[](_vaultNfts.length);
        }
        return abi.decode(options, (bytes[]));
    }

    event CollectProtocolFees(address protocolTreasury, address[] tokens, uint256[] amounts);
    event CollectStrategyFees(address strategyTreasury, address[] tokens, uint256[] amounts);
}
