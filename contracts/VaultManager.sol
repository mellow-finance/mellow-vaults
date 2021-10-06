// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "./interfaces/IProtocolGovernance.sol";
import "./interfaces/IVaultManager.sol";
import "./VaultManagerGovernance.sol";

abstract contract VaultManager is IVaultManager, VaultManagerGovernance, ERC721 {
    IProtocolGovernance private _protocolGovernance;
    IProtocolGovernance private _pendingProtocolGovernance;
    uint256 private _pendingProtocolGovernanceTimestamp;
    uint256 private _topVaultNft = 1;

    mapping(address => uint256) private _nftIndex;
    mapping(uint256 => address) private _vaultIndex;

    constructor(
        string memory name,
        string memory symbol,
        bool permissionless,
        IProtocolGovernance governance
    ) ERC721(name, symbol) VaultManagerGovernance(permissionless, governance) {}

    function nftForVault(address vault) external view override returns (uint256) {
        return _nftIndex[vault];
    }

    function vaultForNft(uint256 nft) external view override returns (address) {
        return _vaultIndex[nft];
    }

    function createVault(address[] memory tokens, uint256[] memory limits) external {
        require(governanceParams().permissionless || _isGovernanceOrDelegate(), "PGD");
        require(tokens.length <= governanceParams().protocolGovernance.maxTokensPerVault(), "MT");
        require(Common.isSortedAndUnique(tokens), "SAU");
        require(tokens.length == limits.length, "TPL");
        uint256 nft = _mintVaultNft();
        address vault = _deployVault(tokens, limits);
        emit CreateVault(vault, nft, tokens, limits);
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

    function _deployVault(address[] memory tokens, uint256[] memory limits) internal virtual returns (address);

    function _mintVaultNft() internal returns (uint256) {
        uint256 nft = _topVaultNft;
        _topVaultNft += 1;
        _safeMint(_msgSender(), nft);
        return nft;
    }
}
