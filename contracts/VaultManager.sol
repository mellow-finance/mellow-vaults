// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "./interfaces/IProtocolGovernance.sol";
import "./interfaces/IVaultManager.sol";
import "./interfaces/IVaultFactory.sol";
import "./VaultManagerGovernance.sol";

import "hardhat/console.sol";

contract VaultManager is IVaultManager, VaultManagerGovernance, ERC721 {
    uint256 private _topVaultNft = 1;

    mapping(address => uint256) private _nftIndex;
    mapping(uint256 => address) private _vaultIndex;

    constructor(
        string memory name,
        string memory symbol,
        IVaultFactory factory,
        IVaultGovernanceFactory governanceFactory,
        bool permissionless,
        IProtocolGovernance protocolGovernance
    ) ERC721(name, symbol) VaultManagerGovernance(permissionless, protocolGovernance, factory, governanceFactory) {}

    function nftForVault(address vault) external view override returns (uint256) {
        return _nftIndex[vault];
    }

    function vaultForNft(uint256 nft) public view override returns (address) {
        return _vaultIndex[nft];
    }

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

        // address[] memory tokens,
        // IVaultManager manager,
        // address treasury,
        // address admin
        vaultGovernance = governanceParams().governanceFactory.deployVaultGovernance(
            tokens,
            this,
            strategyTreasury,
            admin
        );
        vault = governanceParams().factory.deployVault(vaultGovernance, options);
        nft = _mintVaultNft(vault);
        emit CreateVault(address(vaultGovernance), address(vault), nft, tokens, options);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721, IERC165) returns (bool) {
        return interfaceId == type(IVaultManager).interfaceId || super.supportsInterface(interfaceId);
    }

    function _mintVaultNft(IVault vault) internal returns (uint256) {
        uint256 nft = _topVaultNft;
        _topVaultNft += 1;
        _nftIndex[address(vault)] = nft;
        _vaultIndex[nft] = address(vault);
        _safeMint(_msgSender(), nft);
        return nft;
    }
}
