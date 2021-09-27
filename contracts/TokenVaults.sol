// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./access/GovernanceAccessControl.sol";
import "./interfaces/ITokenVaults.sol";
import "./libraries/Array.sol";
import "./Vaults.sol";

contract TokenVaults is ITokenVaults, Vaults {
    using SafeERC20 for IERC20;

    mapping(uint256 => mapping(address => uint256)) public tokenVaultsBalances;
    mapping(address => uint256) public tokenBalances;

    constructor(string memory name, string memory symbol) Vaults(name, symbol) {}

    /// -------------------  PUBLIC, VIEW  -------------------

    function delegated(uint256 nft)
        external
        view
        override
        returns (address[] memory tokens, uint256[] memory tokenAmounts)
    {
        tokens = managedTokens(nft);
        tokenAmounts = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            tokenAmounts[i] = tokenVaultsBalances[nft][tokens[i]];
        }
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(Vaults, IERC165) returns (bool) {
        return interfaceId == type(ITokenVaults).interfaceId || super.supportsInterface(interfaceId);
    }

    /// -------------------  PUBLIC, MUTATING, NFT_OWNER  -------------------

    // @dev Can claim only free tokens
    function claimTokensToVault(
        uint256 nft,
        address[] calldata tokens,
        uint256[] calldata tokenAmounts
    ) external override {
        require(_isApprovedOrOwner(_msgSender(), nft), "IO"); // Also checks that the token exists
        require(Array.isSortedAndUnique(tokens), "SAU");
        require(tokens.length == tokenAmounts.length, "L");
        _claimTokensToVault(nft, tokens, tokenAmounts);
    }

    function deposit(
        uint256 nft,
        address[] calldata tokens,
        uint256[] calldata tokenAmounts
    ) external override returns (uint256[] memory actualTokenAmounts) {
        require(_isApprovedOrOwner(_msgSender(), nft), "IO"); // Also checks that the token exists
        require(Array.isSortedAndUnique(tokens), "SAU");
        require(tokens.length == tokenAmounts.length, "L");
        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokenAmounts[i] == 0) {
                continue;
            }
            require(isManagedToken(nft, tokens[i]));
            IERC20(tokens[i]).safeTransferFrom(_msgSender(), address(this), tokenAmounts[i]);
        }
        _claimTokensToVault(nft, tokens, tokenAmounts);
        actualTokenAmounts = tokenAmounts;
        emit Deposit(nft, tokens, actualTokenAmounts);
    }

    function withdraw(
        uint256 nft,
        address to,
        address[] calldata tokens,
        uint256[] calldata tokenAmounts
    ) external override returns (uint256[] memory actualTokenAmounts) {
        require(_isApprovedOrOwner(_msgSender(), nft), "IO"); // Also checks that the token exists
        require(Array.isSortedAndUnique(tokens), "SAU");
        require(tokens.length == tokenAmounts.length, "L");
        for (uint256 i = 0; i < tokens.length; i++) {
            _withdrawTokenFromVault(nft, to, tokens[i], tokenAmounts[i]);
        }
        actualTokenAmounts = tokenAmounts;
        emit Withdraw(nft, to, tokens, actualTokenAmounts);
    }

    /// -------------------  PRIVATE, VIEW  -------------------

    function _freeBalance(address token) internal view returns (uint256) {
        uint256 actualBalance = IERC20(token).balanceOf(address(this));
        uint256 bookBalance = tokenBalances[token];
        return actualBalance - bookBalance;
    }

    /// -------------------  PRIVATE, MUTATING  -------------------

    function _claimTokensToVault(
        uint256 nft,
        address[] memory tokens,
        uint256[] memory tokenAmounts
    ) private {
        for (uint256 i = 0; i < tokens.length; i++) {
            _claimTokenToVault(nft, tokens[i], tokenAmounts[i]);
        }
    }

    function _claimTokenToVault(
        uint256 nft,
        address token,
        uint256 tokenAmount
    ) private {
        if (tokenAmount == 0) return;
        require(isManagedToken(nft, token), "NMT"); // check that token is managed by the cell
        uint256 freeTokenAmount = _freeBalance(token);
        require(tokenAmount <= freeTokenAmount, "FTA");
        tokenVaultsBalances[nft][token] += tokenAmount;
        tokenBalances[token] += tokenAmount;
        emit TokenClaimedToVault({nft: nft, token: token, tokenAmount: tokenAmount});
    }

    function _withdrawTokenFromVault(
        uint256 nft,
        address to,
        address token,
        uint256 tokenAmount
    ) private {
        if (tokenAmount == 0) return;
        require(isManagedToken(nft, token), "NMT"); // check that token is managed by the cell
        tokenVaultsBalances[nft][token] -= tokenAmount;
        tokenBalances[token] -= tokenAmount;
        IERC20(token).safeTransfer(to, tokenAmount);
        emit TokenDisbursedFromVault({nft: nft, to: to, token: token, tokenAmount: tokenAmount});
    }

    event TokenClaimedToVault(uint256 nft, address token, uint256 tokenAmount);
    event TokenDisbursedFromVault(uint256 nft, address to, address token, uint256 tokenAmount);
}
