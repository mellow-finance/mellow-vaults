// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/src/Test.sol";
import "forge-std/src/Vm.sol";
import "forge-std/src/console2.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../../src/utils/InstantFarm.sol";

contract InstantFarmTest is Test {
    using SafeERC20 for IERC20;

    address public constant AURA = 0xC0c293ce456fF0ED870ADd98a0828Dd4d2903DBF;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant GHO = 0x40D16FC0246aD3160Ccc09B8D0D3A2cD28aE6C2f;
    address public constant WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address public constant LUSD = 0x5f98805A4E8be255a32880FDeC7F6728C6568bA0;
    address public constant BAL = 0xba100000625a3754423978a60c9317c58a424e3D;

    InstantFarm public farm;

    address public immutable admin = address(1);
    address public immutable operator = address(2);
    address public immutable user = address(3);
    address public immutable randomUser = address(4);
    address public immutable user2 = address(5);
    address public immutable user3 = address(6);
    address public immutable user4 = address(7);
    address public immutable user5 = address(8);
    address[] public rewards;

    function increaseAmounts(uint256[] memory amounts) public {
        require(rewards.length == amounts.length, "Invalid length");
        vm.startPrank(randomUser);
        for (uint256 i = 0; i < rewards.length; i++) {
            if (amounts[i] > 0) {
                deal(rewards[i], randomUser, amounts[i]);
                IERC20(rewards[i]).safeTransfer(address(farm), amounts[i]);
            }
        }
        vm.stopPrank();
    }

    function getRewardBalances(address user_) public view returns (uint256[] memory balances) {
        balances = new uint256[](rewards.length);
        for (uint256 i = 0; i < balances.length; i++) {
            balances[i] = IERC20(rewards[i]).balanceOf(user_);
        }
    }

    function test() external {
        {
            vm.startPrank(admin);
            rewards.push(AURA);
            rewards.push(WETH);
            rewards.push(GHO);
            farm = new InstantFarm(LUSD, admin, rewards);
            vm.stopPrank();
        }

        {
            vm.startPrank(user);

            deal(LUSD, user, 100 ether);
            IERC20(LUSD).safeApprove(address(farm), 1 ether);
            farm.deposit(1 ether, user);
            require(
                IERC20(LUSD).balanceOf(user) == 99 ether &&
                    farm.balanceOf(user) == 1 ether &&
                    farm.totalSupply() == 1 ether &&
                    farm.balanceDelta(user, 0) == 1 ether,
                "Invalid balances"
            );

            farm.withdraw(1 ether, user);
            require(
                IERC20(LUSD).balanceOf(user) == 100 ether &&
                    farm.balanceOf(user) == 0 ether &&
                    farm.totalSupply() == 0 ether &&
                    farm.balanceDelta(user, 0) == 0 ether,
                "Invalid balances"
            );

            vm.stopPrank();
        }

        {
            uint256[] memory amounts = new uint256[](3);
            amounts[0] = 10 ether;
            increaseAmounts(amounts);
        }

        {
            vm.startPrank(admin);
            try farm.updateRewardAmounts() {
                revert("Must fail");
            } catch {}
            vm.stopPrank();
        }

        {
            vm.startPrank(user);

            deal(LUSD, user, 100 ether);
            IERC20(LUSD).safeApprove(address(farm), 100 ether);
            farm.deposit(100 ether, user);
            require(
                IERC20(LUSD).balanceOf(user) == 0 ether &&
                    farm.balanceOf(user) == 100 ether &&
                    farm.totalSupply() == 100 ether &&
                    farm.balanceDelta(user, 0) == 100 ether,
                "Invalid balances"
            );

            vm.stopPrank();
        }

        {
            vm.startPrank(admin);
            uint256[] memory amounts = farm.updateRewardAmounts();
            require(
                amounts[0] == 10 ether && amounts[1] == 0 && amounts[2] == 0 && amounts.length == 3,
                "Invalid reward values"
            );
            require(
                farm.totalCollectedAmounts(0) == 10 ether &&
                    farm.totalCollectedAmounts(1) == 0 &&
                    farm.totalCollectedAmounts(2) == 0,
                "Invalid totalCollectedAmounts"
            );
            InstantFarm.Epoch memory epoch = farm.epoch(0);

            require(
                epoch.totalSupply == 100 ether &&
                    epoch.amounts.length == 3 &&
                    epoch.amounts[0] == 10 ether &&
                    epoch.amounts[1] == 0 &&
                    epoch.amounts[2] == 0,
                "Invalid epoch data"
            );

            vm.stopPrank();
        }

        {
            vm.startPrank(user);

            uint256[] memory balancesBefore = getRewardBalances(user);
            uint256[] memory rewardAmounts = farm.claim(user);
            uint256[] memory balancesAfter = getRewardBalances(user);

            require(rewardAmounts.length == rewards.length);
            uint256[] memory expectedAmounts = new uint256[](3);
            expectedAmounts[0] = 10 ether;
            for (uint256 i = 0; i < rewardAmounts.length; i++) {
                require(rewardAmounts[i] == balancesAfter[i] - balancesBefore[i], "Invalid balances");
                require(rewardAmounts[i] == expectedAmounts[i], "Invalid reward amounts");
            }
            vm.stopPrank();
        }
    }

    function test2() external {
        {
            vm.startPrank(admin);
            rewards.push(AURA);
            rewards.push(WETH);
            farm = new InstantFarm(LUSD, admin, rewards);
            vm.stopPrank();
        }

        {
            uint256[] memory amounts = new uint256[](2);
            amounts[1] = 10 ether;
            amounts[0] = 9 ether;
            increaseAmounts(amounts);
        }

        {
            vm.startPrank(admin);
            try farm.updateRewardAmounts() {
                revert("Must fail");
            } catch {}
            vm.stopPrank();
        }

        {
            vm.startPrank(user);
            deal(LUSD, user, 100 ether);
            IERC20(LUSD).safeApprove(address(farm), 100 ether);
            farm.deposit(100 ether, user);
            vm.stopPrank();
        }

        {
            vm.startPrank(admin);
            uint256[] memory amounts = farm.updateRewardAmounts();
            require(amounts[0] == 9 ether && amounts[1] == 10 ether && amounts.length == 2, "Invalid reward values");
            require(
                farm.totalCollectedAmounts(0) == 9 ether && farm.totalCollectedAmounts(1) == 10 ether,
                "Invalid totalCollectedAmounts"
            );
            InstantFarm.Epoch memory epoch = farm.epoch(0);

            require(
                epoch.totalSupply == 100 ether &&
                    epoch.amounts.length == 2 &&
                    epoch.amounts[0] == 9 ether &&
                    epoch.amounts[1] == 10 ether,
                "Invalid epoch data"
            );

            vm.stopPrank();
        }

        {
            vm.startPrank(user);

            uint256[] memory balancesBefore = getRewardBalances(user);
            uint256[] memory rewardAmounts = farm.claim(user);
            uint256[] memory balancesAfter = getRewardBalances(user);

            require(rewardAmounts.length == rewards.length);
            uint256[] memory expectedAmounts = new uint256[](2);
            expectedAmounts[0] = 9 ether;
            expectedAmounts[1] = 10 ether;
            for (uint256 i = 0; i < rewardAmounts.length; i++) {
                require(rewardAmounts[i] == balancesAfter[i] - balancesBefore[i], "Invalid balances");
                require(rewardAmounts[i] == expectedAmounts[i], "Invalid reward amounts");
            }
            vm.stopPrank();
        }
    }

    function test3() external {
        {
            vm.startPrank(admin);
            rewards.push(AURA);
            rewards.push(WETH);
            farm = new InstantFarm(LUSD, admin, rewards);
            vm.stopPrank();
        }

        {
            uint256[] memory amounts = new uint256[](2);
            amounts[1] = 10 ether;
            amounts[0] = 9 ether;
            increaseAmounts(amounts);
        }

        {
            vm.startPrank(admin);
            try farm.updateRewardAmounts() {
                revert("Must fail");
            } catch {}
            vm.stopPrank();
        }

        {
            vm.startPrank(user);
            deal(LUSD, user, 100 ether);
            IERC20(LUSD).safeApprove(address(farm), 100 ether);
            farm.deposit(100 ether, user);
            vm.stopPrank();
        }

        {
            vm.startPrank(user2);
            deal(LUSD, user2, 99 ether);
            IERC20(LUSD).safeApprove(address(farm), 99 ether);
            farm.deposit(99 ether, user2);
            vm.stopPrank();
        }

        {
            vm.startPrank(admin);
            uint256[] memory amounts = farm.updateRewardAmounts();
            require(amounts[0] == 9 ether && amounts[1] == 10 ether && amounts.length == 2, "Invalid reward values");
            require(
                farm.totalCollectedAmounts(0) == 9 ether && farm.totalCollectedAmounts(1) == 10 ether,
                "Invalid totalCollectedAmounts"
            );
            InstantFarm.Epoch memory epoch = farm.epoch(0);

            require(
                epoch.totalSupply == 199 ether &&
                    epoch.amounts.length == 2 &&
                    epoch.amounts[0] == 9 ether &&
                    epoch.amounts[1] == 10 ether,
                "Invalid epoch data"
            );

            vm.stopPrank();
        }

        {
            vm.startPrank(user);

            uint256[] memory balancesBefore = getRewardBalances(user);
            uint256[] memory rewardAmounts = farm.claim(user);
            uint256[] memory balancesAfter = getRewardBalances(user);

            require(rewardAmounts.length == rewards.length);
            uint256[] memory expectedAmounts = new uint256[](2);
            expectedAmounts[0] = (uint256(9 ether) * 100) / 199;
            expectedAmounts[1] = (uint256(10 ether) * 100) / 199;
            for (uint256 i = 0; i < rewardAmounts.length; i++) {
                require(rewardAmounts[i] == balancesAfter[i] - balancesBefore[i], "Invalid balances");
                require(rewardAmounts[i] == expectedAmounts[i], "Invalid reward amounts");
            }
            vm.stopPrank();
        }

        {
            vm.startPrank(user2);

            uint256[] memory balancesBefore = getRewardBalances(user2);
            uint256[] memory rewardAmounts = farm.claim(user2);
            uint256[] memory balancesAfter = getRewardBalances(user2);

            require(rewardAmounts.length == rewards.length);
            uint256[] memory expectedAmounts = new uint256[](2);
            expectedAmounts[0] = (uint256(9 ether) * 99) / 199;
            expectedAmounts[1] = (uint256(10 ether) * 99) / 199;
            for (uint256 i = 0; i < rewardAmounts.length; i++) {
                require(rewardAmounts[i] == balancesAfter[i] - balancesBefore[i], "Invalid balances");
                require(rewardAmounts[i] == expectedAmounts[i], "Invalid reward amounts");
            }
            vm.stopPrank();
        }
    }

    function test4() external {
        {
            vm.startPrank(admin);
            rewards.push(AURA);
            rewards.push(WETH);
            farm = new InstantFarm(LUSD, admin, rewards);
            vm.stopPrank();
        }

        {
            uint256[] memory amounts = new uint256[](2);
            amounts[1] = 10 ether;
            amounts[0] = 9 ether;
            increaseAmounts(amounts);
        }

        {
            vm.startPrank(admin);
            try farm.updateRewardAmounts() {
                revert("Must fail");
            } catch {}
            vm.stopPrank();
        }

        {
            vm.startPrank(user);
            deal(LUSD, user, 100 ether);
            IERC20(LUSD).safeApprove(address(farm), 100 ether);
            farm.deposit(100 ether, user);
            vm.stopPrank();
        }

        {
            vm.startPrank(user2);
            deal(LUSD, user2, 99 ether);
            IERC20(LUSD).safeApprove(address(farm), 99 ether);
            farm.deposit(99 ether, user2);
            vm.stopPrank();
        }

        {
            vm.startPrank(admin);
            uint256[] memory amounts = farm.updateRewardAmounts();
            require(amounts[0] == 9 ether && amounts[1] == 10 ether && amounts.length == 2, "Invalid reward values");
            require(
                farm.totalCollectedAmounts(0) == 9 ether && farm.totalCollectedAmounts(1) == 10 ether,
                "Invalid totalCollectedAmounts"
            );
            InstantFarm.Epoch memory epoch = farm.epoch(0);

            require(
                epoch.totalSupply == 199 ether &&
                    epoch.amounts.length == 2 &&
                    epoch.amounts[0] == 9 ether &&
                    epoch.amounts[1] == 10 ether,
                "Invalid epoch data"
            );

            vm.stopPrank();
        }

        {
            vm.startPrank(user2);
            farm.withdraw(farm.balanceOf(user2), user2);
            vm.stopPrank();
        }

        {
            vm.startPrank(user);

            uint256[] memory balancesBefore = getRewardBalances(user);
            uint256[] memory rewardAmounts = farm.claim(user);
            uint256[] memory balancesAfter = getRewardBalances(user);

            require(rewardAmounts.length == rewards.length);
            uint256[] memory expectedAmounts = new uint256[](2);
            expectedAmounts[0] = (uint256(9 ether) * 100) / 199;
            expectedAmounts[1] = (uint256(10 ether) * 100) / 199;
            for (uint256 i = 0; i < rewardAmounts.length; i++) {
                require(rewardAmounts[i] == balancesAfter[i] - balancesBefore[i], "Invalid balances");
                require(rewardAmounts[i] == expectedAmounts[i], "Invalid reward amounts");
            }
            vm.stopPrank();
        }

        {
            vm.startPrank(user2);

            uint256[] memory balancesBefore = getRewardBalances(user2);
            uint256[] memory rewardAmounts = farm.claim(user2);
            uint256[] memory balancesAfter = getRewardBalances(user2);

            require(rewardAmounts.length == rewards.length);
            uint256[] memory expectedAmounts = new uint256[](2);
            expectedAmounts[0] = (uint256(9 ether) * 99) / 199;
            expectedAmounts[1] = (uint256(10 ether) * 99) / 199;
            for (uint256 i = 0; i < rewardAmounts.length; i++) {
                require(rewardAmounts[i] == balancesAfter[i] - balancesBefore[i], "Invalid balances");
                require(rewardAmounts[i] == expectedAmounts[i], "Invalid reward amounts");
            }
            vm.stopPrank();
        }
    }

    function test5() external {
        {
            vm.startPrank(admin);
            rewards.push(AURA);
            rewards.push(WETH);
            farm = new InstantFarm(LUSD, admin, rewards);
            vm.stopPrank();
        }

        {
            uint256[] memory amounts = new uint256[](2);
            amounts[0] = 9 ether;
            amounts[1] = 10 ether;
            increaseAmounts(amounts);
        }

        {
            vm.startPrank(user);
            deal(LUSD, user, 100 ether);
            IERC20(LUSD).safeApprove(address(farm), 100 ether);
            farm.deposit(100 ether, user);
            vm.stopPrank();
        }

        {
            vm.startPrank(user2);
            deal(LUSD, user2, 100 ether);
            IERC20(LUSD).safeApprove(address(farm), 100 ether);
            farm.deposit(100 ether, user2);
            vm.stopPrank();
        }

        {
            vm.startPrank(admin);
            uint256[] memory amounts = farm.updateRewardAmounts();
            require(amounts[0] == 9 ether && amounts[1] == 10 ether && amounts.length == 2, "Invalid reward values");
            require(
                farm.totalCollectedAmounts(0) == 9 ether && farm.totalCollectedAmounts(1) == 10 ether,
                "Invalid totalCollectedAmounts"
            );
            InstantFarm.Epoch memory epoch = farm.epoch(0);

            require(
                epoch.totalSupply == 200 ether &&
                    epoch.amounts.length == 2 &&
                    epoch.amounts[0] == 9 ether &&
                    epoch.amounts[1] == 10 ether,
                "Invalid epoch data"
            );

            vm.stopPrank();
        }

        {
            uint256[] memory amounts = new uint256[](2);
            amounts[0] = 9 ether;
            amounts[1] = 10 ether;
            increaseAmounts(amounts);
        }

        {
            vm.startPrank(admin);
            uint256[] memory amounts = farm.updateRewardAmounts();
            require(amounts[0] == 9 ether && amounts[1] == 10 ether && amounts.length == 2, "Invalid reward values");
            require(
                farm.totalCollectedAmounts(0) == 18 ether && farm.totalCollectedAmounts(1) == 20 ether,
                "Invalid totalCollectedAmounts"
            );
            InstantFarm.Epoch memory epoch = farm.epoch(1);

            require(
                epoch.totalSupply == 200 ether &&
                    epoch.amounts.length == 2 &&
                    epoch.amounts[0] == 9 ether &&
                    epoch.amounts[1] == 10 ether,
                "Invalid epoch data"
            );

            vm.stopPrank();
        }

        {
            uint256[] memory amounts = new uint256[](2);
            amounts[0] = 9 ether;
            amounts[1] = 10 ether;
            increaseAmounts(amounts);
        }

        {
            vm.startPrank(admin);
            uint256[] memory amounts = farm.updateRewardAmounts();
            require(amounts[0] == 9 ether && amounts[1] == 10 ether && amounts.length == 2, "Invalid reward values");
            require(
                farm.totalCollectedAmounts(0) == 27 ether && farm.totalCollectedAmounts(1) == 30 ether,
                "Invalid totalCollectedAmounts"
            );
            InstantFarm.Epoch memory epoch = farm.epoch(2);

            require(
                epoch.totalSupply == 200 ether &&
                    epoch.amounts.length == 2 &&
                    epoch.amounts[0] == 9 ether &&
                    epoch.amounts[1] == 10 ether,
                "Invalid epoch data"
            );

            vm.stopPrank();
        }

        uint256[] memory totalUser1Claimed = new uint256[](2);
        uint256[] memory totalUser2Claimed = new uint256[](2);

        {
            vm.startPrank(user);

            uint256[] memory balancesBefore = getRewardBalances(user);
            uint256[] memory rewardAmounts = farm.claim(user);
            uint256[] memory balancesAfter = getRewardBalances(user);

            require(rewardAmounts.length == rewards.length);
            uint256[] memory expectedAmounts = new uint256[](2);
            expectedAmounts[0] = (uint256(27 ether) * 100) / 200;
            expectedAmounts[1] = (uint256(30 ether) * 100) / 200;
            for (uint256 i = 0; i < rewardAmounts.length; i++) {
                require(rewardAmounts[i] == balancesAfter[i] - balancesBefore[i], "Invalid balances");
                require(rewardAmounts[i] == expectedAmounts[i], "Invalid reward amounts");
                totalUser1Claimed[i] += rewardAmounts[i];
            }
            vm.stopPrank();
        }

        {
            uint256[] memory amounts = new uint256[](2);
            amounts[0] = 9 ether;
            amounts[1] = 10 ether;
            increaseAmounts(amounts);
        }

        {
            vm.startPrank(admin);
            uint256[] memory amounts = farm.updateRewardAmounts();
            require(amounts[0] == 9 ether && amounts[1] == 10 ether && amounts.length == 2, "Invalid reward values");
            require(
                farm.totalCollectedAmounts(0) == 36 ether && farm.totalCollectedAmounts(1) == 40 ether,
                "Invalid totalCollectedAmounts"
            );
            InstantFarm.Epoch memory epoch = farm.epoch(3);

            require(
                epoch.totalSupply == 200 ether &&
                    epoch.amounts.length == 2 &&
                    epoch.amounts[0] == 9 ether &&
                    epoch.amounts[1] == 10 ether,
                "Invalid epoch data"
            );

            vm.stopPrank();
        }

        {
            uint256[] memory amounts = new uint256[](2);
            amounts[0] = 9 ether;
            amounts[1] = 10 ether;
            increaseAmounts(amounts);
        }

        {
            vm.startPrank(admin);
            uint256[] memory amounts = farm.updateRewardAmounts();
            require(amounts[0] == 9 ether && amounts[1] == 10 ether && amounts.length == 2, "Invalid reward values");
            require(
                farm.totalCollectedAmounts(0) == 45 ether && farm.totalCollectedAmounts(1) == 50 ether,
                "Invalid totalCollectedAmounts"
            );
            InstantFarm.Epoch memory epoch = farm.epoch(4);

            require(
                epoch.totalSupply == 200 ether &&
                    epoch.amounts.length == 2 &&
                    epoch.amounts[0] == 9 ether &&
                    epoch.amounts[1] == 10 ether,
                "Invalid epoch data"
            );

            vm.stopPrank();
        }

        {
            vm.startPrank(user);

            uint256[] memory balancesBefore = getRewardBalances(user);
            uint256[] memory rewardAmounts = farm.claim(user);
            uint256[] memory balancesAfter = getRewardBalances(user);

            require(rewardAmounts.length == rewards.length);
            uint256[] memory expectedAmounts = new uint256[](2);
            expectedAmounts[0] = (uint256(18 ether) * 100) / 200;
            expectedAmounts[1] = (uint256(20 ether) * 100) / 200;
            for (uint256 i = 0; i < rewardAmounts.length; i++) {
                require(rewardAmounts[i] == balancesAfter[i] - balancesBefore[i], "Invalid balances");
                require(rewardAmounts[i] == expectedAmounts[i], "Invalid reward amounts 1");
                totalUser1Claimed[i] += rewardAmounts[i];
            }
            vm.stopPrank();
        }

        {
            vm.startPrank(user2);

            uint256[] memory balancesBefore = getRewardBalances(user2);
            uint256[] memory rewardAmounts = farm.claim(user2);
            uint256[] memory balancesAfter = getRewardBalances(user2);

            require(rewardAmounts.length == rewards.length);
            uint256[] memory expectedAmounts = new uint256[](2);
            expectedAmounts[0] = (uint256(45 ether) * 100) / 200;
            expectedAmounts[1] = (uint256(50 ether) * 100) / 200;
            for (uint256 i = 0; i < rewardAmounts.length; i++) {
                require(rewardAmounts[i] == balancesAfter[i] - balancesBefore[i], "Invalid balances");
                require(rewardAmounts[i] == expectedAmounts[i], "Invalid reward amounts 2");
                totalUser2Claimed[i] += rewardAmounts[i];
            }
            vm.stopPrank();
        }

        {
            for (uint256 i = 0; i < rewards.length; i++) {
                require(totalUser1Claimed[i] == totalUser2Claimed[i], "Invalid ratio");
            }
        }
    }

    function test6() external {
        {
            vm.startPrank(admin);
            rewards.push(AURA);
            rewards.push(WETH);
            farm = new InstantFarm(LUSD, admin, rewards);
            vm.stopPrank();
        }

        {
            uint256[] memory amounts = new uint256[](2);
            amounts[0] = 9 ether;
            amounts[1] = 10 ether;
            increaseAmounts(amounts);
        }

        {
            vm.startPrank(user);
            deal(LUSD, user, 100 ether);
            IERC20(LUSD).safeApprove(address(farm), 100 ether);
            farm.deposit(100 ether, user);
            vm.stopPrank();
        }

        {
            vm.startPrank(user2);
            deal(LUSD, user2, 100 ether);
            IERC20(LUSD).safeApprove(address(farm), 100 ether);
            farm.deposit(100 ether, user2);
            vm.stopPrank();
        }

        {
            vm.startPrank(admin);
            uint256[] memory amounts = farm.updateRewardAmounts();
            require(amounts[0] == 9 ether && amounts[1] == 10 ether && amounts.length == 2, "Invalid reward values");
            require(
                farm.totalCollectedAmounts(0) == 9 ether && farm.totalCollectedAmounts(1) == 10 ether,
                "Invalid totalCollectedAmounts"
            );
            InstantFarm.Epoch memory epoch = farm.epoch(0);

            require(
                epoch.totalSupply == 200 ether &&
                    epoch.amounts.length == 2 &&
                    epoch.amounts[0] == 9 ether &&
                    epoch.amounts[1] == 10 ether,
                "Invalid epoch data"
            );

            vm.stopPrank();
        }

        {
            uint256[] memory amounts = new uint256[](2);
            amounts[0] = 9 ether;
            amounts[1] = 10 ether;
            increaseAmounts(amounts);
        }

        {
            vm.startPrank(admin);
            uint256[] memory amounts = farm.updateRewardAmounts();
            require(amounts[0] == 9 ether && amounts[1] == 10 ether && amounts.length == 2, "Invalid reward values");
            require(
                farm.totalCollectedAmounts(0) == 18 ether && farm.totalCollectedAmounts(1) == 20 ether,
                "Invalid totalCollectedAmounts"
            );
            InstantFarm.Epoch memory epoch = farm.epoch(1);

            require(
                epoch.totalSupply == 200 ether &&
                    epoch.amounts.length == 2 &&
                    epoch.amounts[0] == 9 ether &&
                    epoch.amounts[1] == 10 ether,
                "Invalid epoch data"
            );

            vm.stopPrank();
        }

        {
            uint256[] memory amounts = new uint256[](2);
            amounts[0] = 9 ether;
            amounts[1] = 10 ether;
            increaseAmounts(amounts);
        }

        {
            vm.startPrank(user);
            uint256 balance = farm.balanceOf(user);
            farm.withdraw(balance, user);
            IERC20(LUSD).safeApprove(address(farm), balance);
            farm.deposit(balance, user);
            vm.stopPrank();
        }

        {
            vm.startPrank(admin);
            uint256[] memory amounts = farm.updateRewardAmounts();
            require(amounts[0] == 9 ether && amounts[1] == 10 ether && amounts.length == 2, "Invalid reward values");
            require(
                farm.totalCollectedAmounts(0) == 27 ether && farm.totalCollectedAmounts(1) == 30 ether,
                "Invalid totalCollectedAmounts"
            );
            InstantFarm.Epoch memory epoch = farm.epoch(2);

            require(
                epoch.totalSupply == 200 ether &&
                    epoch.amounts.length == 2 &&
                    epoch.amounts[0] == 9 ether &&
                    epoch.amounts[1] == 10 ether,
                "Invalid epoch data"
            );

            vm.stopPrank();
        }

        uint256[] memory totalUser1Claimed = new uint256[](2);
        uint256[] memory totalUser2Claimed = new uint256[](2);

        {
            vm.startPrank(user);

            uint256[] memory balancesBefore = getRewardBalances(user);
            uint256[] memory rewardAmounts = farm.claim(user);
            uint256[] memory balancesAfter = getRewardBalances(user);

            require(rewardAmounts.length == rewards.length);
            uint256[] memory expectedAmounts = new uint256[](2);
            expectedAmounts[0] = (uint256(27 ether) * 100) / 200;
            expectedAmounts[1] = (uint256(30 ether) * 100) / 200;
            for (uint256 i = 0; i < rewardAmounts.length; i++) {
                require(rewardAmounts[i] == balancesAfter[i] - balancesBefore[i], "Invalid balances");
                require(rewardAmounts[i] == expectedAmounts[i], "Invalid reward amounts");
                totalUser1Claimed[i] += rewardAmounts[i];
            }
            vm.stopPrank();
        }

        {
            uint256[] memory amounts = new uint256[](2);
            amounts[0] = 9 ether;
            amounts[1] = 10 ether;
            increaseAmounts(amounts);
        }

        {
            vm.startPrank(admin);
            uint256[] memory amounts = farm.updateRewardAmounts();
            require(amounts[0] == 9 ether && amounts[1] == 10 ether && amounts.length == 2, "Invalid reward values");
            require(
                farm.totalCollectedAmounts(0) == 36 ether && farm.totalCollectedAmounts(1) == 40 ether,
                "Invalid totalCollectedAmounts"
            );
            InstantFarm.Epoch memory epoch = farm.epoch(3);

            require(
                epoch.totalSupply == 200 ether &&
                    epoch.amounts.length == 2 &&
                    epoch.amounts[0] == 9 ether &&
                    epoch.amounts[1] == 10 ether,
                "Invalid epoch data"
            );

            vm.stopPrank();
        }

        {
            uint256[] memory amounts = new uint256[](2);
            amounts[0] = 9 ether;
            amounts[1] = 10 ether;
            increaseAmounts(amounts);
        }

        {
            vm.startPrank(admin);
            uint256[] memory amounts = farm.updateRewardAmounts();
            require(amounts[0] == 9 ether && amounts[1] == 10 ether && amounts.length == 2, "Invalid reward values");
            require(
                farm.totalCollectedAmounts(0) == 45 ether && farm.totalCollectedAmounts(1) == 50 ether,
                "Invalid totalCollectedAmounts"
            );
            InstantFarm.Epoch memory epoch = farm.epoch(4);

            require(
                epoch.totalSupply == 200 ether &&
                    epoch.amounts.length == 2 &&
                    epoch.amounts[0] == 9 ether &&
                    epoch.amounts[1] == 10 ether,
                "Invalid epoch data"
            );

            vm.stopPrank();
        }

        {
            vm.startPrank(user);

            uint256[] memory balancesBefore = getRewardBalances(user);
            uint256[] memory rewardAmounts = farm.claim(user);
            uint256[] memory balancesAfter = getRewardBalances(user);

            require(rewardAmounts.length == rewards.length);
            uint256[] memory expectedAmounts = new uint256[](2);
            expectedAmounts[0] = (uint256(18 ether) * 100) / 200;
            expectedAmounts[1] = (uint256(20 ether) * 100) / 200;
            for (uint256 i = 0; i < rewardAmounts.length; i++) {
                require(rewardAmounts[i] == balancesAfter[i] - balancesBefore[i], "Invalid balances");
                require(rewardAmounts[i] == expectedAmounts[i], "Invalid reward amounts 1");
                totalUser1Claimed[i] += rewardAmounts[i];
            }
            vm.stopPrank();
        }

        {
            vm.startPrank(user2);

            uint256[] memory balancesBefore = getRewardBalances(user2);
            uint256[] memory rewardAmounts = farm.claim(user2);
            uint256[] memory balancesAfter = getRewardBalances(user2);

            require(rewardAmounts.length == rewards.length);
            uint256[] memory expectedAmounts = new uint256[](2);
            expectedAmounts[0] = (uint256(45 ether) * 100) / 200;
            expectedAmounts[1] = (uint256(50 ether) * 100) / 200;
            for (uint256 i = 0; i < rewardAmounts.length; i++) {
                require(rewardAmounts[i] == balancesAfter[i] - balancesBefore[i], "Invalid balances");
                require(rewardAmounts[i] == expectedAmounts[i], "Invalid reward amounts 2");
                totalUser2Claimed[i] += rewardAmounts[i];
            }
            vm.stopPrank();
        }

        {
            for (uint256 i = 0; i < rewards.length; i++) {
                require(totalUser1Claimed[i] == totalUser2Claimed[i], "Invalid ratio");
            }
        }
    }
}
