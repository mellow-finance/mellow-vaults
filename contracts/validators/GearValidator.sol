// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/validators/IValidator.sol";
import "../interfaces/IProtocolGovernance.sol";
import "../libraries/PermissionIdsLibrary.sol";
import "../utils/ContractMeta.sol";
import "./Validator.sol";

contract GearValidator is ContractMeta, Validator {
    bytes4 public constant CLAIM_SELECTOR = 0x2e7ba6ef;
    address public constant gearAirdrop = 0xA7Df60785e556d65292A2c9A077bb3A8fBF048BC;

    bytes4 public constant SWAP_SELECTOR = 0x65b2489b;
    address public constant pool = 0x0E9B5B092caD6F1c5E6bc7f89Ffe1abb5c95F1C2;

    constructor(IProtocolGovernance protocolGovernance_) BaseValidator(protocolGovernance_) {}

    // -------------------  EXTERNAL, VIEW  -------------------

    // @inhericdoc IValidator
    function validate(
        address,
        address addr,
        uint256 value,
        bytes4 selector,
        bytes calldata data
    ) external pure {
        if (selector == CLAIM_SELECTOR) {
            require(value == 0, ExceptionsLibrary.INVALID_VALUE);
            require(addr == gearAirdrop, ExceptionsLibrary.INVALID_TARGET);
        } else if (selector == SWAP_SELECTOR) {
            require(value == 0, ExceptionsLibrary.INVALID_VALUE);
            require(addr == pool, ExceptionsLibrary.INVALID_TARGET);
            (uint256 i, , , ) = abi.decode(data, (uint256, uint256, uint256, uint256));
            require(i == 0, ExceptionsLibrary.INVARIANT);
        } else {
            revert(ExceptionsLibrary.INVALID_SELECTOR);
        }
    }

    // -------------------  INTERNAL, VIEW  -------------------

    function _contractName() internal pure override returns (bytes32) {
        return bytes32("GearValidator");
    }

    function _contractVersion() internal pure override returns (bytes32) {
        return bytes32("1.0.0");
    }
}
