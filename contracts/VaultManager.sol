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

    constructor(
        string memory name,
        string memory symbol,
        IVaultFactory factory,
        bool permissionless,
        IProtocolGovernance protocolGovernance,
    ) ERC721(name, symbol) VaultManagerGovernance(permissionless, protocolGovernance) {
        _factory = factory;
    }

    function nftForVault(address vault) external view override returns (uint256) {
        return _nftIndex[vault];
    }

    function vaultForNft(uint256 nft) external view override returns (address) {
        return _vaultIndex[nft];
    }

    function createVault(
        address[] calldata tokens,
        address strategyTreasury,
        bytes calldata options
    ) external override returns (address vault, uint256 nft) {
        require(governanceParams().permissionless || _isProtocolAdmin(), "PGD");
        require(tokens.length <= governanceParams().protocolGovernance.maxTokensPerVault(), "MT");
        require(Common.isSortedAndUnique(tokens), "SAU");
        nft = _mintVaultNft();
        vault = _factory.deployVault(tokens, strategyTreasury, options);
        emit CreateVault(vault, nft, tokens, options);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(AccessControlEnumerable, ERC721, IERC165)
        returns (bool)
    {
        return interfaceId == type(IVaultManager).interfaceId || super.supportsInterface(interfaceId);
    }

    function _mintVaultNft() internal returns (uint256) {
        uint256 nft = _topVaultNft;
        _topVaultNft += 1;
        _safeMint(_msgSender(), nft);
        return nft;
    }
}
