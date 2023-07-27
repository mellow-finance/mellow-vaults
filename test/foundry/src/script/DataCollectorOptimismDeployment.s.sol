// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "forge-std/Script.sol";

import "../utils/DataCollector.sol";
import "../utils/UniV3Helper.sol";

contract DataCollectorOptimismDeployment is Script {
    address public constant USDC = 0x7F5c764cBc14f9669B88837ca1490cCa17c31607;

    function run() external {
        vm.startBroadcast(vm.envUint("DEPLOYER_PK"));

        MellowOracle mellowOracle = MellowOracle(0xA9FC72eE105D43C885E48Ab18148D308A55d04c7);

        DataCollector collector = new DataCollector(
            USDC,
            INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88),
            IVaultRegistry(0x5cC7Cb6fD996dD646cF613ac94E9E0D2436a083A),
            new UniV3Helper(INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88)),
            mellowOracle,
            0x7ee9247b6199877F86703644c97784495549aC5E
        );

        IChainlinkOracle chainlinkOracle = mellowOracle.chainlinkOracle();
        address[] memory tokens = chainlinkOracle.supportedTokens();

        for (uint256 i = 0; i < tokens.length; i++) {
            collector.setupOracleMask(tokens[i], 63);
        }

        vm.stopBroadcast();
    }
}
