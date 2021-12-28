//SPDX-Licence-Identifier: BSL-1.1
pragma solidity 0.8.9;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

contract AddressPermissionControl {
    using EnumerableSet for EnumerableSet.AddressSet;

    uint256 internal _commitTimestamp;
    address[] internal _stagedAddresses;
    uint256[] internal _stagedPermissionMasks;
    mapping(address => uint256) internal _permissionMasks;
    EnumerableSet.AddressSet internal _addresses;

    event PermissionsStaged(address indexed origin, address indexed target, uint256 permissionMask);
    event PermissionsCommitted(address indexed origin);
    event PermissionRevokoedInstant(address indexed origin, address indexed target, uint256 permissionMask);

    function addresses() public view returns (address[] memory) {
        return _addresses.values();
    }

    function length() public view returns (uint256) {
        return _addresses.length();
    }

    function addressAt(uint256 index) public view returns (address) {
        return _addresses.at(index);
    }

    function stagedAddresses() public view returns (address[] memory) {
        return _stagedAddresses;
    }

    function stagedPermissionMasks() public view returns (uint256[] memory) {
        return _stagedPermissionMasks;
    }

    function hasPermissionId(address token, uint8 permissionId) internal view returns (bool) {
        return _permissionMasks[token] & permissionIdToMask(permissionId) != 0;
    }

    function permissionMaskOf(address token) internal view returns (uint256) {
        return _permissionMasks[token];
    }

    function revokeInstantPermissionId(address from, uint8 permissionId) internal {
        uint256 permission = permissionIdToMask(permissionId);
        uint256 oldPermission = _permissionMasks[from];
        require(oldPermission & permission != 0);
        _permissionMasks[from] = oldPermission & (~ permission);
        if (_permissionMasks[from] == 0) {
            delete _permissionMasks[from];
            _addresses.remove(from);
        }
    }

    function stagePermissionMasks(
        address[] memory addrs,
        uint256[] memory permissions,
        uint256 delay
    ) internal {
        require(addrs.length == permissions.length);
        _commitTimestamp = block.timestamp + delay;
        _stagedAddresses = addrs;
        _stagedPermissionMasks = permissions;
    }

    function stagePermissionIds(
        address[] memory addrs,
        uint8[][] memory permissionIds,
        uint256 delay
    ) internal {
        uint256[] memory permissionMasks = new uint256[](addrs.length);
        for (uint256 i; i < addrs.length; ++i) {
            uint256 permissionMask = 0;
            for (uint256 j; j < permissionIds[i].length; ++j) {
                uint8 permissionId = permissionIds[i][j];
                permissionMask |= permissionIdToMask(permissionId);
            }
            permissionMasks[i] = permissionMask;
        }
        stagePermissionMasks(addrs, permissionMasks, delay);
    }

    function commitStagedPermissions() internal {
        require(_commitTimestamp != 0 && block.timestamp >= _commitTimestamp);
        uint256 len = _stagedAddresses.length;
        for (uint256 i; i != len; ++i) {
            uint256 stagedPermission = _stagedPermissionMasks[i];
            address stagedAddress = _stagedAddresses[i];
            if (stagedPermission != 0) {
                _permissionMasks[stagedAddress] = stagedPermission;
                _addresses.add(stagedAddress);
            } else {
                delete _permissionMasks[stagedAddress];
                _addresses.remove(stagedAddress);
            }
        }
        delete _commitTimestamp;
        delete _stagedAddresses;
        delete _stagedPermissionMasks;
    }

    function permissionIdToMask(uint8 permissionId) internal pure returns (uint256) {
        return 1 << permissionId;
    }
}
