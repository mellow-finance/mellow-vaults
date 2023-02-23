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
    bytes4 public constant EXCHANGE_SELECTOR = 0x5b41b908;
    bytes4 public constant APPROVE_SELECTOR = 0x095ea7b3;

    uint256 public constant Q96 = 2**96;

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
        require(value == 0, ExceptionsLibrary.INVALID_VALUE);
        if (selector == APPROVE_SELECTOR) {
            (address spender, uint256 valueToApprove) = abi.decode(data, (address, uint256));
            require(valueToApprove < Q96 || valueToApprove == type(uint256).max, ExceptionsLibrary.INVARIANT);

            require(
                ICurvePool(spender).coins(uint256(0)) == addr || ICurvePool(spender).coins(uint256(1)) == addr,
                ExceptionsLibrary.INVALID_TARGET
            );
        } else if (selector == EXCHANGE_SELECTOR) {
            (uint256 i, , , ) = abi.decode(data, (uint256, uint256, uint256, uint256));

            address tokenFrom = ICurvePool(addr).coins(i);
            address primaryToken = IGearboxVault(msg.sender).primaryToken();

            require(tokenFrom != primaryToken, ExceptionsLibrary.FORBIDDEN);
        } else if (selector != CLAIM_SELECTOR) {
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
