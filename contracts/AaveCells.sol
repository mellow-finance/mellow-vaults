// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/ITokenCells.sol";
import "./libraries/Array.sol";
import "./libraries/external/FixedPoint96.sol";
import "./Cells.sol";
import "./interfaces/external/aave/ILendingPool.sol";

contract AaveCells is IDelegatedCells, Cells {
    using SafeERC20 for IERC20;
    ILendingPool public lendingPool;

    mapping(uint256 => mapping(address => uint256)) public tokenCellsBalances;
    mapping(address => uint256) public tokenBalances;

    constructor(
        ILendingPool _lendingPool,
        string memory name,
        string memory symbol
    ) Cells(name, symbol) {
        lendingPool = _lendingPool;
    }

    function delegated(uint256 nft)
        public
        view
        override
        returns (address[] memory tokens, uint256[] memory tokenAmounts)
    {
        tokens = new address[](1);
        tokenAmounts = new uint256[](1);
        tokens[0] = managedTokens(nft)[0];
        address aToken = _getAToken(tokens[0]);
        tokenAmounts[0] =
            (IERC20(aToken).balanceOf(address(this)) * tokenCellsBalances[nft][tokens[0]]) /
            tokenBalances[tokens[0]];
    }

    function deposit(
        uint256 nft,
        address[] calldata tokens,
        uint256[] calldata tokenAmounts
    ) external override returns (uint256[] memory actualTokenAmounts) {
        require(_isApprovedOrOwner(_msgSender(), nft), "IO");
        require((tokens.length == 1) && (tokenAmounts.length == 1), "TL");
        require(tokenAmounts[0] > 0, "TA");
        require(isManagedToken(nft, tokens[0]), "MT");
        address aToken = _getAToken(tokens[0]);

        uint256 tokensToMint;
        if (tokenBalances[tokens[0]] == 0) {
            tokensToMint = tokenAmounts[0];
            // TODO: check if approval is required
            IERC20(aToken).approve(address(lendingPool), type(uint256).max);
        } else {
            tokensToMint = (tokenAmounts[0] * tokenBalances[tokens[0]]) / IERC20(aToken).balanceOf(address(this));
        }
        _allowTokenIfNecessary(tokens[0]);
        IERC20(tokens[0]).safeTransferFrom(_msgSender(), address(this), tokenAmounts[0]);
        // TODO: Check what is 0
        lendingPool.deposit(tokens[0], tokenAmounts[0], address(this), 0);
        tokenBalances[tokens[0]] += tokensToMint;
        tokenCellsBalances[nft][tokens[0]] += tokensToMint;
        actualTokenAmounts = tokenAmounts;
    }

    function withdraw(
        uint256 nft,
        address to,
        address[] calldata tokens,
        uint256[] calldata tokenAmounts
    ) external override returns (uint256[] memory actualTokenAmounts) {
        require(_isApprovedOrOwner(_msgSender(), nft), "IO");
        require((tokens.length == 1) && (tokenAmounts.length == 1), "TL");
        require(tokenAmounts[0] > 0, "TA");
        require(isManagedToken(nft, tokens[0]), "MT");
        address aToken = _getAToken(tokens[0]);
        uint256 tokensToBurn = (tokenAmounts[0] * tokenBalances[tokens[0]]) / IERC20(aToken).balanceOf(address(this));
        tokenBalances[tokens[0]] -= tokensToBurn;
        tokenCellsBalances[nft][tokens[0]] -= tokensToBurn;
        lendingPool.withdraw(tokens[0], tokenAmounts[0], to);
        actualTokenAmounts = tokenAmounts;
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
