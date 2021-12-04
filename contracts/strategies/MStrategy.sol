// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.9;

import "../interfaces/IVault.sol";
import "../interfaces/external/univ3/IUniswapV3Pool.sol";
import "../DefaultAccessControl.sol";

contract MStrategy is DefaultAccessControl {
    struct Params {
        uint256 oraclePriceTimespan;
        uint256 oraclePriceMinTimespan;
        uint256 oracleLiquidityTimespan;
        uint256 oracleLiquidityMinTimespan;
        uint256 liquidToFixedRatioX96;
        uint256 pMinX96;
        uint256 pMaxX96;
    }

    struct ImmutableParams {
        address token0;
        address token1;
        IUniswapV3Pool uniV3Pool;
        IVault gwVault;
        IVault erc20Vault;
        IVault moneyVault;
    }

    Params[] public vaultParams;
    ImmutableParams[] public vaultImmutableParams;
    mapping(address => mapping(address => uint256)) public vaultIndex;
    mapping(uint256 => bool) public disabled;

    constructor(address owner) DefaultAccessControl(owner) {}

    mapping(address => mapping(address => uint256)) public paramsIndex;

    function addVault(ImmutableParams memory immutableParams_, Params memory params_) external {
        require(isAdmin(msg.sender), "ADM");
        address token0 = immutableParams_.token0;
        address token1 = immutableParams_.token1;
        require(immutableParams_.uniV3Pool.token0() == token0, "T0");
        require(immutableParams_.uniV3Pool.token1() == token1, "T1");
        IVault[3] memory vaults = [immutableParams_.erc20Vault, immutableParams_.gwVault, immutableParams_.moneyVault];
        for (uint256 i = 0; i < vaults.length; i++) {
            IVault vault = vaults[i];
            address[] memory tokens = vault.vaultTokens();
            require(tokens[0] == token0, "VT0");
            require(tokens[1] == token1, "VT1");
        }
        uint256 num = vaultParams.length;
        vaultParams.push(params_);
        vaultImmutableParams.push(immutableParams_);
        paramsIndex[token0][token1] = num;
        paramsIndex[token1][token0] = num;
        emit VaultAdded(tx.origin, msg.sender, num, immutableParams_, params_);
    }

    function disableVault(uint256 num, bool disabled_) external {
        require(isAdmin(msg.sender), "ADM");
        disabled[num] = disabled_;
        emit VaultDisabled(tx.origin, msg.sender, num, disabled_);
    }

    event VaultAdded(
        address indexed origin,
        address indexed sender,
        uint256 num,
        ImmutableParams immutableParams,
        Params params
    );

    event VaultDisabled(address indexed origin, address indexed sender, uint256 num, bool disabled);
}
