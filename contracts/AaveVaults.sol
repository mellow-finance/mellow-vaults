// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./libraries/Common.sol";
import "./libraries/external/FixedPoint96.sol";
import "./Vaults.sol";
import "./interfaces/external/aave/ILendingPool.sol";

contract AaveVaults is Vaults {
    using SafeERC20 for IERC20;
    ILendingPool public lendingPool;

    mapping(uint256 => mapping(address => uint256)) public tokenVaultsBalances;
    mapping(address => uint256) public tokenBalances;

    constructor(
        ILendingPool _lendingPool,
        string memory name,
        string memory symbol,
        address _protocolGovernance
    ) Vaults(name, symbol, _protocolGovernance) {
        lendingPool = _lendingPool;
    }

    function vaultTVL(uint256 nft)
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

    function _getAToken(address token) internal view returns (address) {
        DataTypes.ReserveData memory data = lendingPool.getReserveData(token);
        return data.aTokenAddress;
    }

    function _allowTokenIfNecessary(address token) internal {
        // Since tokens are not stored at contract address after any tx - it's safe to give unlimited approval
        if (IERC20(token).allowance(address(this), address(lendingPool)) < type(uint256).max / 2) {
            IERC20(token).approve(address(lendingPool), type(uint256).max);
        }
    }

    /// -------------------  PRIVATE, MUTATING  -------------------

    function _push(
        uint256 nft,
        address[] memory tokens,
        uint256[] memory tokenAmounts
    ) internal override returns (uint256[] memory actualTokenAmounts) {
        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokenAmounts[i] == 0) {
                continue;
            }
            address aToken = _getAToken(tokens[i]);
            _allowTokenIfNecessary(tokens[i]);
            uint256 tokensToMint;
            if (tokenBalances[tokens[i]] == 0) {
                tokensToMint = tokenAmounts[i];
            } else {
                tokensToMint = (tokenAmounts[i] * tokenBalances[tokens[i]]) / IERC20(aToken).balanceOf(address(this));
            }

            IERC20(tokens[i]).safeTransferFrom(_msgSender(), address(this), tokenAmounts[i]);
            // TODO: Check what is 0
            lendingPool.deposit(tokens[i], tokenAmounts[i], address(this), 0);
            tokenBalances[tokens[i]] += tokensToMint;
            tokenVaultsBalances[nft][tokens[i]] += tokensToMint;
        }
        actualTokenAmounts = tokenAmounts;
    }

    function _pull(
        uint256 nft,
        address to,
        address[] memory tokens,
        uint256[] memory tokenAmounts
    ) internal override returns (uint256[] memory actualTokenAmounts) {
        for (uint256 i = 0; i < tokens.length; i++) {
            address aToken = _getAToken(tokens[i]);
            uint256 tokensToBurn = (tokenAmounts[i] * tokenBalances[tokens[i]]) /
                IERC20(aToken).balanceOf(address(this));
            if (tokensToBurn == 0) {
                continue;
            }
            tokenBalances[tokens[i]] -= tokensToBurn;
            tokenVaultsBalances[nft][tokens[i]] -= tokensToBurn;
            lendingPool.withdraw(tokens[i], tokenAmounts[i], to);
        }
        actualTokenAmounts = tokenAmounts;
    }
}
