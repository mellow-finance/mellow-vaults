// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

import "../../src/interfaces/IProtocolGovernance.sol";
import "../../src/utils/ContractMeta.sol";

import "./Constants.sol";

library PermissionsCheck {
    function checkTokens(address[] memory tokens) external view {
        string memory logs = getLog(tokens);
        if (keccak256(abi.encode(logs)) != keccak256(abi.encode(""))) revert(logs);
    }

    function getLog(address[] memory tokens) public view returns (string memory logs) {
        for (uint256 i = 0; i < tokens.length; i++) {
            string memory token = string(
                abi.encodePacked(IERC20Metadata(tokens[i]).symbol(), " (", Strings.toHexString(tokens[i]), ")")
            );

            uint256 mask = IProtocolGovernance(Constants.governance).permissionMasks(tokens[i]);
            if ((mask & 12) != 12) {
                logs = string(abi.encodePacked(logs, token, " does not have permissions\n"));
            }
            address validator = IProtocolGovernance(Constants.governance).validators(tokens[i]);
            if (address(validator) == address(0)) {
                logs = string(abi.encodePacked(logs, token, " validator not set\n"));
            } else {
                if (
                    keccak256(abi.encode(ContractMeta(validator).contractName())) !=
                    keccak256(abi.encode("ERC20Validator"))
                ) {
                    logs = string(
                        abi.encodePacked(logs, token, " validator is wrong (", Strings.toHexString(validator), ")\n")
                    );
                }
            }
            if (IProtocolGovernance(Constants.governance).unitPrices(tokens[i]) == 0) {
                logs = string(abi.encodePacked(logs, token, " unit price is zero\n"));
            }
        }
    }
}
