// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.9;

import "../interfaces/validators/IBaseValidator.sol";
import "../interfaces/IProtocolGovernance.sol";
import "../libraries/ExceptionsLibrary.sol";

contract BaseValidator is IBaseValidator {
    IBaseValidator.ValidatorParams internal _validatorParams;
    IBaseValidator.ValidatorParams internal _stagedValidatorParams;
    uint256 internal _stagedValidatorParamsTimestamp;

    constructor(IProtocolGovernance protocolGovernance) {
        _validatorParams = IBaseValidator.ValidatorParams({protocolGovernance: protocolGovernance});
    }

    // -------------------  EXTERNAL, VIEW  -------------------

    /// @inheritdoc IBaseValidator
    function stagedValidatorParams() external view returns (ValidatorParams memory) {
        return _stagedValidatorParams;
    }

    /// @inheritdoc IBaseValidator
    function stagedValidatorParamsTimestamp() external view returns (uint256) {
        return _stagedValidatorParamsTimestamp;
    }

    /// @inheritdoc IBaseValidator
    function validatorParams() external view returns (ValidatorParams memory) {
        return _validatorParams;
    }

    // -------------------  EXTERNAL, MUTATING  -------------------

    /// @notice Stages params that could have been committed after governance delay expires.
    /// @param newParams Params to stage
    function stageValidatorParams(IBaseValidator.ValidatorParams calldata newParams) external {
        IProtocolGovernance governance = _validatorParams.protocolGovernance;
        require(governance.isAdmin(msg.sender), ExceptionsLibrary.FORBIDDEN);
        _stagedValidatorParams = newParams;
        _stagedValidatorParamsTimestamp = block.timestamp + governance.governanceDelay();
        emit StagedValidatorParams(tx.origin, msg.sender, newParams, _stagedValidatorParamsTimestamp);
    }

    /// @notice Commits staged params
    function commitValidatorParams() external {
        require(_stagedValidatorParamsTimestamp != 0, ExceptionsLibrary.INVALID_STATE);
        IProtocolGovernance governance = _validatorParams.protocolGovernance;
        require(governance.isAdmin(msg.sender), ExceptionsLibrary.FORBIDDEN);
        require(block.timestamp >= _stagedValidatorParamsTimestamp, ExceptionsLibrary.TIMESTAMP);
        _validatorParams = _stagedValidatorParams;
        delete _stagedValidatorParams;
        delete _stagedValidatorParamsTimestamp;
        emit CommittedValidatorParams(tx.origin, msg.sender, _validatorParams);
    }

    /// @notice Emitted when new params are staged for commit
    /// @param origin Origin of the transaction (tx.origin)
    /// @param sender Sender of the call (msg.sender)
    /// @param newParams New params that were staged for commit
    /// @param when When the params could be committed
    event StagedValidatorParams(
        address indexed origin,
        address indexed sender,
        IBaseValidator.ValidatorParams newParams,
        uint256 when
    );

    /// @notice Emitted when new params are staged for commit
    /// @param origin Origin of the transaction (tx.origin)
    /// @param sender Sender of the call (msg.sender)
    /// @param params New params that were staged for commit
    event CommittedValidatorParams(
        address indexed origin,
        address indexed sender,
        IBaseValidator.ValidatorParams params
    );
}
