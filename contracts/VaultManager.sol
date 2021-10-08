// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "./interfaces/IProtocolGovernance.sol";
import "./interfaces/IVaultManager.sol";
import "./interfaces/IVaultFactory.sol";
import "./VaultManagerGovernance.sol";

contract VaultManager is IVaultManager, VaultManagerGovernance, ERC721 {
    IProtocolGovernance private _protocolGovernance;
    IProtocolGovernance private _pendingProtocolGovernance;
    uint256 private _pendingProtocolGovernanceTimestamp;
    uint256 private _topVaultNft = 1;
    IVaultFactory private _factory;

    mapping(address => uint256) private _nftIndex;
    mapping(uint256 => address) private _vaultIndex;

    constructor(
        string memory name,
        string memory symbol,
        IVaultFactory factory,
        bool permissionless,
        IProtocolGovernance governance
    ) ERC721(name, symbol) VaultManagerGovernance(permissionless, governance) {
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
        uint256[] calldata limits,
        address strategyTreasury,
        bytes calldata options
    ) external override returns (address vault, uint256 nft) {
        require(governanceParams().permissionless || _isGovernanceOrDelegate(), "PGD");
        require(tokens.length <= governanceParams().protocolGovernance.maxTokensPerVault(), "MT");
        require(Common.isSortedAndUnique(tokens), "SAU");
        require(tokens.length == limits.length, "TPL");
        nft = _mintVaultNft();
        vault = _factory.deployVault(tokens, limits, strategyTreasury, options);
        emit CreateVault(vault, nft, tokens, limits, options);
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
