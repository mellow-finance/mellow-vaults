// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/vaults/IERC20Vault.sol";
import "../interfaces/vaults/IVoltzVault.sol";
import "../utils/DefaultAccessControl.sol";
import "../interfaces/utils/ILpCallback.sol";
import "../libraries/external/FixedPoint96.sol";

contract LPOptimiserStrategy is DefaultAccessControl, ILpCallback {
    using SafeERC20 for IERC20;
    using PRBMathUD60x18 for uint256;

    // VAULT PARAMETERS
    struct VaultParams {
        int256 sigmaWad; // standard deviation parameter in wad 10^18
        int256 maxPossibleLowerBoundWad; // Maximum Possible Fixed Rate Lower bounds when initiating a rebalance
        uint256 proximityWad; // closeness parameter in wad 10^18
        uint256 weight; // weight parameter that decides how many funds are going to this vault
    }

    // IMMUTABLES
    address[] public _tokens;
    IERC20Vault public immutable _erc20Vault;

    // INTERNAL STATE
    IVoltzVault[] internal _vaults;
    VaultParams[] internal _vaultParams;
    uint256 _totalWeight; // sum of all vault weights

    // CONSTANTS
    int256 internal constant MINIMUM_FIXED_RATE = 1e16;
    uint256 internal constant LOG_BASE = 1000100000000000000;

    // GETTERS AND SETTERS

    /// @notice Get the addresses of all vaults
    function getVaults() public view returns (IVoltzVault[] memory) {
        return _vaults;
    }

    /// @notice Get the parameters of a vault 
    /// @param index The index of the vault in _vaults
    function getVaultParams(uint256 index) public view returns (VaultParams memory) {
        return _vaultParams[index];
    }

    /// @notice Set the parameters of a vault
    function setVaultParams(uint256 index, VaultParams memory vaultParams_) external {
        _requireAdmin();
        require(index < _vaultParams.length, ExceptionsLibrary.INVALID_STATE);

        _totalWeight -= _vaultParams[index].weight;
        _vaultParams[index] = vaultParams_;
        _totalWeight += _vaultParams[index].weight;
    }

    // EVENTS
    event StrategyDeployment(IERC20Vault erc20vault, IVoltzVault[] vaults, VaultParams[] vaultParams, address admin);

    event RebalancedTicks(IVoltzVault voltzVault, int24 tickLower, int24 tickUpper);

    /// @notice Constructor for a new contract
    /// @param erc20vault_ Reference to ERC20 Vault
    /// @param vaults_ Reference to Voltz Vaults
    /// @param vaultParams_ Rebalancing parameters of the voltz vaults
    /// @param admin_ Admin of the strategy
    constructor(
        IERC20Vault erc20vault_,
        IVoltzVault[] memory vaults_,
        VaultParams[] memory vaultParams_,
        address admin_
    ) DefaultAccessControl(admin_) {
        _erc20Vault = erc20vault_;

        _tokens = _erc20Vault.vaultTokens();
        require(_tokens.length == 1, ExceptionsLibrary.INVALID_TOKEN);
    
        require(vaults_.length == vaultParams_.length, ExceptionsLibrary.INVALID_LENGTH);
        for (uint256 i = 0; i < vaults_.length; i += 1) {
            _addVault(vaults_[i], vaultParams_[i]);
        }

        emit StrategyDeployment(erc20vault_, vaults_, vaultParams_, admin_);
    }

    /// @notice Attach another voltz vault to the strategy
    /// @param vault_ The address of the vault
    /// @param vaultParams_ The paremeters of the new vault
    function addVault(IVoltzVault vault_, VaultParams memory vaultParams_) external {
        _requireAdmin();
        _addVault(vault_, vaultParams_);
    }

    function _addVault(IVoltzVault vault_, VaultParams memory vaultParams_) internal {
        // 0. Set the local variables
        address[] memory tokens = vault_.vaultTokens();

        // 1. Check if the tokens correspond
        require(tokens.length == 1, ExceptionsLibrary.INVALID_TOKEN);
        require(tokens[0] == _tokens[0], ExceptionsLibrary.INVALID_TOKEN);

        // 2. Add the vault 
        _vaults.push(vault_);
        _vaultParams.push(vaultParams_);
        _totalWeight += vaultParams_.weight;
    }

    /// @notice Get the current tick and position ticks and decide whether to rebalance
    /// @param currentFixedRateWad currentFixedRate which is passed in from a 7-day rolling avg. historical fixed rate
    /// @return bool True if rebalanceTicks should be called, false otherwise
    function rebalanceCheck(uint256 index, uint256 currentFixedRateWad) public view returns (bool) {
        // 0. Set the local variables
        VaultParams memory vaultParams = _vaultParams[index];
        IVoltzVault vault = _vaults[index];

        // 1. Get current position, lower, and upper ticks form VoltzVault.sol
        IVoltzVault.TickRange memory currentPosition = vault.currentPosition();

        // 2. Convert the ticks into fixed rate
        uint256 lowFixedRateWad = convertTickToFixedRate(currentPosition.tickUpper);
        uint256 highFixedRateWad = convertTickToFixedRate(currentPosition.tickLower);

        if (
            lowFixedRateWad + vaultParams.proximityWad <= currentFixedRateWad &&
            currentFixedRateWad + vaultParams.proximityWad <= highFixedRateWad
        ) {
            // 3.1. If current fixed rate is within bounds, return false (don't rebalance)
            return false;
        } else {
            // 3.2. If current fixed rate is outside bounds, return true (do rebalance)
            return true;
        }
    }

    /// @notice Get the nearest tick multiple given a tick and tick spacing
    /// @param newTick The tick to be rounded to the closest multiple of tickSpacing
    /// @param tickSpacing The tick spacing of the vamm being used for this strategy
    /// @return int24 The nearest tick multiple for newTick
    function nearestTickMultiple(int24 newTick, int24 tickSpacing) public pure returns (int24) {
        return
            (newTick /
                tickSpacing +
                ((((newTick % tickSpacing) + tickSpacing) % tickSpacing) >= tickSpacing / 2 ? int24(1) : int24(0))) *
            tickSpacing;
    }

    /// @notice Convert a fixed rate to a tick in wad
    /// @param fixedRateWad The fixed rate to be converted to a tick in wad
    /// @return int256 The tick in wad
    function convertFixedRateToTick(int256 fixedRateWad) public pure returns (int256) {
        return -PRBMathSD59x18.div(PRBMathSD59x18.log2(int256(fixedRateWad)), PRBMathSD59x18.log2(int256(LOG_BASE)));
    }

    function convertTickToFixedRate(int24 tick) public pure returns (uint256) {
        // 1. Convert the tick into X96 sqrt price (scaled by 2^96)
        uint160 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(tick);

        // 2. Convert the X96 sqrt price (scaled by 2^96) to wad 1/sqrt price (scaled by 10^18)
        uint256 sqrtRatioWad = FullMath.mulDiv(1e18, FixedPoint96.Q96, sqrtPriceX96);

        // 3. Convert 1/sqrt price into fixed rate (1/price) 
        uint256 fixedRateWad = sqrtRatioWad.mul(sqrtRatioWad);

        // 4. Return the fixed rate
        return fixedRateWad;
    }

    /// @notice Set new optimal tick range based on current twap tick given that we are using the offchain moving average of the fixed rate in the current iteration
    /// @param currentFixedRateWad currentFixedRate which is passed in from a 7-day rolling avg. historical fixed rate.
    /// @return newTickLower The new lower tick for the rebalanced position
    /// @return newTickUpper The new upper tick for the rebalanced position
    function rebalanceTicks(uint256 index, uint256 currentFixedRateWad) public returns (int24 newTickLower, int24 newTickUpper) {
        _requireAtLeastOperator();
        require(rebalanceCheck(index, currentFixedRateWad), ExceptionsLibrary.REBALANCE_NOT_NEEDED);

        VaultParams memory vaultParams = _vaultParams[index];
        IVoltzVault vault = _vaults[index];

        // 0. Get tickspacing from vamm
        int24 tickSpacing = vault.vamm().tickSpacing();

        // 1. Get the new tick lower
        int256 deltaWad = int256(currentFixedRateWad) - vaultParams.sigmaWad;
        int256 newFixedLowerWad;
        if (deltaWad > MINIMUM_FIXED_RATE) {
            // delta is greater than MINIMUM_FIXED_RATE (0.01) => choose delta
            if (deltaWad < vaultParams.maxPossibleLowerBoundWad) {
                newFixedLowerWad = deltaWad;
            } else {
                newFixedLowerWad = vaultParams.maxPossibleLowerBoundWad;
            }
        } else {
            // delta is less than or equal to MINIMUM_FIXED_RATE (0.01) => choose MINIMUM_FIXED_RATE (0.01)
            newFixedLowerWad = MINIMUM_FIXED_RATE;
        }
        // 2. Get the new tick upper
        int256 newFixedUpperWad = newFixedLowerWad + 2 * vaultParams.sigmaWad;

        // 3. Convert new fixed lower rate back to tick
        int256 newTickLowerWad = convertFixedRateToTick(newFixedUpperWad);

        // 4. Convert new fixed upper rate back to tick
        int256 newTickUpperWad = convertFixedRateToTick(newFixedLowerWad);

        // 5. Scale ticks from wad
        int256 newTickLowerExact = newTickLowerWad / 1e18;
        int256 newTickUpperExact = newTickUpperWad / 1e18;

        // 6. The underlying Voltz VAMM accepts only ticks multiple of tickSpacing
        // Hence, we get the nearest usable tick
        newTickLower = nearestTickMultiple(int24(newTickLowerExact), tickSpacing);
        newTickUpper = nearestTickMultiple(int24(newTickUpperExact), tickSpacing);

        // Call to VoltzVault contract to update the position lower and upper ticks
        vault.rebalance(IVoltzVault.TickRange(newTickLower, newTickUpper));

        emit RebalancedTicks(vault, newTickLower, newTickUpper);
        return (newTickLower, newTickUpper);
    }

    function _pushFunds() internal {
        // 0. Set the local variables
        address[] memory tokens = _tokens;
        uint256 balance = IERC20(tokens[0]).balanceOf(address(_erc20Vault));

        // 1. Distribute the funds
        for (uint256 i = 0; i < _vaults.length; i++) {
            uint256[] memory vaultShare = new uint256[](1);

            if (_vaultParams[i].weight == 0) {
                continue;
            }

            // The share of i-th is vaultParams[i].weight / sum(vaultParams.weight)
            vaultShare[0] = FullMath.mulDiv(balance, _vaultParams[i].weight, _totalWeight); 

            // Pull funds from the erc20 vault and push the share into the i-th voltz vault
            _erc20Vault.pull(address(_vaults[i]), tokens, vaultShare, "");
        }
    }

    /// @notice Callback function called after for ERC20RootVault::deposit
    function depositCallback() external override {
        _pushFunds();
    }

    /// @notice Callback function called after for ERC20RootVault::withdraw
    function withdrawCallback() external override {
        // Do nothing on withdraw
    }
}
