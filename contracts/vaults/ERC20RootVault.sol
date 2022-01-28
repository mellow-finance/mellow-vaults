// SPDX-License-Identifier: BSL-1.1
pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "../libraries/external/FullMath.sol";
import "../libraries/ExceptionsLibrary.sol";
import "../interfaces/utils/IContractMeta.sol";
import "../interfaces/vaults/IERC20RootVaultGovernance.sol";
import "../interfaces/vaults/IERC20RootVault.sol";
import "../interfaces/oracles/IExactOracle.sol";
import "../utils/ERC20Token.sol";
import "./AggregateVault.sol";

/// @notice Contract that mints and burns LP tokens in exchange for ERC20 liquidity.
contract ERC20RootVault is IERC20RootVault, ERC20Token, ReentrancyGuard, AggregateVault {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    uint256 public lpPriceHighWatermark;
    uint256 public lastFeeCharge;
    uint256 public totalWithdrawnAmountsTimestamp;
    uint256[] public totalWithdrawnAmounts;

    EnumerableSet.AddressSet private _depositorsAllowlist;

    // -------------------  EXTERNAL, VIEW  -------------------

    function depositorsAllowlist() external view returns (address[] memory) {
        return _depositorsAllowlist.values();
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(IERC165, AggregateVault)
        returns (bool)
    {
        return super.supportsInterface(interfaceId) || type(IERC20RootVault).interfaceId == interfaceId;
    }

    // -------------------  EXTERNAL, MUTATING  -------------------

    function addDepositorsToAllowlist(address[] calldata depositors) external {
        _requireAtLeastStrategy();
        for (uint256 i = 0; i < depositors.length; i++) {
            _depositorsAllowlist.add(depositors[i]);
        }
    }

    function removeDepositorsFromAllowlist(address[] calldata depositors) external {
        _requireAtLeastStrategy();
        for (uint256 i = 0; i < depositors.length; i++) {
            _depositorsAllowlist.remove(depositors[i]);
        }
    }

    function initialize(
        uint256 nft_,
        address[] memory vaultTokens_,
        address strategy_,
        uint256[] memory subvaultNfts_
    ) external {
        _initialize(vaultTokens_, nft_, strategy_, subvaultNfts_);

        _initERC20(_getTokenName(bytes("Mellow Lp Token "), nft_), _getTokenName(bytes("MLP"), nft_));
        uint256 len = vaultTokens_.length;
        totalWithdrawnAmounts = new uint256[](len);

        lastFeeCharge = block.timestamp;
    }

    function deposit(uint256[] memory tokenAmounts, uint256 minLpTokens)
        external
        nonReentrant
        returns (uint256[] memory actualTokenAmounts)
    {
        require(
            !IERC20RootVaultGovernance(address(_vaultGovernance)).operatorParams().disableDeposit,
            ExceptionsLibrary.FORBIDDEN
        );
        (uint256[] memory minTvl, uint256[] memory maxTvl) = tvl();
        uint256 thisNft = _nft;
        IERC20RootVaultGovernance.DelayedStrategyParams memory delayedStaretgyParams = IERC20RootVaultGovernance(
            address(_vaultGovernance)
        ).delayedStrategyParams(thisNft);
        require(
            !delayedStaretgyParams.privateVault || _depositorsAllowlist.contains(msg.sender),
            ExceptionsLibrary.FORBIDDEN
        );
        uint256 supply = totalSupply;
        uint256 preLpAmount = _getLpAmount(maxTvl, tokenAmounts, supply);
        uint256[] memory normalizedAmounts = new uint256[](tokenAmounts.length);
        uint256 vaultTokensLength = _vaultTokens.length;
        for (uint256 i = 0; i < vaultTokensLength; ++i) {
            normalizedAmounts[i] = _getNormalizedAmount(maxTvl[i], tokenAmounts[i], preLpAmount, supply);
            IERC20(_vaultTokens[i]).safeTransferFrom(msg.sender, address(this), normalizedAmounts[i]);
        }
        actualTokenAmounts = _push(normalizedAmounts, "");
        uint256 lpAmount = _getLpAmount(maxTvl, actualTokenAmounts, supply);
        require(lpAmount >= minLpTokens, ExceptionsLibrary.LIMIT_UNDERFLOW);
        require(lpAmount != 0, ExceptionsLibrary.VALUE_ZERO);
        IERC20RootVaultGovernance.StrategyParams memory params = IERC20RootVaultGovernance(address(_vaultGovernance))
            .strategyParams(thisNft);
        require(lpAmount + balanceOf[msg.sender] <= params.tokenLimitPerAddress, ExceptionsLibrary.LIMIT_OVERFLOW);
        require(lpAmount + totalSupply <= params.tokenLimit, ExceptionsLibrary.LIMIT_OVERFLOW);

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
        uint256[] memory minTokenAmounts
    ) external nonReentrant returns (uint256[] memory actualTokenAmounts) {
        uint256 supply = totalSupply;
        require(supply > 0, ExceptionsLibrary.VALUE_ZERO);
        uint256[] memory tokenAmounts = new uint256[](_vaultTokens.length);
        (uint256[] memory minTvl, ) = tvl();
        for (uint256 i = 0; i < _vaultTokens.length; ++i) {
            tokenAmounts[i] = FullMath.mulDiv(lpTokenAmount, minTvl[i], supply);
            require(tokenAmounts[i] >= minTokenAmounts[i], ExceptionsLibrary.LIMIT_UNDERFLOW);
        }
        actualTokenAmounts = _pull(address(this), tokenAmounts, "");
        uint256 vaultTokensLength = _vaultTokens.length;
        for (uint256 i = 0; i < vaultTokensLength; ++i) {
            if (actualTokenAmounts[i] == 0) {
                continue;
            }

            IERC20(_vaultTokens[i]).safeTransfer(to, actualTokenAmounts[i]);
        }
        _updateWithdrawnAmounts(actualTokenAmounts);
        _chargeFees(_nft, minTvl, supply, actualTokenAmounts, lpTokenAmount, true);
        _burn(msg.sender, lpTokenAmount);
        emit Withdraw(msg.sender, _vaultTokens, actualTokenAmounts, lpTokenAmount);
    }

    // -------------------  INTERNAL, VIEW  -------------------

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

    function _requireAtLeastStrategy() internal view {
        uint256 nft_ = _nft;
        IVaultGovernance.InternalParams memory internalParams = _vaultGovernance.internalParams();
        require(
            (internalParams.protocolGovernance.isAdmin(msg.sender) ||
                internalParams.registry.getApproved(nft_) == msg.sender ||
                (internalParams.registry.ownerOf(nft_) == msg.sender)),
            ExceptionsLibrary.FORBIDDEN
        );
    }

    function _getTokenName(bytes memory prefix, uint256 nft_) internal pure returns (string memory) {
        bytes memory number = bytes(Strings.toString(nft_));
        bytes memory res = new bytes(prefix.length + number.length);
        for (uint256 i = 0; i < prefix.length; i++) {
            res[i] = prefix[i];
        }
        for (uint256 i = 0; i < number.length; i++) {
            res[i + prefix.length] = number[i];
        }
        return string(res);
    }

    // -------------------  INTERNAL, MUTATING  -------------------

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
        if (elapsed < vg.delayedProtocolParams().managementFeeChargeDelay) {
            return;
        }

        lastFeeCharge = block.timestamp;
        uint256 baseSupply = supply;
        if (isWithdraw) {
            baseSupply = 0;
            if (supply > deltaSupply) {
                baseSupply = supply - deltaSupply;
            }
        }

        if (baseSupply == 0) {
            delete lpPriceHighWatermark;
            return;
        }

        uint256[] memory baseTvls = new uint256[](tvlsLength);
        for (uint256 i = 0; i < baseTvls.length; ++i) {
            if (isWithdraw) {
                baseTvls[i] = tvls[i] - deltaTvls[i];
            } else {
                baseTvls[i] = tvls[i];
            }
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
            uint256 lpPrice = _calcLpPriceHighWatermark(vg.delayedProtocolParams().oracle, baseTvls, baseSupply);
            if (lpPrice > lpPriceHighWatermark) {
                uint256 growth = FullMath.mulDiv(lpPrice, CommonLibrary.DENOMINATOR, lpPriceHighWatermark);
                lpPriceHighWatermark = lpPrice;
                uint256 toMint = FullMath.mulDiv(baseSupply, growth, CommonLibrary.DENOMINATOR);
                toMint = FullMath.mulDiv(toMint, performanceFee, CommonLibrary.DENOMINATOR);
                address treasury = strategyParams.strategyPerformanceTreasury;
                _mint(treasury, toMint);
                emit PerformanceFeesCharged(treasury, performanceFee, toMint);
            }
        }
    }

    function _updateWithdrawnAmounts(uint256[] memory tokenAmounts) internal {
        uint256[] memory withdrawn = new uint256[](tokenAmounts.length);
        uint256 timestamp = block.timestamp;
        IProtocolGovernance protocolGovernance = _vaultGovernance.internalParams().protocolGovernance;
        if (timestamp != totalWithdrawnAmountsTimestamp) {
            totalWithdrawnAmountsTimestamp = timestamp;
        } else {
            for (uint256 i = 0; i < tokenAmounts.length; i++) {
                withdrawn[i] = totalWithdrawnAmounts[i];
            }
        }
        for (uint256 i = 0; i < tokenAmounts.length; i++) {
            withdrawn[i] += tokenAmounts[i];
            require(
                withdrawn[i] <= protocolGovernance.withdrawLimit(_vaultTokens[i]),
                ExceptionsLibrary.LIMIT_OVERFLOW
            );
            totalWithdrawnAmounts[i] = withdrawn[i];
        }
    }

    function _calcLpPriceHighWatermark(
        IExactOracle oracle,
        uint256[] memory tvl_,
        uint256 lp
    ) internal view returns (uint256) {
        uint256 totalTvlX96;
        for (uint256 i; i != tvl_.length; ++i) {
            address token = _vaultTokens[i];
            if (oracle.canTellExactPrice(token)) {
                totalTvlX96 += oracle.exactPriceX96(token) * tvl_[i];
            } else {
                return 0;
            }
        }
        return FullMath.mulDiv(totalTvlX96, CommonLibrary.PRICE_DENOMINATOR, lp * CommonLibrary.Q96);
    }

    // --------------------------  EVENTS  --------------------------

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
