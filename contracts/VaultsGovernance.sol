// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "./access/GovernanceAccessControl.sol";
import "./interfaces/IProtocolGovernance.sol";
import "./interfaces/IVaultsGovernance.sol";

contract VaultsGovernance is IVaultsGovernance, ERC721, GovernanceAccessControl {
    VaultsParams private _vaultsParams;
    VaultsParams private _pendingVaultsParams;
    uint256 public pendingVaultsParamsTimestamp;

    mapping(uint256 => VaultParams) public _vaultParams;
    mapping(uint256 => VaultParams) public _pendingVaultParams;
    mapping(uint256 => uint256) public pendingVaultParamsTimestamps;

    mapping(uint256 => uint256[]) private _tokenLimits;
    mapping(uint256 => uint256[]) private _pendingTokenLimits;
    mapping(uint256 => uint256) public pendingTokenLimitsTimestamps;

    constructor(VaultsParams memory vaultsParams) {
        _vaultsParams = _vaultsParams;
    }

    /// -------------------  PUBLIC, VIEW  -------------------

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC721, AccessControlEnumerable)
        returns (bool)
    {
        return interfaceId == type(IVaultsGovernance).interfaceId || super.supportsInterface(interfaceId);
    }

    function tokenLimits(uint256 nft) external returns (uint256[] memory) {
        return _tokenLimits[nft];
    }

    function pendingTokenLimits(uint256 nft) external returns (uint256[] memory) {
        return _pendingTokenLimits[nft];
    }

    /// -------------------  PUBLIC, MUTATING, GOVERNANCE, DELAY  -------------------

    function setPendingVaultsParams(VaultsParams memory newVaultsParams) external {
        require(_isGovernanceOrDelegate(), "PGD");
        _pendingVaultsParams = newVaultsParams;
        pendingVaultsParamsTimestamp = block.timestamp + _vaultsParams.protocolGovernance.governanceDelay();
        emit SetPendingVaultsParams(pendingVaultsParamsTimestamp, newVaultsParams);
    }

    function commitVaultsParams() external {
        require(_isGovernanceOrDelegate(), "PGD");
        require((block.timestamp > pendingVaultsParamsTimestamp) && (pendingVaultsParamsTimestamp > 0), "TS");
        _vaultsParams = _pendingVaultsParams;
        delete _pendingVaultsParams;
        delete pendingVaultsParamsTimestamp;
        emit CommitVaultsParams(_vaultsParams);
    }

    function setPendingVaultParams(uint256 nft, VaultParams memory newVaultParams) external {
        require(_isApprovedOrOwner(_msgSender(), nft) || _isGovernanceOrDelegate(), "IO"); // Also checks that the token exists
        _pendingVaultParams[nft] = newVaultParams;
        pendingVaultParamsTimestamps[nft] = block.timestamp + _vaultsParams.protocolGovernance.governanceDelay();
        emit SetPendingVaultParams(nft, pendingVaultParamsTimestamps[nft], newVaultParams);
    }

    function commitVaultParams(uint256 nft) external {
        require(_isApprovedOrOwner(_msgSender(), nft) || _isGovernanceOrDelegate(), "IO"); // Also checks that the token exists
        require((block.timestamp > pendingVaultParamsTimestamps[nft]) && (pendingVaultParamsTimestamps[nft] > 0), "TS");
        _vaultParams[nft] = _pendingVaultParams[nft];
        delete _pendingVaultParams[nft];
        delete pendingVaultParamsTimestamps[nft];
        emit CommitVaultParams(nft, _vaultParams[nft]);
    }

    function setPendingVaultLimits(uint256 nft, uint256[] memory newLimits) external {
        require(_isApprovedOrOwner(_msgSender(), nft) || _isGovernanceOrDelegate(), "IO"); // Also checks that the token exists
        require(_tokenLimits[nft].length == newLimits.length, "LL");
        _tokenLimits[nft] = newLimits;
        pendingTokenLimitsTimestamps[nft] = block.timestamp + _vaultsParams.protocolGovernance.governanceDelay();
        emit SetPendingTokenLimits(nft, pendingTokenLimitsTimestamps[nft], newLimits);
    }

    function commitTokenLimits(uint256 nft) external {
        require(_isApprovedOrOwner(_msgSender(), nft) || _isGovernanceOrDelegate(), "IO"); // Also checks that the token exists
        require((block.timestamp > pendingTokenLimitsTimestamps[nft]) && (pendingTokenLimitsTimestamps[nft] > 0), "TS");
        _tokenLimits[nft] = _pendingTokenLimits[nft];
        delete _pendingTokenLimits[nft];
        delete pendingTokenLimitsTimestamps[nft];
        emit CommitTokenLimits(nft, _tokenLimits[nft]);
    }
}
