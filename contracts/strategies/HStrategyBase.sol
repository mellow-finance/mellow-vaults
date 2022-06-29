// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.9;

import "../interfaces/vaults/IUniV3Vault.sol";
import "../interfaces/vaults/IERC20Vault.sol";
import "../interfaces/vaults/IVault.sol";
import "../interfaces/oracles/IOracle.sol";


abstract contract HStrategyBase {
    public immutable IUniV3Vault uniV3;
    public immutable IERC20Vault erc20;
    public immutable IVault farmVault;
    public immutable IOracle oracle;
    public immutable uint256 oracleMask;

    struct VaultStats {
        uint256 amount0;
        uint256 amount1;
    }

    struct StrategyVaultStats {
        VaultStats erc20Stats;
        VaultStats uniV3Stats;
        VaultStats farmStats;
    }

    function rebalance() external {
        if (!_checkPrice()) {
            return;
        }
        address[] memory tokens = erc20.vaultTokens();
        uint256 priceX96 = _priceX96();
        _burnPosition(tokens);
        StrategyVaultStats startTvl = _calculateTvl();
        StrategyVaultStats expectedTvl = _calculateExpected(startTvl);
        StrategyVaultStats missingTokens = _calculateMissingTokens(startTvl, expectedTvl);
        _biRebalance(startTvl, missingTokens);
        _mintPosition();
    }

    function _burnPosition(address[] memory tokens) internal {
        uint256[] toPull = new uint256[](2);
        toPull[0] = type(uint256).max;
        toPull[1] = type(uint256).max;
        uniV3.collectEarnings();
        uniV3.pull(address(erc20), tokens, toPull);
    }

    function _tvl(IVault vault) internal pure returns (uint256 amount0, uint256 amount1) {
        ([]uint256 minTvl, []uint256 maxTvl) = vault.tvl();
        return (minTvl[0] + maxTvl[0]) / 2, (minTvl[1] + maxTvl[1]) / 2;
    }

    function _calculateTvl() internal view returns (StrategyVaultStats tvl) {
        (tvl.erc20Stats.amount0, tvl.erc20Stats.amount1) = _tvl(erc20);
        (tvl.uniV3Stats.amount0, tvl.uniV3Stats.amount1) = _tvl(uniV3);
        (tvl.farmStats.amount0, tvl.farmStats.amount1) = _tvl(farmVault);
    } 

    function _capitalToken0(IVault vault) internal pure returns (uint256 amount);

    function _checkPrice() internal view returns (bool needRebalance);

    function _priceX96() internal view returns (uint256 priceX96);
}
