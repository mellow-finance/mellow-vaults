// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/IProtocolGovernance.sol";
import "../interfaces/vaults/IERC20RootVault.sol";
import "../interfaces/oracles/IChainlinkOracle.sol";
import "../libraries/external/FullMath.sol";
import "../libraries/ExceptionsLibrary.sol";
import "../libraries/PermissionIdsLibrary.sol";

import "./DefaultAccessControl.sol";

contract InchDepositWrapper is DefaultAccessControl {
    using SafeERC20 for IERC20;
    using SafeERC20 for IERC20RootVault;

    IChainlinkOracle public immutable mellowOracle;
    IProtocolGovernance public immutable governance;
    address public immutable router;

    uint256 public slippageD9;

    uint256 public constant Q96 = 2**96;
    uint256 public constant D18 = 10**18;
    uint256 public constant D9 = 10**9;

    constructor(
        IChainlinkOracle mellowOracle_,
        IProtocolGovernance governance_,
        address router_,
        address admin,
        uint256 initialSlippageD9
    ) DefaultAccessControl(admin) {
        mellowOracle = mellowOracle_;
        governance = governance_;
        router = router_;
        slippageD9 = initialSlippageD9;
    }

    function _convert(
        address token0,
        address token1,
        uint256 amount
    ) internal view returns (uint256) {
        (uint256[] memory pricesX96, ) = mellowOracle.priceX96(token0, token1, 0x20);
        require(pricesX96[0] != 0, ExceptionsLibrary.INVALID_STATE);
        return FullMath.mulDiv(amount, pricesX96[0], Q96);
    }

    function _swap(bytes memory swapOption) internal {
        (bool res, bytes memory returndata) = router.call{value: 0}(swapOption);
        if (!res) {
            assembly {
                let returndata_size := mload(returndata)
                // Bubble up revert reason
                revert(add(32, returndata), returndata_size)
            }
        }
    }

    function setSlippage(uint256 newSlippageD9) external {
        _requireAdmin();
        require(newSlippageD9 <= D9, ExceptionsLibrary.INVARIANT);
        slippageD9 = newSlippageD9;
    }

    function deposit(
        IERC20RootVault rootVault,
        address token,
        uint256 amount,
        uint256 minLpTokens,
        bytes calldata vaultOptions,
        bytes[] memory swapOptions
    ) external {
        require(governance.hasPermission(token, PermissionIdsLibrary.ERC20_TRANSFER), ExceptionsLibrary.FORBIDDEN);
        require(mellowOracle.hasOracle(token), ExceptionsLibrary.FORBIDDEN);

        address[] memory vaultTokens = rootVault.vaultTokens();

        for (uint256 i = 0; i < vaultTokens.length; ++i) {
            require(mellowOracle.hasOracle(vaultTokens[i]), ExceptionsLibrary.FORBIDDEN);
        }

        (uint256[] memory minTvl, ) = rootVault.tvl();

        uint256 totalToken0Tvl = minTvl[0];
        for (uint256 i = 1; i < vaultTokens.length; ++i) {
            totalToken0Tvl += _convert(vaultTokens[i], vaultTokens[0], minTvl[i]);
        }

        for (uint256 i = 0; i < vaultTokens.length; ++i) {
            if (vaultTokens[i] != token) {
                uint256 amountI = FullMath.mulDiv(
                    _convert(vaultTokens[i], vaultTokens[0], minTvl[i]),
                    amount,
                    totalToken0Tvl
                );
                uint256 expectedAmountOut = _convert(vaultTokens[0], vaultTokens[i], amountI);
                _swap(swapOptions[i]);
                require(
                    IERC20(vaultTokens[i]).balanceOf(address(this)) >=
                        FullMath.mulDiv(expectedAmountOut, D9 - slippageD9, D9),
                    ExceptionsLibrary.INVARIANT
                );
            }
        }

        uint256[] memory balances = new uint256[](vaultTokens.length);
        for (uint256 i = 0; i < vaultTokens.length; ++i) {
            uint256 balance = IERC20(vaultTokens[i]).balanceOf(address(this));
            balances[i] = balance;
            IERC20(vaultTokens[i]).safeIncreaseAllowance(address(rootVault), balance);
        }

        rootVault.deposit(balances, minLpTokens, vaultOptions);

        for (uint256 i = 0; i < vaultTokens.length; ++i) {
            IERC20(vaultTokens[i]).safeApprove(address(rootVault), 0);
        }

        rootVault.safeTransfer(msg.sender, rootVault.balanceOf(address(this)));
        for (uint256 i = 0; i < vaultTokens.length; ++i) {
            IERC20(vaultTokens[i]).safeTransfer(msg.sender, IERC20(vaultTokens[i]).balanceOf(address(this)));
        }
    }

    function calcSwapShares(IERC20RootVault rootVault) external returns (uint256[] memory swapSharesD18) {
        (uint256[] memory minTvl, ) = rootVault.tvl();

        address[] memory vaultTokens = rootVault.vaultTokens();

        swapSharesD18 = new uint256[](minTvl.length);

        uint256 totalToken0Tvl = minTvl[0];
        for (uint256 i = 1; i < vaultTokens.length; ++i) {
            totalToken0Tvl += _convert(vaultTokens[i], vaultTokens[0], minTvl[i]);
        }

        for (uint256 i = 0; i < vaultTokens.length; ++i) {
            swapSharesD18[i] = FullMath.mulDiv(
                _convert(vaultTokens[i], vaultTokens[0], minTvl[i]),
                D18,
                totalToken0Tvl
            );
        }
    }
}
