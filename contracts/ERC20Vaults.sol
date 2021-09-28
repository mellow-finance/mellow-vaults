// SPDX-License-Identifier: MIT
pragma solidity 0.8.8;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./access/GovernanceAccessControl.sol";
import "./interfaces/ITokenVaults.sol";
import "./libraries/Array.sol";
import "./Vaults.sol";

contract ERC20Vaults is Vaults {
    using SafeERC20 for IERC20;

    mapping(uint256 => mapping(address => uint256)) public tokenVaultsBalances;
    mapping(address => uint256) public tokenBalances;

    constructor(
        string memory name,
        string memory symbol,
        address _protocolGovernance
    ) Vaults(name, symbol, _protocolGovernance) {}

    /// -------------------  PUBLIC, VIEW  -------------------

    function vaultTVL(uint256 nft)
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

    /// -------------------  PRIVATE, VIEW  -------------------

    function _freeBalance(address token) internal view returns (uint256) {
        uint256 actualBalance = IERC20(token).balanceOf(address(this));
        uint256 bookBalance = tokenBalances[token];
        return actualBalance > bookBalance ? actualBalance - bookBalance : 0;
    }

    /// -------------------  PRIVATE, MUTATING  -------------------

    function _push(
        uint256 nft,
        address[] memory tokens,
        uint256[] memory tokenAmounts
    ) internal override returns (uint256[] memory actualTokenAmounts) {
        actualTokenAmounts = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            uint256 tokenAmount = tokenAmounts[i];
            if (tokenAmount == 0) {
                actualTokenAmounts[i] = 0;
                continue;
            }
            address token = tokens[i];
            require(tokenAmount <= _freeBalance(token), "FTA");
            tokenVaultsBalances[nft][token] += tokenAmount;
            tokenBalances[token] += tokenAmount;
            actualTokenAmounts[i] = tokenAmount;
        }
    }

    function _pull(
        uint256 nft,
        address to,
        address[] memory tokens,
        uint256[] memory tokenAmounts
    ) internal override returns (uint256[] memory actualTokenAmounts) {
        actualTokenAmounts = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            uint256 tokenAmount = tokenAmounts[i];
            if (tokenAmount == 0) {
                actualTokenAmounts[i] = 0;
                continue;
            }
            address token = tokens[i];
            tokenVaultsBalances[nft][token] -= tokenAmount;
            tokenBalances[token] -= tokenAmount;
            IERC20(token).safeTransfer(to, tokenAmount);
            actualTokenAmounts[i] = tokenAmount;
        }
    }
}
