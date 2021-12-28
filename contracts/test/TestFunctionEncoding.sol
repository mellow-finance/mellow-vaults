// SPDX-License-Identifier: BSL-1.1
pragma solidity 0.8.9;

import "../IntegrationVault.sol";
import "../interfaces/IVaultGovernance.sol";
import "../interfaces/IVault.sol";

contract TestFunctionEncoding {
    IntegrationVault public vault;

    constructor(IntegrationVault _vault) {
        vault = _vault;
    }

    function encodeWithSignatureTest(address from) external {
        bytes memory data = abi.encodeWithSignature("tvl()");
        vault.claimRewards(from, data);
    }
}
