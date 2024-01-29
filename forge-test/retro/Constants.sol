// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

library Constants {
    uint256 public constant Q96 = 2**96;

    address public constant protocolTreasury = 0x646f851A97302Eec749105b73a45d461B810977F;
    address public constant strategyTreasury = 0x83FC42839FAd06b737E0FC37CA88E84469Dbd56B;
    address public constant deployer = 0x7ee9247b6199877F86703644c97784495549aC5E;
    address public constant operator = 0xE4445221cF7e2070C2C1928d0B3B3e99A0D4Fb8E;

    address public constant weth = 0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619;
    address public constant wbtc = 0x1BFD67037B42Cf73acF2047067bd4F2C47D9BfD6;
    address public constant cash = 0x5D066D022EDE10eFa2717eD3D79f22F949F8C175;
    address public constant wmatic = 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270;
    address public constant usdc = 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;
    address public constant usdt = 0xc2132D05D31c914a87C6611C10748AEb04B58e8F;

    address public constant governance = 0x8Ff3148CE574B8e135130065B188960bA93799c6;
    address public constant registry = 0xd3D0e85F225348a2006270Daf624D8c46cAe4E1F;
    address public constant erc20RetroRootVaultGovernance = 0xC2Fa6E348A7AE86D32aba71528848dFd38A3E6F2;
    address public constant erc20Governance = 0x05164eC2c3074A4E8eA20513Fbe98790FfE930A4;
    address public constant uniV3RetroVaultGovernance = 0xe84f1350DE1208469AE7c8f343652E60A82aB76b;
    address public constant mellowOracle = 0x27AeBFEBDd0fde261Ec3E1DF395061C56EEC5836;

    address public constant uniV3Helper = 0x484cadA63222a0810295fa393A079E4961145864;

    address public constant oneInchRouter = 0x1111111254EEB25477B68fb85Ed929f73A960582;
    address public constant depositWrapper = 0xa5Ece1f667DF4faa82cF29959517a15f84fD7862;
}
