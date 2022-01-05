// SPDX-License-Identifier: BSL-1.1
pragma solidity 0.8.9;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "../libraries/ExceptionsLibrary.sol";

contract AddressPermissionControl {
    using EnumerableSet for EnumerableSet.AddressSet;

    uint256 internal _stagedToCommitAt;

    mapping(address => uint256) private _stagedPermissionMasks;
    mapping(address => uint256) private _permissionMasks;
    EnumerableSet.AddressSet private _stagedAddresses;
    EnumerableSet.AddressSet private _addresses;

    function addresses() public view returns (address[] memory) {
        return _addresses.values();
    }

    function addressesLength() public view returns (uint256) {
        return _addresses.length();
    }

    function addressAt(uint256 index) public view returns (address) {
        return _addresses.at(index);
    }

    function permissionMask(address target) public view returns (uint256) {
        return _permissionMasks[target];
    }

    function stagedAddresses() public view returns (address[] memory) {
        return _stagedAddresses.values();
    }

    function stagedAddressesLength() public view returns (uint256) {
        return _stagedAddresses.length();
    }

    function stagedAddressAt(uint256 index) public view returns (address) {
        return _stagedAddresses.at(index);
    }

    function stagedPermissionMaskOf(address target) public view returns (uint256) {
        return _stagedPermissionMasks[target];
    }

    function _hasPermission(address addr, uint8 permissionId) internal view returns (bool) {
        return _permissionMasks[addr] & _permissionIdToMask(permissionId) != 0;
    }

    function _hasAllPermissions(address addr, uint8[] calldata permissionIds) internal view returns (bool) {
        for (uint256 i; i < permissionIds.length; ++i) {
            if (!_hasPermission(addr, permissionIds[i])) {
                return false;
            }
        }
        return true;
    }

    function _hasStagedPermission(address addr, uint8 permissionId) internal view returns (bool) {
        return _stagedPermissionMasks[addr] & _permissionIdToMask(permissionId) != 0;
    }

    function _isStagedToCommit() private view returns (bool) {
        return _stagedToCommitAt != 0;
    }

    function _permissionIdToMask(uint8 permissionId) private pure returns (uint256) {
        return 1 << (permissionId);
    }

    function _clearStagedPermissions() private {
        uint256 length = _stagedAddresses.length();
        for (uint256 i; i != length; ++i) {
            address target = _stagedAddresses.at(i);
            delete _stagedPermissionMasks[target];
            _stagedAddresses.remove(target);
        }
    }

    function _revokePermissionInstant(address from, uint8 permissionId) private {
        uint256 diff = _permissionIdToMask(permissionId);
        uint256 currentMask = _permissionMasks[from];
        _permissionMasks[from] = currentMask & (~diff);
        if (_permissionMasks[from] == 0) {
            delete _permissionMasks[from];
            _addresses.remove(from);
        }
    }

    function _revokePermissionsInstant(address from, uint8[] calldata permissionIds) internal {
        for (uint256 i; i != permissionIds.length; ++i) {
            _revokePermissionInstant(from, permissionIds[i]);
        }
        emit RevokedPermissionsInstant(msg.sender, from, permissionIds);
    }

    function _stageGrantPermission(address to, uint8 permissionId) private {
        require(!_isStagedToCommit(), "Already staged");
        uint256 diff = _permissionIdToMask(permissionId);
        if (!_stagedAddresses.contains(to)) {
            _stagedAddresses.add(to);
            _stagedPermissionMasks[to] = _permissionMasks[to];
        }
        uint256 currentMask = _stagedPermissionMasks[to];
        _stagedPermissionMasks[to] = currentMask | diff;
    }

    function _rollbackStagedPermissions() internal {
        require(_isStagedToCommit(), ExceptionsLibrary.INVALID_STATE);
        delete _stagedAddresses;
        _clearStagedPermissions();
        delete _stagedToCommitAt;
        emit RolledBackStagedPermissions(msg.sender);
    }

    function _stageGrantPermissions(
        address to,
        uint8[] calldata permissionIds,
        uint256 delay
    ) internal {
        require(!_isStagedToCommit(), ExceptionsLibrary.INVALID_STATE);
        for (uint256 i; i != permissionIds.length; ++i) {
            _stageGrantPermission(to, permissionIds[i]);
        }
        _stagedToCommitAt = block.timestamp + delay;
        emit StagedGrantPermissions(msg.sender, to, permissionIds, delay);
    }

    function _commitStagedPermissions() internal {
        require(_isStagedToCommit(), ExceptionsLibrary.INVALID_STATE);
        require(block.timestamp >= _stagedToCommitAt, ExceptionsLibrary.TIMESTAMP);
        uint256 length = _stagedAddresses.length();
        for (uint256 i; i != length; ++i) {
            address delayedAddress = _stagedAddresses.at(i);
            uint256 delayedPermissionMask = _stagedPermissionMasks[delayedAddress];
            if (delayedPermissionMask == 0) {
                delete _permissionMasks[delayedAddress];
                _addresses.remove(delayedAddress);
            } else {
                _permissionMasks[delayedAddress] = delayedPermissionMask;
                _addresses.add(delayedAddress);
            }
        }
        _clearStagedPermissions();
        delete _stagedToCommitAt;
    }

    event StagedGrantPermissions(address indexed sender, address indexed target, uint8[] permissionIds, uint256 delay);
    event RevokedPermissionsInstant(address indexed sender, address indexed target, uint8[] permissionIds);
    event RolledBackStagedPermissions(address indexed sender);
    event CommittedStagedPermissions(address indexed sender);
}
