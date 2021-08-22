// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./access/OwnerAccessControl.sol";
import "./interfaces/ITokenCells.sol";

contract TokenCells is ITokenCells, OwnerAccessControl, ERC721 {
    using SafeERC20 for IERC20;

    struct MutableTokenCellsGovernanceParams {
        bool isPublicCreateCell;
        uint256 maxTokensPerCell;
    }
    MutableTokenCellsGovernanceParams public mutableTokenCellsGovernanceParams;
    mapping(uint256 => mapping(address => uint256)) public tokenCellsBalances;
    mapping(address => uint256) public tokenBalances;
    mapping(uint256 => address[]) public tokens;
    mapping(uint256 => mapping(address => bool)) public tokensIndex;

    uint256 private _topCellNft;

    constructor(string memory name, string memory symbol) ERC721(name, symbol) {
        mutableTokenCellsGovernanceParams = MutableTokenCellsGovernanceParams({
            isPublicCreateCell: false,
            maxTokensPerCell: 10
        });
    }

    // @dev Can claim only free tokens
    function claimTokensToCell(
        uint256 cellNft,
        address[] memory tokensToClaim,
        uint256[] memory tokenAmounts
    ) public override {
        require(_isApprovedOrOwner(_msgSender(), cellNft), "IO"); // Also checks that the token exists
        for (uint256 i = 0; i < tokensToClaim.length; i++) {
            _claimTokenToCell(cellNft, tokensToClaim[i], tokenAmounts[i]);
        }
    }

    function disburseTokensFromCell(
        uint256 cellNft,
        address to,
        address[] memory tokensToDisburse,
        uint256[] memory tokenAmounts
    ) public override {
        require(_isApprovedOrOwner(_msgSender(), cellNft), "IO"); // Also checks that the token exists
        for (uint256 i = 0; i < tokensToDisburse.length; i++) {
            _disburseTokenFromCell(cellNft, to, tokensToDisburse[i], tokenAmounts[i]);
        }
    }

    function createCell(address[] memory cellTokens) external override returns (uint256) {
        require(cellTokens.length <= mutableTokenCellsGovernanceParams.maxTokensPerCell, "MT");
        uint256 cellNft = _topCellNft;
        _topCellNft += 1;
        tokens[cellNft] = cellTokens;
        for (uint256 i = 0; i < cellTokens.length; i++) {
            tokensIndex[cellNft][cellTokens[i]] = true;
        }
        _safeMint(_msgSender(), cellNft);
        return cellNft;
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

    function _claimTokenToCell(
        uint256 cellNft,
        address token,
        uint256 tokenAmount
    ) private {
        require(tokensIndex[cellNft][token], "NMT"); // check that token is managed by the cell
        uint256 freeTokenAmount = _freeBalance(token);
        require(tokenAmount <= freeTokenAmount, "FTA");
        tokenCellsBalances[cellNft][token] += tokenAmount;
        tokenBalances[token] += tokenAmount;
        emit TokenClaimedToCell({cellNft: cellNft, token: token, tokenAmount: tokenAmount});
    }

    function _disburseTokenFromCell(
        uint256 cellNft,
        address to,
        address token,
        uint256 tokenAmount
    ) internal {
        require(tokensIndex[cellNft][token], "NMT"); // check that token is managed by the cell
        if (tokenAmount == 0) return;
        tokenCellsBalances[cellNft][token] -= tokenAmount;
        tokenBalances[token] -= tokenAmount;
        IERC20(token).safeTransfer(to, tokenAmount);
        emit TokenDisbursedFromCell({cellNft: cellNft, to: to, token: token, tokenAmount: tokenAmount});
    }

    function _freeBalance(address token) internal view returns (uint256) {
        uint256 actualBalance = IERC20(token).balanceOf(address(this));
        uint256 bookBalance = tokenBalances[token];
        return actualBalance - bookBalance;
    }

    event TokenClaimedToCell(uint256 cellNft, address token, uint256 tokenAmount);
    event TokenDisbursedFromCell(uint256 cellNft, address to, address token, uint256 tokenAmount);
}
