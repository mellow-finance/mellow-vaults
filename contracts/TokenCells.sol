// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./access/OwnerAccessControl.sol";
import "./interfaces/ITokenCells.sol";
import "./libraries/Array.sol";

contract TokenCells is ITokenCells, OwnerAccessControl, ERC721 {
    using SafeERC20 for IERC20;

    bool public isPublicCreateCell;
    uint256 public maxTokensPerCell;

    mapping(uint256 => mapping(address => uint256)) public tokenCellsBalances;
    mapping(address => uint256) public tokenBalances;
    mapping(uint256 => address[]) private _managedTokens;
    mapping(uint256 => mapping(address => bool)) public managedTokensIndex;

    uint256 private _topCellNft;

    constructor(string memory name, string memory symbol) ERC721(name, symbol) {
        maxTokensPerCell = 10;
    }

    function managedTokens(uint256 nft) external view override returns (address[] memory) {
        return _managedTokens[nft];
    }

    function delegated(uint256 nft)
        external
        view
        override
        returns (address[] memory tokens, uint256[] memory tokenAmounts)
    {
        tokens = _managedTokens[nft];
        tokenAmounts = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            tokenAmounts[i] = tokenCellsBalances[nft][tokens[i]];
        }
    }

    // @dev Can claim only free tokens
    function claimTokensToCell(
        uint256 nft,
        address[] calldata tokens,
        uint256[] calldata tokenAmounts
    ) external override {
        require(_isApprovedOrOwner(_msgSender(), nft), "IO"); // Also checks that the token exists
        _claimTokensToCell(nft, tokens, tokenAmounts);
    }

    function deposit(
        uint256 nft,
        address[] calldata tokens,
        uint256[] calldata tokenAmounts
    ) external override returns (uint256[] memory actualTokenAmounts) {
        require(tokens.length == tokenAmounts.length, "L");
        require(_isApprovedOrOwner(_msgSender(), nft), "IO"); // Also checks that the token exists
        for (uint256 i = 0; i < tokens.length; i++) {
            IERC20(tokens[i]).safeTransferFrom(tokens[i], address(this), tokenAmounts[i]);
        }
        _claimTokensToCell(nft, tokens, tokenAmounts);
        actualTokenAmounts = tokenAmounts;
    }

    function withdraw(
        uint256 nft,
        address to,
        address[] calldata tokens,
        uint256[] calldata tokenAmounts
    ) external override returns (uint256[] memory actualTokenAmounts) {
        require(tokens.length == tokenAmounts.length, "L");
        require(_isApprovedOrOwner(_msgSender(), nft), "IO"); // Also checks that the token exists
        for (uint256 i = 0; i < tokens.length; i++) {
            _withdrawTokenFromCell(nft, to, tokens[i], tokenAmounts[i]);
        }
        actualTokenAmounts = tokenAmounts;
    }

    function createCell(address[] memory cellTokens) external returns (uint256) {
        require(isPublicCreateCell || hasRole(OWNER_ROLE, _msgSender()), "FB");
        require(cellTokens.length <= maxTokensPerCell, "MT");
        uint256 nft = _topCellNft;
        _topCellNft += 1;
        Array.bubbleSort(cellTokens);
        _managedTokens[nft] = cellTokens;
        for (uint256 i = 0; i < cellTokens.length; i++) {
            managedTokensIndex[nft][cellTokens[i]] = true;
        }
        _safeMint(_msgSender(), nft);
        return nft;
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC721, IERC165, AccessControlEnumerable)
        returns (bool)
    {
        return interfaceId == type(ITokenCells).interfaceId || super.supportsInterface(interfaceId);
    }

    function _claimTokensToCell(
        uint256 nft,
        address[] calldata tokens,
        uint256[] calldata tokenAmounts
    ) private {
        require(tokens.length == tokenAmounts.length, "L");
        for (uint256 i = 0; i < tokens.length; i++) {
            _claimTokenToCell(nft, tokens[i], tokenAmounts[i]);
        }
    }

    function _claimTokenToCell(
        uint256 nft,
        address token,
        uint256 tokenAmount
    ) private {
        require(managedTokensIndex[nft][token], "NMT"); // check that token is managed by the cell
        uint256 freeTokenAmount = _freeBalance(token);
        require(tokenAmount <= freeTokenAmount, "FTA");
        tokenCellsBalances[nft][token] += tokenAmount;
        tokenBalances[token] += tokenAmount;
        emit TokenClaimedToCell({nft: nft, token: token, tokenAmount: tokenAmount});
    }

    function _withdrawTokenFromCell(
        uint256 nft,
        address to,
        address token,
        uint256 tokenAmount
    ) private {
        require(managedTokensIndex[nft][token], "NMT"); // check that token is managed by the cell
        if (tokenAmount == 0) return;
        tokenCellsBalances[nft][token] -= tokenAmount;
        tokenBalances[token] -= tokenAmount;
        IERC20(token).safeTransfer(to, tokenAmount);
        emit TokenDisbursedFromCell({nft: nft, to: to, token: token, tokenAmount: tokenAmount});
    }

    function _freeBalance(address token) internal view returns (uint256) {
        uint256 actualBalance = IERC20(token).balanceOf(address(this));
        uint256 bookBalance = tokenBalances[token];
        return actualBalance - bookBalance;
    }

    event TokenClaimedToCell(uint256 nft, address token, uint256 tokenAmount);
    event TokenDisbursedFromCell(uint256 nft, address to, address token, uint256 tokenAmount);
}
