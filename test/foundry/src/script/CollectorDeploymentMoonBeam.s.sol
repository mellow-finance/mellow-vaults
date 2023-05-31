// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "forge-std/Script.sol";

import "../../src/utils/DataCollector.sol";
import "../../src/utils/UniV3Helper.sol";

import "../../src/oracles/UniV2Oracle.sol";
import "../../src/oracles/UniV3Oracle.sol";
import "../../src/oracles/ChainlinkOracle.sol";
import "../../src/oracles/MellowOracle.sol";

contract MoonBeamDeploymentC is Script {

    address deployer = 0x7ee9247b6199877F86703644c97784495549aC5E;
    address public wglmr = 0xAcc15dC74880C9944775448304B263D191c6077F;
    address public usdc = 0x931715FEE2d06333043d11F658C8CE934aC61D0c;

    address public governance = 0xD1770b8Ce5943F40186747718FB6eD0b4dcf86a4;
    address public registry = 0x6A4c92818C956AFC22eb33ce50b65090e9187FFD;

    address public uniManager = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;

    function runCollector() public {

        UniV2Oracle fake = new UniV2Oracle(IUniswapV2Factory(address(0)));

        IUniswapV3Pool[] memory pools = new IUniswapV3Pool[](0);
        UniV3Oracle fake2 = new UniV3Oracle(IUniswapV3Factory(address(0)), pools, deployer);

        address[] memory tokens = new address[](2);
        tokens[0] = wglmr;
        tokens[1] = usdc;

        address[] memory oracles = new address[](2);
        oracles[0] = 0x4497B606be93e773bbA5eaCFCb2ac5E2214220Eb;
        oracles[1] = 0xA122591F60115D63421f66F752EF9f6e0bc73abC;

        ChainlinkOracle c = new ChainlinkOracle(tokens, oracles, deployer);

        MellowOracle m = new MellowOracle(fake, fake2, c);

        console2.log("oracle:", address(m));
        
        UniV3Helper helper = new UniV3Helper(INonfungiblePositionManager(uniManager));
        DataCollector d = new DataCollector(usdc, INonfungiblePositionManager(uniManager), IVaultRegistry(registry), helper, m, deployer);

        d.setupOracleMask(wglmr, 32);
        d.setupOracleMask(usdc, 32);

        console.log("collector: ", address(d));

    }

    function run() external {

        vm.startBroadcast();
        runCollector();
    }
}