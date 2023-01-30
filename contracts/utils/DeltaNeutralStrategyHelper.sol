// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.9;

import "../strategies/DeltaNeutralStrategy.sol";
import "../libraries/ExceptionsLibrary.sol";

import "../interfaces/vaults/IAaveVault.sol";
import "../interfaces/vaults/IERC20Vault.sol";
import "../interfaces/vaults/IUniV3Vault.sol";

import "../libraries/external/FullMath.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract DeltaNeutralStrategyHelper {
    using SafeERC20 for IERC20;

    uint32 constant D9 = 10**9;
    uint256 public constant Q96 = 1 << 96;

    IERC20Vault public erc20Vault;
    IUniV3Vault public uniV3Vault;
    IAaveVault public aaveVault;
    INonfungiblePositionManager public positionManager;

    DeltaNeutralStrategy public owner;

    address[] public tokens;

    function setParams(
        IERC20Vault erc20Vault_,
        IUniV3Vault uniV3Vault_,
        IAaveVault aaveVault_,
        INonfungiblePositionManager positionManager_
    ) external {
        erc20Vault = erc20Vault_;
        uniV3Vault = uniV3Vault_;
        aaveVault = aaveVault_;
        positionManager = positionManager_;

        address[] memory erc20Tokens = erc20Vault.vaultTokens();
        address[] memory aaveTokens = aaveVault.vaultTokens();
        address[] memory uniV3Tokens = uniV3Vault.vaultTokens();
        require(aaveTokens.length == 2, ExceptionsLibrary.INVALID_LENGTH);
        require(erc20Tokens.length == 2, ExceptionsLibrary.INVALID_LENGTH);
        require(uniV3Tokens.length == 2, ExceptionsLibrary.INVALID_LENGTH);

        require(uniV3Tokens[0] == aaveTokens[0], ExceptionsLibrary.INVARIANT);
        require(erc20Tokens[0] == aaveTokens[0], ExceptionsLibrary.INVARIANT);
        require(uniV3Tokens[1] == aaveTokens[1], ExceptionsLibrary.INVARIANT);
        require(erc20Tokens[1] == aaveTokens[1], ExceptionsLibrary.INVARIANT);

        owner = DeltaNeutralStrategy(msg.sender);

        tokens = uniV3Tokens;
    }

    function calcWithdrawParams(bytes memory withdrawOptions)
        external
        returns (
            uint256 totalToken0,
            uint256 totalToken1,
            uint256 balanceToken0,
            uint256 debtToken1
        )
    {
        require(withdrawOptions.length == 32, ExceptionsLibrary.INVALID_VALUE);
        uint256 shareOfCapitalQ96 = abi.decode(withdrawOptions, (uint256));

        (, , , , , , , uint128 liquidity, , , , ) = positionManager.positions(uniV3Vault.uniV3Nft());

        uniV3Vault.collectEarnings();

        totalToken0 = FullMath.mulDiv(IERC20(tokens[0]).balanceOf(address(erc20Vault)), shareOfCapitalQ96, Q96);
        totalToken1 = FullMath.mulDiv(IERC20(tokens[1]).balanceOf(address(erc20Vault)), shareOfCapitalQ96, Q96);

        uint256[] memory pullFromUni = uniV3Vault.liquidityToTokenAmounts(
            uint128(FullMath.mulDiv(liquidity, shareOfCapitalQ96, Q96))
        );

        pullFromUni = owner.pullFromUniswap(pullFromUni);

        totalToken0 += pullFromUni[0];
        totalToken1 += pullFromUni[1];

        balanceToken0 = FullMath.mulDiv(
            IERC20(aaveVault.aTokens(0)).balanceOf(address(aaveVault)),
            shareOfCapitalQ96,
            Q96
        );
        debtToken1 = FullMath.mulDiv(aaveVault.getDebt(1), shareOfCapitalQ96, Q96);
    }

    function calcDepositParams(bytes memory depositOptions)
        external
        returns (
            uint256 shareOfCapitalQ96,
            uint256 debtToken1,
            uint256[] memory tokenAmounts
        )
    {
        require(depositOptions.length == 32, ExceptionsLibrary.INVALID_VALUE);
        shareOfCapitalQ96 = abi.decode(depositOptions, (uint256));

        uint256 balanceToken0 = IERC20(aaveVault.aTokens(0)).balanceOf(address(aaveVault));
        debtToken1 = aaveVault.getDebt(1);

        tokenAmounts = new uint256[](2);
        tokenAmounts[0] = FullMath.mulDiv(balanceToken0, shareOfCapitalQ96, Q96);
    }

    function calcERC20Params() external returns (uint256 token0OnERC20, uint256 wantToHaveOnERC20) {
        token0OnERC20 = IERC20(tokens[0]).balanceOf(address(erc20Vault));
        uint256 token0CapitalOnERC20 = owner.getSwapAmountOut(
            IERC20(tokens[1]).balanceOf(address(erc20Vault)),
            1,
            false
        ) + token0OnERC20;
        (, , , , , , , uint128 liquidity, , , , ) = positionManager.positions(uniV3Vault.uniV3Nft());

        uint256[] memory totalOnUni = uniV3Vault.liquidityToTokenAmounts(liquidity);
        uint256 token0CapitalOnUni = owner.getSwapAmountOut(totalOnUni[1], 1, false) + totalOnUni[0];

        wantToHaveOnERC20 = FullMath.mulDiv(totalOnUni[0], token0CapitalOnERC20, token0CapitalOnUni);
    }
}
