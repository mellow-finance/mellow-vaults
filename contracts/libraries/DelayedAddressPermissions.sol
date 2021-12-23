// SPDX-License-Identifier: BSL-1.1
pragma solidity 0.8.9;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

library DelayedAddressPermissions {
    using EnumerableSet for EnumerableSet.AddressSet;

    struct BitMap {
        uint256 _timestamp;
        address[] _stagedAddresses;
        uint64[] _stagedPermissions;
        mapping(address => uint64) _permissions;
        EnumerableSet.AddressSet _addresses;
    }

    function addresses(BitMap storage state) public view returns (address[] memory) {
        return state._addresses.values();
    }

    function length(BitMap storage state) public view returns (uint256) {
        return state._addresses.length();
    }

    function at(BitMap storage state, uint256 index) public view returns (address) {
        return state._addresses.at(index);
    }

    function hasPermission(
        BitMap storage state,
        address token,
        uint64 permission
    ) internal view returns (bool) {
        // ensure permission has only exactly one bit set
        require(permission != 0 && (permission & (permission - 1)) != 0);
        return state._permissions[token] & permission != 0;
    }

    function hasExactPermissions(
        BitMap storage state,
        address token,
        uint64 permissions
    ) internal view returns (bool) {
        return state._permissions[token] == permissions;
    }

    function hasAllPermissions(
        BitMap storage state,
        address token,
        uint64 permissions
    ) internal view returns (bool) {
        return (state._permissions[token] & permissions) == permissions;
    }

    function hasAnyPermission(
        BitMap storage state,
        address token,
        uint64 permissions
    ) internal view returns (bool) {
        return state._permissions[token] & permissions != 0;
    }

    function permissionsOf(
        BitMap storage state,
        address token
    ) internal view returns (uint64) {
        return state._permissions[token];
    }

    function stage(
        BitMap storage state,
        address[] calldata addrs,
        uint64[] calldata permissions,
        uint256 delay
    ) internal {
        require(addrs.length == permissions.length);
        state._timestamp = block.timestamp + delay;
        state._stagedAddresses = addrs;
        state._stagedPermissions = permissions;
    }

    function commit(BitMap storage state) internal {
        require(block.timestamp >= state._timestamp);
        uint256 len = state._stagedAddresses.length;
        for (uint256 i; i != len;) {
            uint64 stagedPermission = state._stagedPermissions[i];
            address stagedAddress = state._stagedAddresses[i];
            if (stagedPermission != 0) {
                state._permissions[stagedAddress] = stagedPermission;
                state._addresses.add(stagedAddress);
            } else {
                delete state._permissions[stagedAddress];
                state._addresses.remove(stagedAddress);
            }
            unchecked {
                ++i;
            }
        }
        delete state._timestamp;
        delete state._stagedAddresses;
        delete state._stagedPermissions;
    }
}
