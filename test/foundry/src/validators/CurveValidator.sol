// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.9;

import "../interfaces/external/curve/I3Pool.sol";
import "../interfaces/vaults/IVault.sol";
import "../interfaces/IProtocolGovernance.sol";
import "../libraries/PermissionIdsLibrary.sol";
import "../libraries/ExceptionsLibrary.sol";
import "../utils/ContractMeta.sol";
import "./Validator.sol";

contract CurveValidator is ContractMeta, Validator {
    bytes4 public constant EXCHANGE_SELECTOR = 0x3df02124;

    constructor(IProtocolGovernance protocolGovernance_) BaseValidator(protocolGovernance_) {}

    // -------------------  EXTERNAL, VIEW  -------------------

    // @inhericdoc IValidator
    function validate(
        address,
        address addr,
        uint256,
        bytes4 selector,
        bytes calldata data
    ) external view {
        IVault vault = IVault(msg.sender);
        if (selector == EXCHANGE_SELECTOR) {
            (int128 i, int128 j, , ) = abi.decode(data, (int128, int128, uint256, uint256));
            require(i != j, ExceptionsLibrary.INVALID_VALUE);
            address to = I3Pool(addr).coins(uint256(uint128(j)));
            require(vault.isVaultToken(to), ExceptionsLibrary.INVALID_TOKEN);
            IProtocolGovernance protocolGovernance = _validatorParams.protocolGovernance;
            require(
                protocolGovernance.hasPermission(addr, PermissionIdsLibrary.ERC20_APPROVE),
                ExceptionsLibrary.FORBIDDEN
            );
        } else {
            revert(ExceptionsLibrary.INVALID_SELECTOR);
        }
    }

    // -------------------  INTERNAL, VIEW  -------------------

    function _contractName() internal pure override returns (bytes32) {
        return bytes32("CurveValidator");
    }

    function _contractVersion() internal pure override returns (bytes32) {
        return bytes32("1.0.0");
    }
}
