// SPDX-License-Identifier: BSL-1.1
pragma solidity 0.8.9;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

contract TwoPhaseAddressPermissionControl {
    using EnumerableSet for EnumerableSet.AddressSet;

    uint256 private _stagedToCommitAt;
    mapping(address => uint256) private _delayedPermissionMasks;
    mapping(address => uint256) private _permissionMasks;
    EnumerableSet.AddressSet private _delayedAddresses;
    EnumerableSet.AddressSet private _addresses;

    event GrantedDelayedPermission(address indexed sender, address indexed target, uint8 indexed permissionId);
    event RevokedDelayedPermission(address indexed sender, address indexed target, uint8 indexed permissionId);
    event RolledBackDelayedPermissions(address indexed sender);
    event StagedDelayedPermissionsToCommit(address indexed sender);
    event RolledBackStagedDelayedPermissions(address indexed sender);
    event CommittedStagedDelayedPermissions(address indexed sender);
    event RevokedPermissionInstant(address indexed sender, address indexed target, uint8 permissionId);
    event GrantedPermissionInstant(address indexed sender, address indexed target, uint8 permissionId);

    function addresses() public view returns (address[] memory) {
        return _addresses.values();
    }

    function addressesLength() public view returns (uint256) {
        return _addresses.length();
    }

    function addressAt(uint256 index) public view returns (address) {
        return _addresses.at(index);
    }

    function permissionMaskOf(address target) public view returns (uint256) {
        return _permissionMasks[target];
    }

    function delayedAddresses() public view returns (address[] memory) {
        return _delayedAddresses.values();
    }

    function delayedAddressesLength() public view returns (uint256) {
        return _delayedAddresses.length();
    }

    function delayedAddressAt(uint256 index) public view returns (address) {
        return _delayedAddresses.at(index);
    }

    function delayedPermissionMaskOf(address target) public view returns (uint256) {
        return _delayedPermissionMasks[target];
    }

    function isStagedToCommit() public view returns (bool) {
        return _isStagedToCommit();
    }

    function stagedToCommitAt() public view returns (uint256) {
        return _stagedToCommitAt;
    }

    function _permissionIdToMask(uint8 permissionId) private pure returns (uint256) {
        return 1 << (permissionId);
    }

    function _isStagedToCommit() private view returns (bool) {
        return _stagedToCommitAt != 0;
    }

    function _clearDelayedPermissions() private {
        uint256 length = _delayedAddresses.length();
        for (uint256 i; i != length; ++i) {
            address target = _delayedAddresses.at(i);
            delete _delayedPermissionMasks[target];
            _delayedAddresses.remove(target);
        }
    }

    function rollbackDelayedPermissions() internal {
        require(!_isStagedToCommit(), "Already staged");
        _clearDelayedPermissions();
        emit RolledBackDelayedPermissions(msg.sender);
    }

    function rollbackStagedDelayedPermissions() internal {
        require(_isStagedToCommit(), "Not staged");
        _clearDelayedPermissions();
        delete _stagedToCommitAt;
        emit RolledBackStagedDelayedPermissions(msg.sender);
    }

    function _hasPermissionId(address addr, uint8 permissionId) internal view returns (bool) {
        return _permissionMasks[addr] & _permissionIdToMask(permissionId) != 0;
    }

    function _grantInstantPermissionId(address to, uint8 permissionId) internal {
        uint256 diff = _permissionIdToMask(permissionId);
        uint256 currentMask = _permissionMasks[to];
        require(currentMask & diff == 0, "Permission already granted");
        _permissionMasks[to] = currentMask | diff;
        _addresses.add(to);
        emit GrantedPermissionInstant(msg.sender, to, permissionId);
    }

    function _revokeInstantPermissionId(address from, uint8 permissionId) internal {
        uint256 diff = _permissionIdToMask(permissionId);
        uint256 currentMask = _permissionMasks[from];
        require(currentMask & diff != 0, "Permission not yet granted");
        _permissionMasks[from] = currentMask & (~ diff);
        if (_permissionMasks[from] == 0) {
            delete _permissionMasks[from];
            _addresses.remove(from);
        }
        emit RevokedPermissionInstant(msg.sender, from, permissionId);
    }

    function _revokeDelayedPermissionId(address from, uint8 permissionId) internal {
        require(!_isStagedToCommit(), "Already staged");
        uint256 diff = _permissionIdToMask(permissionId);
        if (!_delayedAddresses.contains(from)) {
            _delayedAddresses.add(from);
            _delayedPermissionMasks[from] = _permissionMasks[from];
        }
        uint256 currentMask = _delayedPermissionMasks[from];
        require(currentMask & diff != 0, "Permission not yet granted");
        _delayedPermissionMasks[from] = currentMask & (~ diff);
        emit RevokedDelayedPermission(msg.sender, from, permissionId);
    }

    function _grantDelayedPermissionId(address to, uint8 permissionId) internal {
        require(!_isStagedToCommit(), "Already staged");
        uint256 diff = _permissionIdToMask(permissionId);
        if (!_delayedAddresses.contains(to)) {
            _delayedAddresses.add(to);
            _delayedPermissionMasks[to] = _permissionMasks[to];
        }
        uint256 currentMask = _delayedPermissionMasks[to];
        require(currentMask & diff == 0, "Permission already granted");
        _delayedPermissionMasks[to] = currentMask | diff;
        emit GrantedDelayedPermission(msg.sender, to, permissionId);
    }

    function _stageDelayedPermissionsToCommit(uint256 delay) internal {
        _stagedToCommitAt = block.timestamp + delay;
        emit StagedDelayedPermissionsToCommit(msg.sender);
    }

    function _commitStagedPermissions() internal {
        require(_isStagedToCommit());
        require(block.timestamp >= _stagedToCommitAt);
        uint256 length = _delayedAddresses.length();
        for (uint256 i; i != length; ++i) {
            address delayedAddress = _delayedAddresses.at(i);
            uint256 delayedPermissionMask = _delayedPermissionMasks[delayedAddress];
            if (delayedPermissionMask == 0) {
                delete _permissionMasks[delayedAddress];
                _addresses.remove(delayedAddress);
            } else {
                _permissionMasks[delayedAddress] = delayedPermissionMask;
                _addresses.add(delayedAddress);
            }
        }
        _clearDelayedPermissions();
        delete _stagedToCommitAt;
    }
}
