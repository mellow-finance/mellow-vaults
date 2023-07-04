// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Script.sol";

import "../../src/utils/DataCollector.sol";
import "../../src/utils/UniV3Helper.sol";

contract CollectorDeployment is Script {
    address deployer = 0x7ee9247b6199877F86703644c97784495549aC5E;
    address public weth = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address public usdc = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;

    address public governance = 0x65a440a89824AB464d7c94B184eF494c1457258D;
    address public registry = 0x7D7fEF7bF8bE4DB0FFf06346C59efc24EE8e4c22;

    address public mellowOracle = 0x3EFf1DA9e5f72d51F268937d3A5426c2bf5eFf4A;

    address public uniManager = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;

    function runCollector() public {
        UniV3Helper helper = new UniV3Helper(INonfungiblePositionManager(uniManager));
        DataCollector d = new DataCollector(
            usdc,
            INonfungiblePositionManager(uniManager),
            IVaultRegistry(registry),
            helper,
            MellowOracle(mellowOracle),
            deployer
        );

        d.setupOracleMask(weth, 32);
        d.setupOracleMask(usdc, 32);

        console.log("collector: ", address(d));
    }

    function run() external {
        vm.startBroadcast();
        runCollector();
    }
}
