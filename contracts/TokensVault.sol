// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;

import "./interfaces/ITokensVault.sol";

contract TokensVault is ITokensVault {
    IERC20[] private _tokens;

    constructor(IERC20[] memory tokenList) {
        require(tokenList.length != 0);
        _tokens = tokenList;
    }

    function tokensCount() external view override returns (uint256) {
        return _tokens.length;
    }

    function tokens() external view override returns (IERC20[] memory) {
        return _tokens;
    }

    function ownTokenAmounts() external view override returns (uint256[] memory) {
        uint256[] memory tokenAmounts = new uint256[](_tokens.length);
        for (uint256 i = 0; i < _tokens.length; i++) {
            tokenAmounts[i] = _tokens[i].balanceOf(address(this));
        }
        return tokenAmounts;
    }
}
