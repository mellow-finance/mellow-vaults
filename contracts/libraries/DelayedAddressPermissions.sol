// SPDX-License-Identifier: BSL-1.1
pragma solidity 0.8.9;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

library DelayedAddressPermissions {
    using EnumerableSet for EnumerableSet.AddressSet;

    struct BitMap {
        uint256 _timestamp;
        address[] _stagedAddresses;
        uint64[] _stagedPermissionMasks;
        mapping(address => uint64) _permissions;
        EnumerableSet.AddressSet _addresses;
    }

    function addresses(BitMap storage state) internal view returns (address[] memory) {
        return state._addresses.values();
    }

    function length(BitMap storage state) internal view returns (uint256) {
        return state._addresses.length();
    }

    function addressAt(BitMap storage state, uint256 index) internal view returns (address) {
        return state._addresses.at(index);
    }

    function stagedAddresses(BitMap storage state) internal view returns (address[] memory) {
        return state._stagedAddresses;
    }

    function stagedPermissionMasks(BitMap storage state) internal view returns (uint64[] memory) {
        return state._stagedPermissionMasks;
    }

    function hasPermissionId(
        BitMap storage state,
        address token,
        uint8 permissionId
    ) internal view returns (bool) {
        return state._permissions[token] & permissionIdToMask(permissionId) != 0;
    }

    function permissionMaskOf(BitMap storage state, address token) internal view returns (uint64) {
        return state._permissions[token];
    }

    function revokeInstantPermissionId(
        BitMap storage state,
        address from,
        uint8 permissionId
    ) internal {
        uint64 permission = uint64(1) << permissionId;
        uint64 oldPermission = state._permissions[from];
        require(oldPermission & permission != 0);
        state._permissions[from] = oldPermission & (~permission);
        if (state._permissions[from] == 0) {
            delete state._permissions[from];
            state._addresses.remove(from);
        }
    }

    function stagePermissionMasks(
        BitMap storage state,
        address[] memory addrs,
        uint64[] memory permissions,
        uint256 delay
    ) internal {
        require(addrs.length == permissions.length);
        state._timestamp = block.timestamp + delay;
        state._stagedAddresses = addrs;
        state._stagedPermissionMasks = permissions;
    }

    function stagePermissionIds(
        BitMap storage state,
        address[] memory addrs,
        uint8[][] memory permissionIds,
        uint256 delay
    ) internal {
        uint64[] memory permissionMasks = new uint64[](addrs.length);
        for (uint256 i; i < addrs.length; ++i) {
            uint64 permissionMask = 0;
            for (uint256 j; j < permissionIds[i].length; ++j) {
                uint8 permissionId = permissionIds[i][j];
                permissionMask |= permissionIdToMask(permissionId);
            }
            permissionMasks[i] = permissionMask;
        }
        stagePermissionMasks(state, addrs, permissionMasks, delay);
    }

    function commitStagedPermissions(BitMap storage state) internal {
        require(block.timestamp >= state._timestamp);
        uint256 len = state._stagedAddresses.length;
        for (uint256 i; i != len; ++i) {
            uint64 stagedPermission = state._stagedPermissionMasks[i];
            address stagedAddress = state._stagedAddresses[i];
            if (stagedPermission != 0) {
                state._permissions[stagedAddress] = stagedPermission;
                state._addresses.add(stagedAddress);
            } else {
                delete state._permissions[stagedAddress];
                state._addresses.remove(stagedAddress);
            }
        }
        delete state._timestamp;
        delete state._stagedAddresses;
        delete state._stagedPermissionMasks;
    }

    function permissionIdToMask(uint8 permissionId) internal pure returns (uint64) {
        return uint64(1) << permissionId;
    }
}
