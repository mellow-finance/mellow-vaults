// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.9;

import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/vaults/IERC20Vault.sol";
import "../interfaces/vaults/IVoltzVault.sol";
import "../utils/DefaultAccessControlLateInit.sol";
import "../interfaces/utils/ILpCallback.sol";
import "../libraries/external/FixedPoint96.sol";

contract LPOptimiserStrategy is DefaultAccessControlLateInit, ILpCallback {
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
    address[] public tokens;
    IERC20Vault public erc20Vault;

    // INTERNAL STATE
    IVoltzVault[] internal _vaults;
    VaultParams[] internal _vaultParams;
    uint256 private _totalWeight; // sum of all vault weights

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
    /// @param index The index of the vault in _vaults
    /// @param vaultParams_ The new parameters of the vault
    function setVaultParams(uint256 index, VaultParams memory vaultParams_) external {
        _requireAdmin();
        require(index < _vaults.length, ExceptionsLibrary.INVALID_STATE);

        uint256 previousWeight = _vaultParams[index].weight;
        _vaultParams[index] = vaultParams_;
        _totalWeight = (_totalWeight + vaultParams_.weight) - previousWeight;
    }

    constructor(address admin_) {
        DefaultAccessControlLateInit.init(admin_);
    }

    /// @notice Constructor for a new contract
    /// @param erc20vault_ Reference to ERC20 Vault
    /// @param vaults_ Reference to Voltz Vaults
    /// @param vaultParams_ Rebalancing parameters of the voltz vaults
    /// @param admin_ Admin of the strategy
    function initialize(
        IERC20Vault erc20vault_,
        IVoltzVault[] memory vaults_,
        VaultParams[] memory vaultParams_,
        address admin_
    ) public {
        erc20Vault = erc20vault_;

        tokens = erc20vault_.vaultTokens();
        require(tokens.length == 1, ExceptionsLibrary.INVALID_TOKEN);

        require(vaults_.length == vaultParams_.length, ExceptionsLibrary.INVALID_LENGTH);
        for (uint256 i = 0; i < vaults_.length; i += 1) {
            _addVault(vaults_[i], vaultParams_[i]);
        }

        DefaultAccessControlLateInit.init(admin_);

        emit StrategyDeployment(erc20vault_, vaults_, vaultParams_, admin_);
    }

    function createStrategy(
        IERC20Vault erc20vault_,
        IVoltzVault[] memory vaults_,
        VaultParams[] memory vaultParams_,
        address admin_
    ) external returns (LPOptimiserStrategy strategy) {
        strategy = LPOptimiserStrategy(Clones.clone(address(this)));
        strategy.initialize(erc20vault_, vaults_, vaultParams_, admin_);
    }

    function _addVault(IVoltzVault vault_, VaultParams memory vaultParams_) internal {
        // 0. Set the local variables
        address[] memory vaultTokens = vault_.vaultTokens();

        // 1. Check if the tokens correspond
        require(vaultTokens.length == 1, ExceptionsLibrary.INVALID_TOKEN);
        require(vaultTokens[0] == tokens[0], ExceptionsLibrary.INVALID_TOKEN);

        // 2. Add the vault
        _vaults.push(vault_);
        _vaultParams.push(vaultParams_);
        _totalWeight += vaultParams_.weight;
    }

    /// @notice Get the current tick and position ticks and decide whether to rebalance
    /// @param index The index of the vault in _vaults
    /// @param currentFixedRateWad currentFixedRate which is passed in from a 7-day rolling avg. historical fixed rate
    /// @return bool True if rebalanceTicks should be called, false otherwise
    function rebalanceCheck(uint256 index, uint256 currentFixedRateWad) public view returns (bool) {
        require(index < _vaults.length, ExceptionsLibrary.INVALID_STATE);

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

    /// @notice Get the fixed rate corresponding to tick
    /// @param tick The tick to be converted into fixed rate
    /// @return uint256 The fixed rate in wad (1.0001 ^ -tick)
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
    /// @param index The index of the vault in _vaults
    /// @param currentFixedRateWad currentFixedRate which is passed in from a 7-day rolling avg. historical fixed rate.
    /// @return newTickLower The new lower tick for the rebalanced position
    /// @return newTickUpper The new upper tick for the rebalanced position
    function rebalanceTicks(uint256 index, uint256 currentFixedRateWad)
        public
        returns (int24 newTickLower, int24 newTickUpper)
    {
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

    /// @notice This function grabs all funds from the buffer vault
    /// and distributed them to the voltz vaults according to their weights
    function _distributeTokens() internal {
        // 0. Set the local variables
        IERC20Vault localErc20Vault = erc20Vault;
        address[] memory localTokens = tokens;
        VaultParams[] memory vaultParams = _vaultParams;
        uint256 totalWeight = _totalWeight;

        uint256[] memory balances = new uint256[](1);
        balances[0] = IERC20(localTokens[0]).balanceOf(address(localErc20Vault));

        // 1. Distribute the funds
        uint256[] memory vaultShare = new uint256[](1);

        for (uint256 i = 0; i < _vaults.length; i++) {
            uint256 vaultWeight = vaultParams[i].weight;

            if (vaultWeight == 0) {
                continue;
            }

            // The share of i-th is vaultWeight / sum(vaultParams.weight)
            vaultShare[0] = FullMath.mulDiv(balances[0], vaultWeight, totalWeight);

            // Pull funds from the erc20 vault and push the share into the i-th voltz vault
            localErc20Vault.pull(address(_vaults[i]), localTokens, vaultShare, "");
        }
    }

    function transferPermissions(address newStrategy) external {
        _requireAdmin();
        IVaultRegistry vaultRegistry = erc20Vault.vaultGovernance().internalParams().registry;
        IVoltzVault[] memory voltzVaults = _vaults;
        for (uint256 i = 0; i < voltzVaults.length; ++i) {
            vaultRegistry.approve(newStrategy, voltzVaults[i].nft());
        }
        vaultRegistry.approve(newStrategy, erc20Vault.nft());
    }

    /// @notice Callback function called after for ERC20RootVault::deposit
    function depositCallback() external override {
        _distributeTokens();
    }

    /// @notice Callback function called after for ERC20RootVault::withdraw
    function withdrawCallback() external override {
        // Do nothing on withdraw
    }

    // EVENTS
    event StrategyDeployment(IERC20Vault erc20vault, IVoltzVault[] vaults, VaultParams[] vaultParams, address admin);

    event RebalancedTicks(IVoltzVault voltzVault, int24 tickLower, int24 tickUpper);
}
