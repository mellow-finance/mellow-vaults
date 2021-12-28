// SPDX-License-Identifier: BSL-1.1
pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./libraries/external/FullMath.sol";
import "./libraries/ExceptionsLibrary.sol";
import "./interfaces/IERC20RootVaultGovernance.sol";
import "./AggregateVault.sol";

/// @notice Contract that mints and burns LP tokens in exchange for ERC20 liquidity.
contract ERC20RootVault is ERC20, ReentrancyGuard, AggregateVault {
    using SafeERC20 for IERC20;
    uint256[] private _lpPriceHighWaterMarks;
    uint256 public lastFeeCharge;

    /// @notice Creates a new contract.
    /// @dev All subvault nfts must be owned by this vault before.
    /// @param vaultGovernance_ Reference to VaultGovernance for this vault
    /// @param vaultTokens_ ERC20 tokens under Vault management
    /// @param nft_ NFT of the vault in the VaultRegistry
    /// @param name_ Name of the ERC20 token
    /// @param symbol_ Symbol of the ERC20 token
    constructor(
        IVaultGovernance vaultGovernance_,
        address[] memory vaultTokens_,
        uint256 nft_,
        uint256[] memory subvaultNfts_,
        string memory name_,
        string memory symbol_
    ) AggregateVault(vaultGovernance_, vaultTokens_, nft_, subvaultNfts_) ERC20(name_, symbol_) {
    }

    function deposit(uint256[] calldata tokenAmounts, uint256 minLpTokens) external nonReentrant {
        (uint256[] memory minTvl, uint256[] memory maxTvl) = tvl();
        uint256 supply = totalSupply();
        uint256 preLpAmount = _getLpAmount(maxTvl, tokenAmounts, supply);
        uint256[] memory normalizedAmounts = new uint256[](tokenAmounts.length);  
        uint256 vaultTokensLength = _vaultTokens.length;
        for (uint256 i = 0; i < vaultTokensLength; ++i) {
            normalizedAmounts[i] = _getNormalizedAmount(maxTvl[i], tokenAmounts[i], preLpAmount, supply);
            IERC20(_vaultTokens[i]).safeTransferFrom(msg.sender, address(this), normalizedAmounts[i]);
        }
        uint256[] memory actualTokenAmounts = _push(normalizedAmounts, "");
        uint256 lpAmount = _getLpAmount(maxTvl, actualTokenAmounts, supply);
        require(lpAmount >= minLpTokens, ExceptionsLibrary.MIN_LP_AMOUNT);
        require(lpAmount != 0, ExceptionsLibrary.ZERO_LP_TOKENS);

        uint256 thisNft = _nft;
        require(
            lpAmount + balanceOf(msg.sender) <=
                IERC20RootVaultGovernance(address(_vaultGovernance)).strategyParams(thisNft).tokenLimitPerAddress,
            ExceptionsLibrary.LIMIT_PER_ADDRESS
        );

        _chargeFees(thisNft, minTvl, supply, actualTokenAmounts, lpAmount, false);
        _mint(msg.sender, lpAmount);

        for (uint256 i = 0; i < _vaultTokens.length; ++i) {
            if (normalizedAmounts[i] > actualTokenAmounts[i]) {
                IERC20(_vaultTokens[i]).safeTransfer(msg.sender, normalizedAmounts[i] - actualTokenAmounts[i]);
            }
        }

        emit Deposit(msg.sender, _vaultTokens, actualTokenAmounts, lpAmount);
    }

    function withdraw(
        address to,
        uint256 lpTokenAmount,
        uint256[] calldata minTokenAmounts
    ) external nonReentrant {
        uint256 supply = totalSupply();
        require(supply > 0, ExceptionsLibrary.TOTAL_SUPPLY_IS_ZERO);
        uint256[] memory tokenAmounts = new uint256[](_vaultTokens.length);
        (uint256[] memory minTvl,) = tvl();
        for (uint256 i = 0; i < _vaultTokens.length; ++i) {
            tokenAmounts[i] = FullMath.mulDiv(lpTokenAmount, minTvl[i], supply);
            require(tokenAmounts[i] >= minTokenAmounts[i], ExceptionsLibrary.MIN_LP_AMOUNT);
        }
        uint256[] memory actualTokenAmounts = _pull(address(this), tokenAmounts, "");
        uint256 vaultTokensLength = _vaultTokens.length;
        for (uint256 i = 0; i < vaultTokensLength; ++i) {
            if (actualTokenAmounts[i] == 0) { 
                continue;
            }

            IERC20(_vaultTokens[i]).safeTransfer(to, actualTokenAmounts[i]);
        }
        _chargeFees(_nft, minTvl, supply, actualTokenAmounts, lpTokenAmount, true);
        _burn(msg.sender, lpTokenAmount);
        emit Withdraw(msg.sender, _vaultTokens, actualTokenAmounts, lpTokenAmount);
    }

    /// @dev We don't charge on any deposit / withdraw to save gas.
    /// While this introduce some error, the charge always goes for lower lp token supply (pre-deposit / post-withdraw)
    /// So the error results in slightly lower management fees than in exact case
    function _chargeFees(
        uint256 thisNft,
        uint256[] memory tvls,
        uint256 supply,
        uint256[] memory deltaTvls,
        uint256 deltaSupply,
        bool isWithdraw
    ) internal {
        IERC20RootVaultGovernance vg = IERC20RootVaultGovernance(address(_vaultGovernance));
        uint256 elapsed = block.timestamp - lastFeeCharge;
        uint256 tvlsLength = tvls.length;
        if (elapsed < vg.delayedProtocolParams().managementFeeChargeDelay) return;

        lastFeeCharge = block.timestamp;
        uint256 baseSupply = supply;
        if (isWithdraw) {
            baseSupply = 0;
            if (supply > deltaSupply) baseSupply = supply - deltaSupply;
        }

        if (baseSupply == 0) {
            for (uint256 i = 0; i < tvlsLength; ++i)
                _lpPriceHighWaterMarks[i] = (deltaTvls[i] * CommonLibrary.PRICE_DENOMINATOR) / deltaSupply;

            return;
        }

        uint256[] memory baseTvls = new uint256[](tvlsLength);
        for (uint256 i = 0; i < baseTvls.length; ++i) {
            if (isWithdraw) baseTvls[i] = tvls[i] - deltaTvls[i];
            else baseTvls[i] = tvls[i];
        }

        IERC20RootVaultGovernance.DelayedStrategyParams memory strategyParams = vg.delayedStrategyParams(thisNft);
        if (strategyParams.managementFee > 0) {
            uint256 toMint = FullMath.mulDiv(
                strategyParams.managementFee * elapsed,
                baseSupply,
                CommonLibrary.YEAR * CommonLibrary.DENOMINATOR
            );
            _mint(strategyParams.strategyTreasury, toMint);
            emit ManagementFeesCharged(strategyParams.strategyTreasury, strategyParams.managementFee, toMint);
        }
        uint256 protocolFee = vg.delayedProtocolPerVaultParams(thisNft).protocolFee;
        if (protocolFee > 0) {
            address treasury = vg.internalParams().protocolGovernance.protocolTreasury();
            uint256 toMint = FullMath.mulDiv(
                protocolFee * elapsed,
                baseSupply,
                CommonLibrary.DENOMINATOR * CommonLibrary.YEAR
            );
            _mint(treasury, toMint);
            emit ProtocolFeesCharged(treasury, protocolFee, toMint);
        }
        uint256 performanceFee = strategyParams.performanceFee;
        if (performanceFee > 0) {
            uint256[] memory hwms = _lpPriceHighWaterMarks;
            uint256 minLpPriceFactor = type(uint256).max;
            for (uint256 i = 0; i < tvlsLength; ++i) {
                uint256 hwm = hwms[i];
                uint256 lpPrice = (baseTvls[i] * CommonLibrary.PRICE_DENOMINATOR) / baseSupply;
                if (lpPrice > hwm) {
                    uint256 delta = (lpPrice * CommonLibrary.DENOMINATOR) / hwm;
                    if (delta < minLpPriceFactor) {
                        minLpPriceFactor = delta;
                    }
                } else {
                    // not eligible for performance fees
                    return;
                }
            }
            for (uint256 i = 0; i < tvlsLength; ++i)
                _lpPriceHighWaterMarks[i] += FullMath.mulDiv(hwms[i], minLpPriceFactor, CommonLibrary.DENOMINATOR);

            address treasury = strategyParams.strategyPerformanceTreasury;
            uint256 toMint = FullMath.mulDiv(
                baseSupply,
                (minLpPriceFactor - CommonLibrary.DENOMINATOR),
                CommonLibrary.DENOMINATOR
            );
            toMint = FullMath.mulDiv(toMint, performanceFee, CommonLibrary.DENOMINATOR);
            _mint(treasury, toMint);
            emit PerformanceFeesCharged(treasury, performanceFee, toMint);
        }
    }

    function _getLpAmount(
        uint256[] memory tvl_,
        uint256[] memory amounts,
        uint256 supply
    ) internal pure returns (uint256 lpAmount) {
        if (supply == 0) {
            // On init lpToken = max(tokenAmounts)
            for (uint256 i = 0; i < tvl_.length; ++i) {
                if (amounts[i] > lpAmount) {
                    lpAmount = amounts[i];
                }
            }

            return lpAmount;
        }
        uint256 tvlsLength = tvl_.length;
        for (uint256 i = 0; i < tvlsLength; ++i) {
            if ((amounts[i] == 0) || (tvl_[i] == 0)) {
                continue;
            }

            uint256 tokenLpAmount = FullMath.mulDiv(amounts[i], supply, tvl_[i]);
            // take min of meaningful tokenLp amounts
            if ((tokenLpAmount < lpAmount) || (lpAmount == 0)) {
                lpAmount = tokenLpAmount;
            }
        }
    }

    function _getNormalizedAmount(
        uint256 tvl_,
        uint256 amount,
        uint256 lpAmount,
        uint256 supply
    ) internal pure returns (uint256) {
        if (supply == 0) {
            // skip normalization on init
            return amount;            
        }

        // normalize amount
        uint256 res = FullMath.mulDiv(tvl_, lpAmount, CommonLibrary.PRICE_DENOMINATOR);
        if (res > amount) {
            res = amount;
        }

        return res;
    }

    /// @notice Emitted when management fees are charged
    /// @param treasury Treasury receiver of the fee
    /// @param feeRate Fee percent applied denominated in 10 ** 9
    /// @param amount Amount of lp token minted
    event ManagementFeesCharged(address indexed treasury, uint256 feeRate, uint256 amount);

    /// @notice Emitted when protocol fees are charged
    /// @param treasury Treasury receiver of the fee
    /// @param feeRate Fee percent applied denominated in 10 ** 9
    /// @param amount Amount of lp token minted
    event ProtocolFeesCharged(address indexed treasury, uint256 feeRate, uint256 amount);

    /// @notice Emitted when performance fees are charged
    /// @param treasury Treasury receiver of the fee
    /// @param feeRate Fee percent applied denominated in 10 ** 9
    /// @param amount Amount of lp token minted
    event PerformanceFeesCharged(address indexed treasury, uint256 feeRate, uint256 amount);

    /// @notice Emitted when liquidity is deposited
    /// @param from The source address for the liquidity
    /// @param tokens ERC20 tokens deposited
    /// @param actualTokenAmounts Token amounts deposited
    /// @param lpTokenMinted LP tokens received by the liquidity provider
    event Deposit(address indexed from, address[] tokens, uint256[] actualTokenAmounts, uint256 lpTokenMinted);

    /// @notice Emitted when liquidity is withdrawn
    /// @param from The source address for the liquidity
    /// @param tokens ERC20 tokens withdrawn
    /// @param actualTokenAmounts Token amounts withdrawn
    /// @param lpTokenBurned LP tokens burned from the liquidity provider
    event Withdraw(address indexed from, address[] tokens, uint256[] actualTokenAmounts, uint256 lpTokenBurned);
}
