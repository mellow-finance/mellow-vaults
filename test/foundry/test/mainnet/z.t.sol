// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "forge-std/console2.sol";

import "../../src/ProtocolGovernance.sol";
import "../../src/MockOracle.sol";
import "../../src/ERC20RootVaultHelper.sol";
import "../../src/VaultRegistry.sol";

import "../../src/vaults/GearboxVault.sol";
import "../../src/vaults/GearboxRootVault.sol";
import "../../src/vaults/ERC20Vault.sol";

import "../../src/vaults/GearboxVaultGovernance.sol";
import "../../src/vaults/ERC20VaultGovernance.sol";
import "../../src/vaults/ERC20RootVaultGovernance.sol";

import "../../src/utils/GearboxHelper.sol";

import "../../src/external/ConvexBaseRewardPool.sol";

import "../../src/interfaces/external/gearbox/ICreditFacade.sol";

import "../../src/interfaces/IDegenNft.sol";

import "../helpers/MockDistributor.t.sol";
import "../../src/interfaces/external/gearbox/helpers/curve/ICurvePool.sol";

contract Z is Test {

    address gusd = 0x056Fd409E1d7A124BD7017459dFEa2F387b6d5Cd;

    function test() public {
        ICurvePool pool = ICurvePool(0x4f062658EaAF2C1ccf8C8e36D6824CDf41167956);
        uint256 use = 10**22;
        deal(gusd, address(this), use);
        uint256[2] memory A;
        A[0] = use;
        A[1] = 0;
        pool.add_liquidity(A, 0);

        uint256 balance = IERC20(pool.lp_token()).balanceOf(address(this));
        console2.log(balance);
        uint256 G = pool.calc_withdraw_one_coin(balance, 0);

        console2.log(use);
        console2.log(G);
    }
        

}
