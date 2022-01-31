// SPDX-License-Identifier: BSL-1.1
pragma solidity 0.8.9;

import "../interfaces/utils/IContractMeta.sol";

abstract contract ContractMeta is IContractMeta {
    function CONTRACT_NAME_READABLE() external pure virtual returns (string memory);

    function CONTRACT_VERSION_READABLE() external pure virtual returns (string memory);
}
