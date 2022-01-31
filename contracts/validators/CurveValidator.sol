// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "../interfaces/external/curve/I3Pool.sol";
import "../interfaces/validators/IValidator.sol";
import "../interfaces/vaults/IVault.sol";
import "../interfaces/IProtocolGovernance.sol";
import "../interfaces/utils/IContractMeta.sol";
import "../libraries/CommonLibrary.sol";
import "../libraries/PermissionIdsLibrary.sol";
import "../libraries/ExceptionsLibrary.sol";
import "./Validator.sol";

contract CurveValidator is IContractMeta, Validator {
    using EnumerableSet for EnumerableSet.AddressSet;
    bytes32 public constant CONTRACT_NAME = "CurveValidator";
    bytes32 public constant CONTRACT_VERSION = "1.0.0";
    bytes4 public constant EXCHANGE_SELECTOR = 0x3df02124;

    constructor(IProtocolGovernance protocolGovernance_) BaseValidator(protocolGovernance_) {}

    // -------------------  EXTERNAL, VIEW  -------------------

    // @inhericdoc IValidator
    function validate(
        address,
        address addr,
        uint256,
        bytes calldata data
    ) external view {
        IVault vault = IVault(msg.sender);
        bytes4 selector = CommonLibrary.getSelector(data);
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
}
