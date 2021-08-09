// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;

import "./interfaces/ITokensVault.sol";
import "./libraries/Array.sol";

contract TokensVault is ITokensVault {
    IERC20[] private _tokens;
    mapping(IERC20 => bool) _tokenIndex;

    constructor(IERC20[] memory tokenList) {
        require(tokenList.length != 0, "ETL");
        Array.bubble_sort_ercs(tokenList);
        for (uint256 i = 0; i < tokenList.length; i++) {
            IERC20 token = tokenList[i];
            require(!_tokenIndex[token], "TE");
            _tokenIndex[token] = true;
        }
        _tokens = tokenList;
    }

    function tokensCount() external view override returns (uint256) {
        return _tokens.length;
    }

    function tokens() external view override returns (IERC20[] memory) {
        return _tokens;
    }

    function hasToken(IERC20 token) external view override returns (bool) {
        return _tokenIndex[token];
    }

    function ownTokenAmounts() external view override returns (uint256[] memory) {
        uint256[] memory tokenAmounts = new uint256[](_tokens.length);
        for (uint256 i = 0; i < _tokens.length; i++) {
            tokenAmounts[i] = _tokens[i].balanceOf(address(this));
        }
        return tokenAmounts;
    }
}
