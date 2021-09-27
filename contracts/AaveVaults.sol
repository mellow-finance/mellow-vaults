// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/ITokenVaults.sol";
import "./libraries/Array.sol";
import "./libraries/external/FixedPoint96.sol";
import "./Vaults.sol";
import "./interfaces/external/aave/ILendingPool.sol";

contract AaveVaults is IDelegatedVaults, Vaults {
    using SafeERC20 for IERC20;
    ILendingPool public lendingPool;

    mapping(uint256 => mapping(address => uint256)) public tokenVaultsBalances;
    mapping(address => uint256) public tokenBalances;

    constructor(
        ILendingPool _lendingPool,
        string memory name,
        string memory symbol
    ) Vaults(name, symbol) {
        lendingPool = _lendingPool;
    }

    function delegated(uint256 nft)
        public
        view
        override
        returns (address[] memory tokens, uint256[] memory tokenAmounts)
    {
        tokens = managedTokens(nft);
        tokenAmounts = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            address aToken = _getAToken(tokens[i]);
            if (tokenBalances[tokens[i]] == 0) {
                tokenAmounts[i] = 0;
            } else {
                tokenAmounts[i] =
                    (IERC20(aToken).balanceOf(address(this)) * tokenVaultsBalances[nft][tokens[i]]) /
                    tokenBalances[tokens[i]];
            }
        }
    }

    function deposit(
        uint256 nft,
        address[] calldata tokens,
        uint256[] calldata tokenAmounts
    ) external override returns (uint256[] memory actualTokenAmounts) {
        require(_isApprovedOrOwner(_msgSender(), nft), "IO");
        address[] memory pTokens = managedTokens(nft);
        uint256[] memory pTokenAmounts = Array.projectTokenAmounts(pTokens, tokens, tokenAmounts);
        for (uint256 i = 0; i < pTokens.length; i++) {
            if (pTokenAmounts[i] == 0) {
                continue;
            }
            address aToken = _getAToken(pTokens[i]);
            _allowTokenIfNecessary(pTokens[i]);
            uint256 tokensToMint;
            if (tokenBalances[pTokens[i]] == 0) {
                tokensToMint = pTokenAmounts[i];
            } else {
                tokensToMint = (pTokenAmounts[i] * tokenBalances[pTokens[i]]) / IERC20(aToken).balanceOf(address(this));
            }
            
            IERC20(pTokens[i]).safeTransferFrom(_msgSender(), address(this), pTokenAmounts[i]);
            // TODO: Check what is 0
            lendingPool.deposit(pTokens[i], pTokenAmounts[i], address(this), 0);
            tokenBalances[pTokens[i]] += tokensToMint;
            tokenVaultsBalances[nft][pTokens[i]] += tokensToMint;

        }
        actualTokenAmounts = tokenAmounts;
        emit Deposit(nft, tokens, actualTokenAmounts);
    }

    function withdraw(
        uint256 nft,
        address to,
        address[] calldata tokens,
        uint256[] calldata tokenAmounts
    ) external override returns (uint256[] memory actualTokenAmounts) {
        require(_isApprovedOrOwner(_msgSender(), nft), "IO");
        address[] memory pTokens = managedTokens(nft);
        uint256[] memory pTokenAmounts = Array.projectTokenAmounts(pTokens, tokens, tokenAmounts);
        for (uint256 i = 0; i < pTokens.length; i++) {
            address aToken = _getAToken(pTokens[i]);
            uint256 tokensToBurn = (pTokenAmounts[i] * tokenBalances[pTokens[i]]) / IERC20(aToken).balanceOf(address(this));
            if (tokensToBurn == 0) {
                continue;
            }
            tokenBalances[pTokens[i]] -= tokensToBurn;
            tokenVaultsBalances[nft][pTokens[i]] -= tokensToBurn;
            lendingPool.withdraw(pTokens[i], pTokenAmounts[i], to);
        }
        actualTokenAmounts = tokenAmounts;
        emit Withdraw(nft, to, tokens, actualTokenAmounts);
    }

    function _getAToken(address token) internal view returns (address) {
        DataTypes.ReserveData memory data = lendingPool.getReserveData(token);
        return data.aTokenAddress;
    }

    function _allowTokenIfNecessary(address token) internal {
        // Since tokens are not stored at contract address after any tx - it's safe to give unlimited approval
        if (IERC20(token).allowance(address(lendingPool), address(this)) < type(uint256).max / 2) {
            IERC20(token).approve(address(lendingPool), type(uint256).max);
        }
    }

}
