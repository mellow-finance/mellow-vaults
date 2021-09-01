// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import "./interfaces/ITokensEntity.sol";
import "./libraries/Array.sol";

contract TokensEntity is ITokensEntity {
    address[] private _tokens;
    mapping(address => bool) _tokenIndex;

    constructor(address[] memory tokenList) {
        require(tokenList.length != 0, "ETL");
        Array.bubbleSort(tokenList);
        for (uint256 i = 0; i < tokenList.length; i++) {
            address token = tokenList[i];
            require(!_tokenIndex[token], "TE");
            _tokenIndex[token] = true;
        }
        _tokens = tokenList;
    }

    function tokensCount() external view override returns (uint256) {
        return _tokens.length;
    }

    function tokens() external view override returns (address[] memory) {
        return _tokens;
    }

    function hasToken(address token) external view override returns (bool) {
        return _tokenIndex[token];
    }

    function tokenAmountsBalance() external view override returns (uint256[] memory) {
        uint256[] memory tokenAmounts = new uint256[](_tokens.length);
        for (uint256 i = 0; i < _tokens.length; i++) {
            tokenAmounts[i] = IERC20(_tokens[i]).balanceOf(address(this));
        }
        return tokenAmounts;
    }
}
