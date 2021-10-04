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

    mapping(uint256 => VaultParams) private _vaultParams;
    mapping(uint256 => VaultParams) private _pendingVaultParams;
    mapping(uint256 => uint256) private _pendingVaultParamsTimestamps;

    mapping(uint256 => uint256[]) private _vaultLimits;
    mapping(uint256 => uint256[]) private _pendingVaultLimits;
    mapping(uint256 => uint256) private _pendingVaultLimitsTimestamps;

    constructor(
        string memory name,
        string memory symbol,
        VaultsParams memory params
    ) ERC721(name, symbol) {
        _vaultsParams = params;
    }

    /// -------------------  PUBLIC, VIEW  -------------------

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC721, IERC165, AccessControlEnumerable)
        returns (bool)
    {
        return interfaceId == type(IVaultsGovernance).interfaceId || super.supportsInterface(interfaceId);
    }

    function vaultLimits(uint256 nft) public view override returns (uint256[] memory) {
        return _vaultLimits[nft];
    }

    function pendingVaultLimits(uint256 nft) external view override returns (uint256[] memory) {
        return _pendingVaultLimits[nft];
    }

    function pendingVaultLimitsTimestamp(uint256 nft) external view override returns (uint256) {
        return _pendingVaultLimitsTimestamps[nft];
    }

    function vaultParams(uint256 nft) public view override returns (VaultParams memory) {
        return _vaultParams[nft];
    }

    function pendingVaultParams(uint256 nft) external view override returns (VaultParams memory) {
        return _pendingVaultParams[nft];
    }

    function pendingVaultParamsTimestamp(uint256 nft) external view override returns (uint256) {
        return _pendingVaultParamsTimestamps[nft];
    }

    function vaultsParams() public view override returns (VaultsParams memory) {
        return _vaultsParams;
    }

    function pendingVaultsParams() external view override returns (VaultsParams memory) {
        return _pendingVaultsParams;
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
        _pendingVaultParamsTimestamps[nft] = block.timestamp + _vaultsParams.protocolGovernance.governanceDelay();
        emit SetPendingVaultParams(nft, _pendingVaultParamsTimestamps[nft], newVaultParams);
    }

    function commitVaultParams(uint256 nft) external {
        require(_isApprovedOrOwner(_msgSender(), nft) || _isGovernanceOrDelegate(), "IO"); // Also checks that the token exists
        require(
            (block.timestamp > _pendingVaultParamsTimestamps[nft]) && (_pendingVaultParamsTimestamps[nft] > 0),
            "TS"
        );
        _vaultParams[nft] = _pendingVaultParams[nft];
        delete _pendingVaultParams[nft];
        delete _pendingVaultParamsTimestamps[nft];
        emit CommitVaultParams(nft, _vaultParams[nft]);
    }

    function setPendingVaultLimits(uint256 nft, uint256[] memory newLimits) external {
        require(_isApprovedOrOwner(_msgSender(), nft) || _isGovernanceOrDelegate(), "IO"); // Also checks that the token exists
        require(_vaultLimits[nft].length == newLimits.length, "LL");
        _vaultLimits[nft] = newLimits;
        _pendingVaultLimitsTimestamps[nft] = block.timestamp + _vaultsParams.protocolGovernance.governanceDelay();
        emit SetPendingVaultLimits(nft, _pendingVaultLimitsTimestamps[nft], newLimits);
    }

    function commitVaultLimits(uint256 nft) external {
        require(_isApprovedOrOwner(_msgSender(), nft) || _isGovernanceOrDelegate(), "IO"); // Also checks that the token exists
        require(
            (block.timestamp > _pendingVaultLimitsTimestamps[nft]) && (_pendingVaultLimitsTimestamps[nft] > 0),
            "TS"
        );
        _vaultLimits[nft] = _pendingVaultLimits[nft];
        delete _pendingVaultLimits[nft];
        delete _pendingVaultLimitsTimestamps[nft];
        emit CommitVaultLimits(nft, _vaultLimits[nft]);
    }

    /// -------------------  INTERNAL, MUTATING  -------------------

    function _setVaultLimits(uint256 nft, uint256[] memory limits) internal {
        _vaultLimits[nft] = limits;
    }

    function _setVaultParams(uint256 nft, VaultParams memory params) internal {
        _vaultParams[nft] = params;
    }
}
