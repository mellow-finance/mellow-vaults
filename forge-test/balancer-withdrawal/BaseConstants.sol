// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

library Constants {
    uint256 public constant Q96 = 2**96;

    address public constant protocolTreasury = 0x35b8528Fd701F5696AeB4e22c79b5009f7C6D134;
    address public constant strategyTreasury = 0x208e7EF0eD1463e540C117c592E50e76F4BE2Eca;
    address public constant deployer = 0x7ee9247b6199877F86703644c97784495549aC5E;
    address public constant operator = 0xE4445221cF7e2070C2C1928d0B3B3e99A0D4Fb8E;

    address public constant admin = 0x3c1a81D6a635Db2F6d0c15FC12d43c7640cBD25f;

    address public constant weth = 0x4200000000000000000000000000000000000006;
    address public constant wsteth = 0x2Ae3F1Ec7F1F5012CFEab0185bfc7aa3cf0DEc22;
    address public constant usdc = 0xd9aAEc86B65D86f6A7B5B1b0c42FFA531710b6CA;
    address public constant bal = 0x4158734D47Fc9692176B5085E0F52ee0Da5d47F1;

    address public constant governance = 0xCD8237f2b332e482DaEaA609D9664b739e93097d;
    address public constant registry = 0xc02a7B4658861108f9837007b2DF2007d6977116;

    address public constant erc20RootGovernance = 0x558055ae71ee1BC926905469301a232066eD4673;
    address public constant erc20Governance = 0x12ED6474A19f24e3a635E312d85fbAc177D66670;
    address public constant uniV3Governance = 0x5a8552f4Bbac3c31F6E618Da23BaFFf5EaE29847;
    address public constant uniV3Helper = 0x070D1CE4eEFd798107A1C4f30b2c47375f3e5dc9;
    address public constant balancerCSPVaultGovernance = 0xD75E933Ae1F00aA186B6d4ea15D226305d795248;

    address public constant mellowOracle = 0x15b1bC5DF5C44F469394D295959bBEC861893F09;

    address public constant openOceanRouter = 0x6352a56caadC4F1E25CD6c75970Fa768A3304e64;
    address public constant uniswapPositionManager = 0x03a520b32C04BF3bEEf7BEb72E919cf822Ed34f1;
    address public constant uniswapV3Factory = 0x33128a8fC17869897dcE68Ed026d694621f6FDfD;
    address public constant uniswapV3Router = 0x2626664c2603336E57B271c5C0b26F421741e481;

    address public constant balancerVault = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    address public constant balancerWstethWethPool = 0xFb4C2E6E6e27B5b4a07a36360C89EDE29bB3c9B6;
    address public constant balancerMinter = address(1); // FIX THAT
    address public constant balancerWstethWethStakinig = 0x2279abf4bdAb8CF29EAe4036262c62dBA6460306;

    address public constant depositWrapper = 0xca89DeB98290ec57c9838ab2edE4D3DbBDEe03B9;
}
