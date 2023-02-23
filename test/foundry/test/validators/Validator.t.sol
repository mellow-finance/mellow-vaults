// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "forge-std/console2.sol";

import "../../src/ProtocolGovernance.sol";
import "../../src/MockOracle.sol";
import "../../src/ERC20RootVaultHelper.sol";
import "../../src/VaultRegistry.sol";

import "../../src/validators/GearValidator.sol";

import "../../src/vaults/GearboxVault.sol";
import "../../src/vaults/IntegrationVault.sol";
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

contract ValidatorTest is Test {

    address vault = 0x3e80E11C8fD3e05221fE63BE3487f9f0A4316Dc8;
    address admin = 0x565766498604676D9916D4838455Cc5fED24a5B3;
    address operator = 0x136348814f89fcbF1a0876Ca853D48299AFB8b3c;

    function test() public {
        
        ProtocolGovernance governance = ProtocolGovernance(0xDc9C17662133fB865E7bA3198B67c53a617B2153);
        GearValidator g = new GearValidator(governance);

        vm.startPrank(admin);
        governance.stageValidator(0xA7Df60785e556d65292A2c9A077bb3A8fBF048BC, address(g));
        governance.stageValidator(0x0E9B5B092caD6F1c5E6bc7f89Ffe1abb5c95F1C2, address(g));
        governance.stageValidator(0xBa3335588D9403515223F109EdC4eB7269a9Ab5D, address(g));
        vm.warp(block.timestamp + 86400);
        governance.commitValidator(0xA7Df60785e556d65292A2c9A077bb3A8fBF048BC);
        governance.commitValidator(0x0E9B5B092caD6F1c5E6bc7f89Ffe1abb5c95F1C2);
        governance.commitValidator(0xBa3335588D9403515223F109EdC4eB7269a9Ab5D);

        bytes32[13] memory Z = [bytes32(0xd298b6c2c993d61130fa6ecaecbefc46e30b45ad5ef9d0869cda56d9e21be65c), 0x8fa9f65ddf2c06f7e800eebfac1f9c1dff4cd78be0d38295c14eeda9257021ea, 0x2cfb6085e6215f83864785a46674c67bde9122956a97217a6a3432905fb07e49,0x41e12518f4f2594ee84b5316fe20c97d9f8ee37aac3d95dce2d94ed4630587b8,0x3f495f0fd26f26b0a01de8baf91595a9bf76d999e8c4d9ca4236cd7fdd82bca0,0xc832dee14ccdd67d416bdb21c67b6bedb77d7452d9db9fb08bfffbba2afe04d1,0x4473836f0feef410d67a41a9e1c22d87bfdb460cd0d5e5586a564074feb65103,0x3cb5920c9551543c8ff690605b3e0d2bf275098ac453ad1c6926f5f6674b27ba,0x3cd4a9d8fdf5e8e1c6c814ce5ee73ab71c9d3a4b770042026c53f704169a6a27,0x25c2284a82bdc9ef24fb118c23742ab858a0661c32dadaa1accf76837cf7844c,0x2dafe700c80a18ce2408333589bbdd00f17870c477f8c3bb9c314c8826a790d5,0xfd4b91bc2567ad585ac2c1d735361ce137b9707f3672d7528ae942707541ec0a,0xcb57c570dce77a879ab42bf9cd5264ab530379f04fecb8449e402c141118b440];
        bytes32[] memory Q = new bytes32[](13);

        for (uint256 i = 0; i < 13; ++i) {
            Q[i] = Z[i];
        }

        bytes memory data = abi.encode(uint256(1817), address(0x3e80E11C8fD3e05221fE63BE3487f9f0A4316Dc8), 34383455536135262260435, Q);

        vm.stopPrank();
        vm.startPrank(operator);

        IntegrationVault(vault).externalCall(0xA7Df60785e556d65292A2c9A077bb3A8fBF048BC, 0x2e7ba6ef, data);

        data = abi.encode(address(0x0E9B5B092caD6F1c5E6bc7f89Ffe1abb5c95F1C2), uint256(34383455536135262260435));
        IntegrationVault(vault).externalCall(0xBa3335588D9403515223F109EdC4eB7269a9Ab5D, 0x095ea7b3, data);

        data = abi.encode(uint256(0), uint256(1), uint256(34383455536135262260435), uint256(0), bool(false));
        IntegrationVault(vault).externalCall(0x0E9B5B092caD6F1c5E6bc7f89Ffe1abb5c95F1C2, 0x394747c5, data);

    }
        

}


//["0xd298b6c2c993d61130fa6ecaecbefc46e30b45ad5ef9d0869cda56d9e21be65c","0x8fa9f65ddf2c06f7e800eebfac1f9c1dff4cd78be0d38295c14eeda9257021ea","0x2cfb6085e6215f83864785a46674c67bde9122956a97217a6a3432905fb07e49","0x41e12518f4f2594ee84b5316fe20c97d9f8ee37aac3d95dce2d94ed4630587b8","0x3f495f0fd26f26b0a01de8baf91595a9bf76d999e8c4d9ca4236cd7fdd82bca0","0xc832dee14ccdd67d416bdb21c67b6bedb77d7452d9db9fb08bfffbba2afe04d1","0x4473836f0feef410d67a41a9e1c22d87bfdb460cd0d5e5586a564074feb65103","0x3cb5920c9551543c8ff690605b3e0d2bf275098ac453ad1c6926f5f6674b27ba","0x3cd4a9d8fdf5e8e1c6c814ce5ee73ab71c9d3a4b770042026c53f704169a6a27","0x25c2284a82bdc9ef24fb118c23742ab858a0661c32dadaa1accf76837cf7844c","0x2dafe700c80a18ce2408333589bbdd00f17870c477f8c3bb9c314c8826a790d5","0xfd4b91bc2567ad585ac2c1d735361ce137b9707f3672d7528ae942707541ec0a","0xcb57c570dce77a879ab42bf9cd5264ab530379f04fecb8449e402c141118b440"]