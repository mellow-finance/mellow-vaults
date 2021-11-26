// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "../interfaces/IProtocolGovernance.sol";
import "./interfaces/ITrader.sol";
import "./interfaces/IMasterTrader.sol";
import "./libraries/TraderLibrary.sol";

contract MasterTrader is ERC165, IMasterTrader {
    using EnumerableSet for EnumerableSet.UintSet;

    address public immutable protocolGovernance;
    mapping(address => uint256) public traderIdByAddress;
    mapping(uint256 => address) public traderAddressById;

    uint256 internal _topTraderId;
    EnumerableSet.UintSet internal _traders;
    mapping(SwapType => bytes4) internal _swapTypeToSelector;

    constructor(address _protocolGovernance) {
        protocolGovernance = _protocolGovernance;
        _swapTypeToSelector[SwapType.EXACT_INPUT_SINGLE] = ITrader.swapExactInputSingle.selector;
        _swapTypeToSelector[SwapType.EXACT_OUTPUT_SINGLE] = ITrader.swapExactOutputSingle.selector;
        _swapTypeToSelector[SwapType.EXACT_INPUT_MULTIHOP] = ITrader.swapExactInputMultihop.selector;
        _swapTypeToSelector[SwapType.EXACT_OUTPUT_MULTIHOP] = ITrader.swapExactOutputMultihop.selector;
    }

    function traders() external view returns (uint256[] memory) {
        return _traders.values();
    }

    function addTrader(address traderAddress) external {
        _requireProtocolAdmin();
        require(traderIdByAddress[traderAddress] == 0, TraderLibrary.TRADER_ALREADY_REGISTERED_EXCEPTION);
        require(ERC165(traderAddress).supportsInterface(TraderLibrary.TRADER_INTERFACE_ID));
        traderIdByAddress[traderAddress] = ++_topTraderId;
        traderAddressById[_topTraderId] = traderAddress;
        _traders.add(_topTraderId);
    }

    function removeTraderByAddress(address traderAddress) external {
        _requireProtocolAdmin();
        uint256 traderIdToRemove = traderIdByAddress[traderAddress];
        require(traderIdToRemove != 0, TraderLibrary.TRADER_NOT_FOUND_EXCEPTION);
        delete traderIdByAddress[traderAddress];
        delete traderAddressById[traderIdToRemove];
        _traders.remove(traderIdToRemove);
    }

    function removeTraderById(uint256 traderId) external {
        _requireProtocolAdmin();
        address traderAddressToRemove = traderAddressById[traderId];
        require(traderAddressToRemove != address(0), TraderLibrary.TRADER_NOT_FOUND_EXCEPTION);
        delete traderIdByAddress[traderAddressToRemove];
        delete traderAddressById[traderId];
        _traders.remove(traderId);
    }

    function trade(
        uint256 traderId,
        address input,
        address output,
        uint256 amount,
        SwapType swapType,
        bytes calldata options
    ) external returns (uint256) {
        address traderAddress = traderAddressById[traderId];
        require(traderAddress != address(0), TraderLibrary.TRADER_NOT_FOUND_EXCEPTION);
        address recipient = msg.sender;

        (bool success, bytes memory returndata) = traderAddress.call(
            abi.encodeWithSelector(_swapTypeToSelector[swapType], input, output, amount, recipient, options)
        );
        require(success, TraderLibrary.TRADER_NOT_FOUND_EXCEPTION);
        return abi.decode(returndata, (uint256));
    }

    function supportsInterface(bytes4 interfaceId) public pure override returns (bool) {
        return interfaceId == this.supportsInterface.selector;
    }

    function _requireProtocolAdmin() internal view {
        require(
            IProtocolGovernance(protocolGovernance).isAdmin(msg.sender),
            TraderLibrary.PROTOCOL_ADMIN_REQUIRED_EXCEPTION
        );
    }
}
