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

    address[3] public vaultsWithWrapper = [
        0x74620326155f8Ef1FE4044b18Daf93654521CF9A,
        0xca2cd7B819fBdE9D1a00F2486De3220C28b5b435,
        0x0916BCDcDB6e23e758F41D612e7a8a295fcd6DBF
    ];

    function _checkWrapped(
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
                new bytes(0),
                true
            );
        } else {
            deal(user, amount);
            lpAmount = wrapper.wrappedDeposit{value: amount}(
                0x231002439E1BD5b610C3d98321EA760002b9Ff64,
                vault,
                token,
                0,
                0,
                new bytes(0),
                true
            );
        }

        string memory srcToken = IERC20Metadata(token).symbol();
        if (isNative) srcToken = "ETH";
        console2.log(IERC20Metadata(vault).symbol(), lpAmount, srcToken, amount);

        vm.stopPrank();
    }

    function testWrapperDeposits() external {
        OneSidedDepositWrapper wrapper = new OneSidedDepositWrapper(
            Constants.uniswapV3Router,
            Constants.uniswapV3Factory,
            Constants.weth
        );

        uint256 seed = 0;

        for (uint256 i = 0; i < vaultsWithWrapper.length; i++) {
            address vault = vaultsWithWrapper[i];
            _checkWrapped(true, seed++, Constants.weth, 1e19, vault, wrapper);
            address[] memory vaultTokens = IERC20RootVault(vault).vaultTokens();
            for (uint256 j = 0; j < vaultTokens.length; j++) {
                _checkWrapped(
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

    address[3] public vaultsDirect = [
        0x78ba57594656400d74a0c5ea80f84750cb47f449,
        0x1FCD3926b6DFa2A90Fe49A383C732b31f1ee54eB,
        0xA33a068645E228Db11c42e9d187EDC72361B7BC0
    ];

    function _checkDirect(
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
            lpAmount = wrapper.directDeposit(vault, token, amount, 0, new bytes(0), true);
        } else {
            deal(user, amount);
            lpAmount = wrapper.directDeposit{value: amount}(vault, token, 0, 0, new bytes(0), true);
        }

        string memory srcToken = IERC20Metadata(token).symbol();
        if (isNative) srcToken = "ETH";
        console2.log(IERC20Metadata(vault).symbol(), lpAmount, srcToken, amount);

        vm.stopPrank();
    }

    function testDirectDeposits() external {
        OneSidedDepositWrapper wrapper = new OneSidedDepositWrapper(
            Constants.uniswapV3Router,
            Constants.uniswapV3Factory,
            Constants.weth
        );

        uint256 seed = 523452345;

        for (uint256 i = 0; i < vaultsDirect.length; i++) {
            address vault = vaultsDirect[i];
            _checkDirect(true, seed++, Constants.weth, 1e19, vault, wrapper);
            address[] memory vaultTokens = IERC20RootVault(vault).vaultTokens();
            for (uint256 j = 0; j < vaultTokens.length; j++) {
                _checkDirect(
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
