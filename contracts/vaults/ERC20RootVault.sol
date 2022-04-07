// SPDX-License-Identifier: BSL-1.1
pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "../libraries/external/FullMath.sol";
import "../libraries/ExceptionsLibrary.sol";
import "../interfaces/vaults/IERC20RootVaultGovernance.sol";
import "../interfaces/vaults/IERC20RootVault.sol";
import "../interfaces/utils/ILpCallback.sol";
import "../utils/ERC20Token.sol";
import "./AggregateVault.sol";

/// @notice Contract that mints and burns LP tokens in exchange for ERC20 liquidity.
contract ERC20RootVault is IERC20RootVault, ERC20Token, ReentrancyGuard, AggregateVault {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    uint256 public constant FIRST_DEPOSIT_LIMIT = 10000;
    uint64 public lastFeeCharge;
    uint64 public totalWithdrawnAmountsTimestamp;
    uint256[] public totalWithdrawnAmounts;

    uint256 public lpPriceHighWaterMarkD18;
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
        totalWithdrawnAmounts = new uint256[](vaultTokens_.length);
        lastFeeCharge = uint64(block.timestamp);
    }

    function deposit(
        uint256[] memory tokenAmounts,
        uint256 minLpTokens,
        bytes memory vaultOptions
    ) external nonReentrant returns (uint256[] memory actualTokenAmounts) {
        require(
            !IERC20RootVaultGovernance(address(_vaultGovernance)).operatorParams().disableDeposit,
            ExceptionsLibrary.FORBIDDEN
        );
        if (totalSupply == 0) {
            for (uint256 i = 0; i < _vaultTokens.length; ++i) {
                require(tokenAmounts[i] > FIRST_DEPOSIT_LIMIT, ExceptionsLibrary.LIMIT_UNDERFLOW);
            }
        }
        (uint256[] memory minTvl, uint256[] memory maxTvl) = tvl();
        IERC20RootVaultGovernance.DelayedStrategyParams memory delayedStrategyParams = IERC20RootVaultGovernance(
            address(_vaultGovernance)
        ).delayedStrategyParams(_nft);
        require(
            !delayedStrategyParams.privateVault || _depositorsAllowlist.contains(msg.sender),
            ExceptionsLibrary.FORBIDDEN
        );
        uint256 preLpAmount = _getLpAmount(maxTvl, tokenAmounts, totalSupply);
        uint256[] memory normalizedAmounts = new uint256[](tokenAmounts.length);
        for (uint256 i = 0; i < _vaultTokens.length; ++i) {
            if (totalSupply == 0) {
                // skip normalization on init
                normalizedAmounts[i] = tokenAmounts[i];
            } else {
                // normalize amount
                normalizedAmounts[i] = FullMath.mulDiv(maxTvl[i], preLpAmount, totalSupply);
                if (normalizedAmounts[i] > tokenAmounts[i]) {
                    normalizedAmounts[i] = tokenAmounts[i];
                }
            }
            IERC20(_vaultTokens[i]).safeTransferFrom(msg.sender, address(this), normalizedAmounts[i]);
        }
        actualTokenAmounts = _push(normalizedAmounts, vaultOptions);
        uint256 lpAmount = _getLpAmount(maxTvl, actualTokenAmounts, totalSupply);
        require(lpAmount >= minLpTokens, ExceptionsLibrary.LIMIT_UNDERFLOW);
        require(lpAmount != 0, ExceptionsLibrary.VALUE_ZERO);
        IERC20RootVaultGovernance.StrategyParams memory params = IERC20RootVaultGovernance(address(_vaultGovernance))
            .strategyParams(_nft);
        require(lpAmount + balanceOf[msg.sender] <= params.tokenLimitPerAddress, ExceptionsLibrary.LIMIT_OVERFLOW);
        require(lpAmount + totalSupply <= params.tokenLimit, ExceptionsLibrary.LIMIT_OVERFLOW);

        _chargeFees(_nft, minTvl, totalSupply, actualTokenAmounts, lpAmount, _vaultTokens, false);
        _mint(msg.sender, lpAmount);

        for (uint256 i = 0; i < _vaultTokens.length; ++i) {
            if (normalizedAmounts[i] > actualTokenAmounts[i]) {
                IERC20(_vaultTokens[i]).safeTransfer(msg.sender, normalizedAmounts[i] - actualTokenAmounts[i]);
            }
        }

        if (delayedStrategyParams.depositCallback != address(0)) {
            ILpCallback callbackContract = ILpCallback(delayedStrategyParams.depositCallback);
            callbackContract.depositCallback();
        }

        emit Deposit(msg.sender, _vaultTokens, actualTokenAmounts, lpAmount);
    }

    function withdraw(
        address to,
        uint256 lpTokenAmount,
        uint256[] memory minTokenAmounts,
        bytes[] memory vaultsOptions
    ) external nonReentrant returns (uint256[] memory actualTokenAmounts) {
        require(totalSupply > 0, ExceptionsLibrary.VALUE_ZERO);
        uint256[] memory tokenAmounts = new uint256[](_vaultTokens.length);
        (uint256[] memory minTvl, ) = tvl();
        if (lpTokenAmount > balanceOf[msg.sender]) {
            lpTokenAmount = balanceOf[msg.sender];
        }
        for (uint256 i = 0; i < _vaultTokens.length; ++i) {
            tokenAmounts[i] = FullMath.mulDiv(lpTokenAmount, minTvl[i], totalSupply);
        }
        actualTokenAmounts = _pull(address(this), tokenAmounts, vaultsOptions);
        for (uint256 i = 0; i < _vaultTokens.length; ++i) {
            require(actualTokenAmounts[i] >= minTokenAmounts[i], ExceptionsLibrary.LIMIT_UNDERFLOW);
        }
        for (uint256 i = 0; i < _vaultTokens.length; ++i) {
            if (actualTokenAmounts[i] == 0) {
                continue;
            }

            IERC20(_vaultTokens[i]).safeTransfer(to, actualTokenAmounts[i]);
        }
        uint256[] memory withdrawn = new uint256[](actualTokenAmounts.length);
        IProtocolGovernance protocolGovernance = _vaultGovernance.internalParams().protocolGovernance;
        if (uint64(block.timestamp) != totalWithdrawnAmountsTimestamp) {
            totalWithdrawnAmountsTimestamp = uint64(block.timestamp);
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
        _chargeFees(_nft, minTvl, totalSupply, actualTokenAmounts, lpTokenAmount, _vaultTokens, true);
        _burn(msg.sender, lpTokenAmount);

        IERC20RootVaultGovernance.DelayedStrategyParams memory delayedStrategyParams = IERC20RootVaultGovernance(
            address(_vaultGovernance)
        ).delayedStrategyParams(_nft);

        if (delayedStrategyParams.withdrawCallback != address(0)) {
            ILpCallback callbackContract = ILpCallback(delayedStrategyParams.withdrawCallback);
            try callbackContract.withdrawCallback() {} catch Error(string memory reason) {
                emit WithdrawCallbackLog(reason);
            } catch {
                emit WithdrawCallbackLog(ExceptionsLibrary.CALLBACK_FAILED);
            }
        }

        emit Withdraw(msg.sender, _vaultTokens, actualTokenAmounts, lpTokenAmount);
    }

    // -------------------  INTERNAL, VIEW  -------------------

    function _getLpAmount(
        uint256[] memory tvl_,
        uint256[] memory amounts,
        uint256 supply
    ) internal view returns (uint256 lpAmount) {
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
        bool isLpAmountUpdated = false;
        for (uint256 i = 0; i < tvlsLength; ++i) {
            if (tvl_[i] < _pullExistentials[i]) {
                continue;
            }

            uint256 tokenLpAmount = FullMath.mulDiv(amounts[i], supply, tvl_[i]);
            // take min of meaningful tokenLp amounts
            if ((tokenLpAmount < lpAmount) || (isLpAmountUpdated == false)) {
                isLpAmountUpdated = true;
                lpAmount = tokenLpAmount;
            }
        }
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
        return string(abi.encodePacked(prefix, number));
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
        address[] memory tokens,
        bool isWithdraw
    ) internal {
        IERC20RootVaultGovernance vg = IERC20RootVaultGovernance(address(_vaultGovernance));
        uint256 elapsed = block.timestamp - uint256(lastFeeCharge);
        IERC20RootVaultGovernance.DelayedProtocolParams memory delayedProtocolParams = vg.delayedProtocolParams();
        if (elapsed < delayedProtocolParams.managementFeeChargeDelay) {
            return;
        }
        uint256 baseSupply = supply;
        if (isWithdraw) {
            baseSupply = 0;
            if (supply > deltaSupply) {
                baseSupply = supply - deltaSupply;
            }
        }
        uint256[] memory baseTvls = new uint256[](tvls.length);
        for (uint256 i = 0; i < baseTvls.length; ++i) {
            if (isWithdraw) baseTvls[i] = tvls[i] - deltaTvls[i];
            else baseTvls[i] = tvls[i];
        }
        lastFeeCharge = uint64(block.timestamp);
        // don't charge on initial deposit as well as on the last withdraw
        if (baseSupply == 0) {
            return;
        }
        IERC20RootVaultGovernance.DelayedStrategyParams memory strategyParams = vg.delayedStrategyParams(thisNft);
        uint256 protocolFee = vg.delayedProtocolPerVaultParams(thisNft).protocolFee;
        address protocolTreasury = vg.internalParams().protocolGovernance.protocolTreasury();

        if (strategyParams.managementFee > 0) {
            uint256 toMint = FullMath.mulDiv(
                strategyParams.managementFee * elapsed,
                baseSupply,
                CommonLibrary.YEAR * CommonLibrary.DENOMINATOR
            );
            _mint(strategyParams.strategyTreasury, toMint);
            emit ManagementFeesCharged(strategyParams.strategyTreasury, strategyParams.managementFee, toMint);
        }
        if (protocolFee > 0) {
            uint256 toMint = FullMath.mulDiv(
                protocolFee * elapsed,
                baseSupply,
                CommonLibrary.YEAR * CommonLibrary.DENOMINATOR
            );
            _mint(protocolTreasury, toMint);
            emit ProtocolFeesCharged(protocolTreasury, protocolFee, toMint);
        }

        if ((strategyParams.performanceFee == 0) || (baseSupply == 0)) {
            return;
        }
        uint256 tvlToken0 = baseTvls[0]; //_getTvlToken0(baseTvls, tokens, oracle);
        for (uint256 i = 1; i < baseTvls.length; i++) {
            (uint256[] memory prices, ) = delayedProtocolParams.oracle.price(tokens[0], tokens[i], 0x28);
            require(prices.length > 0, ExceptionsLibrary.VALUE_ZERO);
            uint256 price = 0;
            for (uint256 j = 0; j < prices.length; j++) {
                price += prices[j];
            }
            price /= prices.length;
            tvlToken0 += baseTvls[i] / price;
        }

        uint256 lpPriceD18 = FullMath.mulDiv(tvlToken0, CommonLibrary.D18, baseSupply);
        uint256 hwmsD18 = lpPriceHighWaterMarkD18;
        if (lpPriceD18 <= hwmsD18) {
            return;
        }
        uint256 toMint;
        if (hwmsD18 > 0) {
            toMint = FullMath.mulDiv(baseSupply, lpPriceD18 - hwmsD18, hwmsD18);
            toMint = FullMath.mulDiv(toMint, strategyParams.performanceFee, CommonLibrary.DENOMINATOR);
        }
        lpPriceHighWaterMarkD18 = lpPriceD18;
        _mint(strategyParams.strategyPerformanceTreasury, toMint);
        emit PerformanceFeesCharged(strategyParams.strategyPerformanceTreasury, strategyParams.performanceFee, toMint);
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

    /// @notice Emitted when callback in withdraw failed
    /// @param reason Error reason
    event WithdrawCallbackLog(string reason);
}
