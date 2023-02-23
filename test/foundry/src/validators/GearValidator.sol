// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/validators/IValidator.sol";
import "../interfaces/vaults/IGearboxVault.sol";
import "../interfaces/external/gearbox/helpers/curve/ICurvePool.sol";
import "../interfaces/IProtocolGovernance.sol";
import "../libraries/PermissionIdsLibrary.sol";
import "../utils/ContractMeta.sol";
import "./Validator.sol";

contract GearValidator is ContractMeta, Validator {
    bytes4 public constant CLAIM_SELECTOR = 0x2e7ba6ef;
    bytes4 public constant SWAP_SELECTOR = 0x394747c5;
    bytes4 public constant APPROVE_SELECTOR = 0x095ea7b3;

    constructor(IProtocolGovernance protocolGovernance_) BaseValidator(protocolGovernance_) {}

    // -------------------  EXTERNAL, VIEW  -------------------

    // @inhericdoc IValidator
    function validate(
        address,
        address addr,
        uint256 value,
        bytes4 selector,
        bytes calldata data
    ) external view {
        if (selector == CLAIM_SELECTOR) {
            require(value == 0, ExceptionsLibrary.INVALID_VALUE);
        }
        else if (selector == APPROVE_SELECTOR) {
            require(value == 0, ExceptionsLibrary.INVALID_VALUE);
            (address spender, ) = abi.decode(data, (address, uint256));

            require(ICurvePool(spender).coins(uint256(0)) == addr || ICurvePool(spender).coins(uint256(1)) == addr);
        }
        else if (selector == SWAP_SELECTOR) {
            require(value == 0, ExceptionsLibrary.INVALID_VALUE);
            (uint256 i, , , ,) = abi.decode(data, (uint256, uint256, uint256, uint256, bool));

            address tokenFrom = ICurvePool(addr).coins(i);
            address primaryToken = IGearboxVault(msg.sender).primaryToken();

            require(tokenFrom != primaryToken, ExceptionsLibrary.FORBIDDEN);
        } 
        else {
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
