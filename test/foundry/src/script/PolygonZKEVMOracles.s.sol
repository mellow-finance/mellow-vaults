// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "forge-std/Vm.sol";

import "../../src/oracles/ChainlinkOracle.sol";
import "../../src/oracles/PancakeChainlinkOracle.sol";

contract PolygonZKEVMOracles is Script {
    address public deployer = 0x7ee9247b6199877F86703644c97784495549aC5E;
    address public constant USDC = 0xA8CE8aee21bC2A48a5EF670afCc9274C7bbbC035;
    address public constant USDT = 0x1E4a5963aBFD975d8c9021ce480b42188849D41d;
    address public constant WETH = 0x4F9A0e7FD2Bf6067db6994CF12E4495Df938E6e9;

    IPancakeNonfungiblePositionManager public positionManager =
        IPancakeNonfungiblePositionManager(0x46A15B0b27311cedF172AB29E4f4766fbE7F4364);

    function run() external {
        vm.startBroadcast(vm.envUint("DEPLOYER_PK"));

        address[] memory tokens = new address[](3);
        tokens[0] = USDC;
        tokens[1] = USDT;
        tokens[2] = WETH;

        uint24[] memory fees = new uint24[](3);
        fees[1] = 100;
        fees[2] = 500;

        address[] memory oracles = new address[](3);
        for (uint256 i = 0; i < tokens.length; i++) {
            PancakeChainlinkOracle pcOracle = new PancakeChainlinkOracle(tokens[i], USDC, fees[i], positionManager);
            console2.log(pcOracle.description(), uint256(pcOracle.latestAnswer()));
            oracles[i] = address(pcOracle);
        }

        ChainlinkOracle oracle = new ChainlinkOracle(tokens, oracles, deployer);

        console2.log(address(oracle));

        vm.stopBroadcast();
    }
}
