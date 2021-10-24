// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "./interfaces/IProtocolGovernance.sol";
import "./interfaces/IVaultManager.sol";
import "./interfaces/IVaultFactory.sol";
import "./VaultManagerGovernance.sol";

contract VaultManager is IVaultManager, VaultManagerGovernance, ERC721 {
    uint256 private _topVaultNft = 1;

    mapping(address => uint256) private _nftIndex;
    mapping(uint256 => address) private _vaultIndex;

    /// @notice Creates a new contract
    /// @param name Name of the ERC-721 token
    /// @param symbol Symbol of the ERC-721 token
    /// @param factory Vault Factory reference
    /// @param governanceFactory VaultGovernance Factory reference
    /// @param permissionless Anyone can create a new vault
    /// @param protocolGovernance Refernce to the Governance of the protocol
    constructor(
        string memory name,
        string memory symbol,
        IVaultFactory factory,
        IVaultGovernanceFactory governanceFactory,
        bool permissionless,
        IProtocolGovernance protocolGovernance
    ) ERC721(name, symbol) VaultManagerGovernance(permissionless, protocolGovernance, factory, governanceFactory) {}

    /// @inheritdoc IVaultManager
    function nftForVault(address vault) external view override returns (uint256) {
        return _nftIndex[vault];
    }

    /// @inheritdoc IVaultManager
    function vaultForNft(uint256 nft) public view override returns (address) {
        return _vaultIndex[nft];
    }

    /// @inheritdoc IVaultManager
    function createVault(
        address[] calldata tokens,
        address strategyTreasury,
        address admin,
        bytes memory options
    )
        external
        override
        returns (
            IVaultGovernance vaultGovernance,
            IVault vault,
            uint256 nft
        )
    {
        require(governanceParams().permissionless || _isProtocolAdmin(), "PGD");
        require(tokens.length <= governanceParams().protocolGovernance.maxTokensPerVault(), "MT");
        require(Common.isSortedAndUnique(tokens), "SAU");
        nft = _mintVaultNft();

        vaultGovernance = governanceParams().governanceFactory.deployVaultGovernance(
            tokens,
            this,
            strategyTreasury,
            admin
        );
        vault = governanceParams().factory.deployVault(vaultGovernance, options);
        emit CreateVault(address(vaultGovernance), address(vault), nft, tokens, options);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721, IERC165) returns (bool) {
        return interfaceId == type(IVaultManager).interfaceId || super.supportsInterface(interfaceId);
    }

    function _mintVaultNft() internal returns (uint256) {
        uint256 nft = _topVaultNft;
        _topVaultNft += 1;
        _safeMint(_msgSender(), nft);
        return nft;
    }
}
