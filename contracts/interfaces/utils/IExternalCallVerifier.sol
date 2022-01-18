// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "../IProtocolGovernance.sol";

interface IExternalCallVerifier {
    // @notice Runs a EMV-like code over data.
    // @dev Can revert on code execution overflow
    // @param code Bytecode to execute
    // @param data Data for the code (transaction data to verify)
    // @return res 0 on success or error code otherwise
    function verify(
        bytes memory code,
        bytes memory data,
        IProtocolGovernance protocolGovernance
    ) external view returns (uint256 res);
}
