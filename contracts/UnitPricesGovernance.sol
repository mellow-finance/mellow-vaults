// SPDX-License-Identifier: BSL-1.1
pragma solidity 0.8.9;

import "./interfaces/IUnitPricesGovernance.sol";
import "./libraries/ExceptionsLibrary.sol";
import "./utils/DefaultAccessControl.sol";

contract UnitPricesGovernance is IUnitPricesGovernance, DefaultAccessControl {
    uint256 public constant DELAY = 14 days;
    /// @inheritdoc IUnitPricesGovernance
    mapping(address => uint256) public unitPrices;
    /// @inheritdoc IUnitPricesGovernance
    mapping(address => uint256) public stagedUnitPrices;
    /// @inheritdoc IUnitPricesGovernance
    mapping(address => uint256) public stagedUnitPricesTimestamps;

    constructor(address admin) DefaultAccessControl(admin) {}

    // -------------------  EXTERNAL, VIEW  -------------------

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(IERC165, AccessControlEnumerable)
        returns (bool)
    {
        return (interfaceId == type(IUnitPricesGovernance).interfaceId) || super.supportsInterface(interfaceId);
    }

    // -------------------  EXTERNAL, MUTATING  -------------------

    /// @inheritdoc IUnitPricesGovernance
    function stageUnitPrice(address token, uint256 value) external {
        _requireAdmin();
        stagedUnitPrices[token] = value;
        stagedUnitPricesTimestamps[token] = block.timestamp;
        emit UnitPriceRolledBack(tx.origin, msg.sender, token);
    }

    /// @inheritdoc IUnitPricesGovernance
    function rollbackUnitPrice(address token) external {
        _requireAdmin();
        delete stagedUnitPrices[token];
        delete stagedUnitPricesTimestamps[token];
        emit UnitPriceRolledBack(tx.origin, msg.sender, token);
    }

    /// @inheritdoc IUnitPricesGovernance
    function commitUnitPrice(address token) external {
        uint256 timestamp = stagedUnitPricesTimestamps[token];
        if (unitPrices[token] != 0) {
            require(timestamp > 0 && timestamp <= block.timestamp, ExceptionsLibrary.TIMESTAMP);
        }

        uint256 price = stagedUnitPrices[token];
        unitPrices[token] = price;
        delete stagedUnitPrices[token];
        delete stagedUnitPricesTimestamps[token];
        emit UnitPriceCommitted(tx.origin, msg.sender, token, price);
    }

    // ---------------------------------- EVENTS -------------------------------------

    /// @notice UnitPrice staged for commit
    /// @param origin Origin of the transaction (tx.origin)
    /// @param sender Sender of the call (msg.sender)
    /// @param token Token address
    /// @param unitPrice Unit price
    event UnitPriceStaged(address indexed origin, address indexed sender, address token, uint256 unitPrice);

    /// @notice UnitPrice rolled back
    /// @param origin Origin of the transaction (tx.origin)
    /// @param sender Sender of the call (msg.sender)
    /// @param token Token address
    event UnitPriceRolledBack(address indexed origin, address indexed sender, address token);

    /// @notice UnitPrice committed
    /// @param origin Origin of the transaction (tx.origin)
    /// @param sender Sender of the call (msg.sender)
    /// @param token Token address
    /// @param unitPrice Unit price
    event UnitPriceCommitted(address indexed origin, address indexed sender, address token, uint256 unitPrice);
}
