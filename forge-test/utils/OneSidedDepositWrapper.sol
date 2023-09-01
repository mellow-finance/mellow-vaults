// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "forge-std/src/Test.sol";
import "forge-std/src/Vm.sol";

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../../src/utils/OneSidedDepositWrapper.sol";
import "./Constants.sol";

contract OneSidedDepositWrapperTest is Test {
    using SafeERC20 for IERC20;

    address[3] public vaults = [
        0x74620326155f8Ef1FE4044b18Daf93654521CF9A,
        0xca2cd7B819fBdE9D1a00F2486De3220C28b5b435,
        0x0916BCDcDB6e23e758F41D612e7a8a295fcd6DBF
    ];


    function _check(
        bool isNative,
        uint256 seed,
        address token,
        uint256 amount,
        address vault,
        OneSidedDepositWrapper wrapper
    ) private {
        address user = address(uint160(seed + 412341234123412));
        vm.startPrank(user);
        uint256 lpAmount;
        if (!isNative) {
            deal(token, user, amount);
            IERC20(token).safeApprove(address(wrapper), amount);
            lpAmount = wrapper.wrappedDeposit(
                0x231002439E1BD5b610C3d98321EA760002b9Ff64,
                vault,
                token,
                amount,
                0,
                new bytes(0)
            );
        } else {
            deal(user, amount);
            lpAmount = wrapper.wrappedDeposit{value: amount}(
                0x231002439E1BD5b610C3d98321EA760002b9Ff64,
                vault,
                token,
                0,
                0,
                new bytes(0)
            );
        }

        string memory srcToken = IERC20Metadata(token).symbol();
        if (isNative) srcToken = "ETH";
        console2.log(IERC20Metadata(vault).symbol(), lpAmount, srcToken, amount);

        vm.stopPrank();
    }

    function test() external {
        OneSidedDepositWrapper wrapper = new OneSidedDepositWrapper(
            Constants.uniswapV3Router,
            Constants.uniswapV3Factory,
            Constants.weth
        );

        uint256 seed = 0;

        for (uint256 i = 0; i < vaults.length; i++) {
            address vault = vaults[i];
            _check(true, seed++, Constants.weth, 1e19, vault, wrapper);
            address[] memory vaultTokens = IERC20RootVault(vault).vaultTokens();
            for (uint256 j = 0; j < vaultTokens.length; j++) {
                _check(
                    false,
                    seed++,
                    vaultTokens[j],
                    10 * (10**IERC20Metadata(vaultTokens[j]).decimals()),
                    vault,
                    wrapper
                );
            }
        }
    }
}
