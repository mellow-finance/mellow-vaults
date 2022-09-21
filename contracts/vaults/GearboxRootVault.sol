// SPDX-License-Identifier: BSL-1.1
pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "../libraries/external/FullMath.sol";
import "../libraries/ExceptionsLibrary.sol";
import "../interfaces/vaults/IERC20RootVaultGovernance.sol";
import "../interfaces/vaults/IGearboxRootVault.sol";
import "../interfaces/vaults/IGearboxVaultGovernance.sol";
import "../interfaces/utils/ILpCallback.sol";
import "../utils/ERC20Token.sol";
import "./AggregateVault.sol";
import "../interfaces/utils/IERC20RootVaultHelper.sol";

/// @notice Contract that mints and burns LP tokens in exchange for ERC20 liquidity.
contract GearboxRootVault is IGearboxRootVault, ERC20Token, ReentrancyGuard, AggregateVault {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    uint256 public constant D18 = 10**18;

    /// @inheritdoc IGearboxRootVault
    uint64 public lastFeeCharge;
    /// @inheritdoc IGearboxRootVault
    uint64 public totalWithdrawnAmountsTimestamp;
    /// @inheritdoc IGearboxRootVault
    uint256[] public totalWithdrawnAmounts;
    /// @inheritdoc IGearboxRootVault
    uint256 public lpPriceHighWaterMarkD18;
    EnumerableSet.AddressSet private _depositorsAllowlist;
    IERC20RootVaultHelper public helper;

    // -------------------  EXTERNAL, VIEW  -------------------
    /// @inheritdoc IGearboxRootVault
    function depositorsAllowlist() external view returns (address[] memory) {
        return _depositorsAllowlist.values();
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(IERC165, AggregateVault)
        returns (bool)
    {
        return super.supportsInterface(interfaceId) || type(IGearboxRootVault).interfaceId == interfaceId;
    }

    // -------------------  EXTERNAL, MUTATING  -------------------
    /// @inheritdoc IGearboxRootVault
    function addDepositorsToAllowlist(address[] calldata depositors) external {
        _requireAtLeastStrategy();
        for (uint256 i = 0; i < depositors.length; i++) {
            _depositorsAllowlist.add(depositors[i]);
        }
    }

    /// @inheritdoc IGearboxRootVault
    function removeDepositorsFromAllowlist(address[] calldata depositors) external {
        _requireAtLeastStrategy();
        for (uint256 i = 0; i < depositors.length; i++) {
            _depositorsAllowlist.remove(depositors[i]);
        }
    }

    /// @inheritdoc IGearboxRootVault
    function initialize(
        uint256 nft_,
        address[] memory vaultTokens_,
        address strategy_,
        uint256[] memory subvaultNfts_,
        IERC20RootVaultHelper helper_
    ) external {
        require(vaultTokens_.length == 1, ExceptionsLibrary.INVALID_LENGTH);
        _initialize(vaultTokens_, nft_, strategy_, subvaultNfts_);
        _initERC20(_getTokenName(bytes("Mellow Lp Token "), nft_), _getTokenName(bytes("MLP"), nft_));
        uint256 len = vaultTokens_.length;
        totalWithdrawnAmounts = new uint256[](len);
        lastFeeCharge = uint64(block.timestamp);
        helper = helper_;
    }

    /// @inheritdoc IGearboxRootVault
    function deposit(
        uint256[] memory tokenAmounts,
        uint256 minLpTokens,
        bytes memory vaultOptions
    ) external virtual nonReentrant returns (uint256[] memory actualTokenAmounts) {
        require(tokenAmounts.length == 1, ExceptionsLibrary.INVALID_LENGTH);
        require(
            !IERC20RootVaultGovernance(address(_vaultGovernance)).operatorParams().disableDeposit,
            ExceptionsLibrary.FORBIDDEN
        );
        address[] memory tokens = _vaultTokens;
        uint256 supply = totalSupply;
        if (supply == 0) {
            for (uint256 i = 0; i < tokens.length; ++i) {
                require(tokenAmounts[i] >= 10 * _pullExistentials[i], ExceptionsLibrary.LIMIT_UNDERFLOW);
                require(
                    tokenAmounts[i] <= _pullExistentials[i] * _pullExistentials[i],
                    ExceptionsLibrary.LIMIT_OVERFLOW
                );
            }
        }
        (uint256[] memory minTvl, uint256[] memory maxTvl) = tvl();
        uint256 thisNft = _nft;
        _chargeFees(thisNft, minTvl, supply, tokens);
        supply = totalSupply;
        IERC20RootVaultGovernance.DelayedStrategyParams memory delayedStrategyParams = IERC20RootVaultGovernance(
            address(_vaultGovernance)
        ).delayedStrategyParams(thisNft);
        require(
            !delayedStrategyParams.privateVault || _depositorsAllowlist.contains(msg.sender),
            ExceptionsLibrary.FORBIDDEN
        );
        uint256 preLpAmount;
        uint256[] memory normalizedAmounts = new uint256[](tokenAmounts.length);
        {
            bool isSignificantTvl;
            (preLpAmount, isSignificantTvl) = _getLpAmount(maxTvl, tokenAmounts, supply);
            for (uint256 i = 0; i < tokens.length; ++i) {
                normalizedAmounts[i] = _getNormalizedAmount(
                    maxTvl[i],
                    tokenAmounts[i],
                    preLpAmount,
                    supply,
                    isSignificantTvl,
                    _pullExistentials[i]
                );
                IERC20(tokens[i]).safeTransferFrom(msg.sender, address(this), normalizedAmounts[i]);
            }
        }

        actualTokenAmounts = _pushIntoGearbox(normalizedAmounts, vaultOptions);

        (uint256 lpAmount, ) = _getLpAmount(maxTvl, actualTokenAmounts, supply);
        require(lpAmount >= minLpTokens, ExceptionsLibrary.LIMIT_UNDERFLOW);
        require(lpAmount != 0, ExceptionsLibrary.VALUE_ZERO);
        IERC20RootVaultGovernance.StrategyParams memory params = IERC20RootVaultGovernance(address(_vaultGovernance))
            .strategyParams(thisNft);
        require(lpAmount + balanceOf[msg.sender] <= params.tokenLimitPerAddress, ExceptionsLibrary.LIMIT_OVERFLOW);
        require(lpAmount + supply <= params.tokenLimit, ExceptionsLibrary.LIMIT_OVERFLOW);
        // lock tokens on first deposit
        if (supply == 0) {
            _mint(address(0), lpAmount);
        } else {
            _mint(msg.sender, lpAmount);
        }

        for (uint256 i = 0; i < _vaultTokens.length; ++i) {
            if (normalizedAmounts[i] > actualTokenAmounts[i]) {
                IERC20(_vaultTokens[i]).safeTransfer(msg.sender, normalizedAmounts[i] - actualTokenAmounts[i]);
            }
        }

        if (delayedStrategyParams.depositCallbackAddress != address(0)) {
            try ILpCallback(delayedStrategyParams.depositCallbackAddress).depositCallback() {} catch Error(
                string memory reason
            ) {
                emit DepositCallbackLog(reason);
            } catch {
                emit DepositCallbackLog("callback failed without reason");
            }
        }

        emit Deposit(msg.sender, _vaultTokens, actualTokenAmounts, lpAmount);
    }

    mapping (address => uint256) private _withdrawalRequests;
    mapping (address => uint256) private _lastRequestTimestamp;
    uint256 private _beforeLastWithdrawalsExecutionTimestamp;
    uint256 private _lastWithdrawalsExecutionTimestamp;
    uint256 private _totalLpWitdrawalRequests;
    uint256 private _priceForLpTokenD18;

    /// @inheritdoc IGearboxRootVault
    function currentWithdrawalRequested(address addr) external view returns (uint256 totalAmountRequested) {
        if (_lastWithdrawalsExecutionTimestamp <= _lastRequestTimestamp[addr]) {
            return 0;
        }
        return _withdrawalRequests[addr];
    } 

    /// @inheritdoc IGearboxRootVault
    function registerWithdrawal(uint256 lpTokenAmount) external returns (uint256 totalAmountRequested) {

        uint256 existingRequests = 0;
        
        require(block.timestamp > _lastWithdrawalsExecutionTimestamp, ExceptionsLibrary.DISABLED); 

        if (_lastRequestTimestamp[msg.sender] > _lastWithdrawalsExecutionTimestamp) {
            existingRequests = _withdrawalRequests[msg.sender];
        }

        else if (_lastRequestTimestamp[msg.sender] > _beforeLastWithdrawalsExecutionTimestamp) {
            require(_withdrawalRequests[msg.sender] == 0, ExceptionsLibrary.FORBIDDEN);
        }


        uint256 balance = balanceOf[msg.sender];
        if (lpTokenAmount > balance - existingRequests) {
            lpTokenAmount = balance - existingRequests;
        }

        _withdrawalRequests[msg.sender] = existingRequests + lpTokenAmount;
        _lastRequestTimestamp[msg.sender] = block.timestamp;
        _totalLpWitdrawalRequests += lpTokenAmount;

        return _withdrawalRequests[msg.sender];

    }

    /// @inheritdoc IGearboxRootVault
    function cancelWithdrawal(uint256 lpTokenAmount) external returns (uint256 totalAmountRequested)  {

        require(block.timestamp > _lastWithdrawalsExecutionTimestamp, ExceptionsLibrary.DISABLED); 
        require(_lastRequestTimestamp[msg.sender] > _lastWithdrawalsExecutionTimestamp, ExceptionsLibrary.VALUE_ZERO);

        if (_withdrawalRequests[msg.sender] > lpTokenAmount) {
            _withdrawalRequests[msg.sender] -= lpTokenAmount;
        }
        else {
            _withdrawalRequests[msg.sender] = 0;
        }

        return _withdrawalRequests[msg.sender];

    }

    /// @inheritdoc IGearboxRootVault
    function invokeExecution() external {

        IIntegrationVault zeroVault = IIntegrationVault(IAggregateVault(address(this)).subvaultAt(0));
        IIntegrationVault gearboxVault = IIntegrationVault(IAggregateVault(address(this)).subvaultAt(1));

        IGearboxVaultGovernance governance = IGearboxVaultGovernance(address(IVault(gearboxVault).vaultGovernance()));
        uint256 withdrawDelay = governance.delayedProtocolParams().withdrawDelay;

        require(_lastWithdrawalsExecutionTimestamp + withdrawDelay <= block.timestamp, ExceptionsLibrary.INVARIANT);
        _beforeLastWithdrawalsExecutionTimestamp = block.timestamp;
        _lastWithdrawalsExecutionTimestamp = block.timestamp;

        (uint256[] memory minTokenAmounts, ) = IAggregateVault(address(this)).tvl();

        uint256 totalAmount = FullMath.mulDiv(_totalLpWitdrawalRequests, minTokenAmounts[0], totalSupply);

        uint256 currentErc20Amount = IERC20(_vaultTokens[0]).balanceOf(address(zeroVault));

        if (currentErc20Amount > totalAmount) {
            address[] memory tokens = _vaultTokens;
            uint256[] memory amounts = new uint256[](1);
            amounts[0] = currentErc20Amount - totalAmount;
            zeroVault.pull(address(gearboxVault), tokens, amounts, "");
        }

        else {
            address[] memory tokens = _vaultTokens;
            uint256[] memory amounts = new uint256[](1);
            amounts[0] = totalAmount - currentErc20Amount;
            zeroVault.pull(address(gearboxVault), tokens, amounts, "");
            totalAmount = IERC20(_vaultTokens[0]).balanceOf(address(zeroVault));
        }

        _priceForLpTokenD18 = FullMath.mulDiv(totalAmount, D18, totalSupply);
        _totalLpWitdrawalRequests = 0;

    }

    /// @inheritdoc IGearboxRootVault
    function withdraw(
        address to,
        uint256 lpTokenAmount,
        uint256[] memory minTokenAmounts,
        bytes[] memory vaultsOptions
    ) external nonReentrant returns (uint256[] memory actualTokenAmounts) {
        require(minTokenAmounts.length == 1, ExceptionsLibrary.INVALID_LENGTH);
        uint256 supply = totalSupply;
        require(supply > 0, ExceptionsLibrary.VALUE_ZERO);
        address[] memory tokens = _vaultTokens;
        uint256[] memory tokenAmounts = new uint256[](_vaultTokens.length);
        (uint256[] memory minTvl, ) = tvl();
        _chargeFees(_nft, minTvl, supply, tokens);

        uint256 balance;

        {
            uint256 availableLpTokens = 0;
            if (_lastRequestTimestamp[msg.sender] > _beforeLastWithdrawalsExecutionTimestamp && _lastRequestTimestamp[msg.sender] > _lastWithdrawalsExecutionTimestamp) {
                availableLpTokens = _withdrawalRequests[msg.sender];
            }

            supply = totalSupply;
            balance = balanceOf[msg.sender];

            if (lpTokenAmount > availableLpTokens) {
                lpTokenAmount = availableLpTokens;
            }
        }

        _withdrawalRequests[msg.sender] -= lpTokenAmount;
        tokenAmounts[0] = FullMath.mulDiv(lpTokenAmount, _priceForLpTokenD18, D18);

        actualTokenAmounts = _pull(address(this), tokenAmounts, vaultsOptions);
        // we are draining balance
        // if no sufficent amounts rest
        bool sufficientAmountRest = false;
        for (uint256 i = 0; i < tokens.length; ++i) {
            require(actualTokenAmounts[i] >= minTokenAmounts[i], ExceptionsLibrary.LIMIT_UNDERFLOW);
            if (FullMath.mulDiv(balance, minTvl[i], supply) >= _pullExistentials[i] + actualTokenAmounts[i]) {
                sufficientAmountRest = true;
            }
            if (actualTokenAmounts[i] != 0) {
                IERC20(tokens[i]).safeTransfer(to, actualTokenAmounts[i]);
            }
        }
        _updateWithdrawnAmounts(actualTokenAmounts);
        if (sufficientAmountRest) {
            _burn(msg.sender, lpTokenAmount);
        } else {
            _burn(msg.sender, balance);
        }

        uint256 thisNft = _nft;
        IERC20RootVaultGovernance.DelayedStrategyParams memory delayedStrategyParams = IERC20RootVaultGovernance(
            address(_vaultGovernance)
        ).delayedStrategyParams(thisNft);

        if (delayedStrategyParams.withdrawCallbackAddress != address(0)) {
            try ILpCallback(delayedStrategyParams.withdrawCallbackAddress).withdrawCallback() {} catch Error(
                string memory reason
            ) {
                emit WithdrawCallbackLog(reason);
            } catch {
                emit WithdrawCallbackLog("callback failed without reason");
            }
        }

        emit Withdraw(msg.sender, _vaultTokens, actualTokenAmounts, lpTokenAmount);
    }

    // -------------------  INTERNAL, VIEW  -------------------

    function _getLpAmount(
        uint256[] memory tvl_,
        uint256[] memory amounts,
        uint256 supply
    ) internal view returns (uint256 lpAmount, bool isSignificantTvl) {
        if (supply == 0) {
            // On init lpToken = max(tokenAmounts)
            for (uint256 i = 0; i < tvl_.length; ++i) {
                if (amounts[i] > lpAmount) {
                    lpAmount = amounts[i];
                }
            }
            return (lpAmount, false);
        }
        uint256 tvlsLength = tvl_.length;
        bool isLpAmountUpdated = false;
        uint256[] memory pullExistentials = _pullExistentials;
        for (uint256 i = 0; i < tvlsLength; ++i) {
            if (tvl_[i] < pullExistentials[i]) {
                continue;
            }

            uint256 tokenLpAmount = FullMath.mulDiv(amounts[i], supply, tvl_[i]);
            // take min of meaningful tokenLp amounts
            if ((tokenLpAmount < lpAmount) || (isLpAmountUpdated == false)) {
                isLpAmountUpdated = true;
                lpAmount = tokenLpAmount;
            }
        }
        isSignificantTvl = isLpAmountUpdated;
        // in case of almost zero tvl for all tokens -> do the same with supply == 0
        if (!isSignificantTvl) {
            for (uint256 i = 0; i < tvl_.length; ++i) {
                if (amounts[i] > lpAmount) {
                    lpAmount = amounts[i];
                }
            }
        }
    }

    function _getNormalizedAmount(
        uint256 tvl_,
        uint256 amount,
        uint256 lpAmount,
        uint256 supply,
        bool isSignificantTvl,
        uint256 existentialsAmount
    ) internal pure returns (uint256) {
        if (supply == 0 || !isSignificantTvl) {
            // skip normalization on init
            return amount;
        }

        if (tvl_ < existentialsAmount) {
            // use zero-normalization when all tvls are dust-like
            return 0;
        }

        // normalize amount
        uint256 res = FullMath.mulDiv(tvl_, lpAmount, supply);
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
        return string(abi.encodePacked(prefix, number));
    }

    // -------------------  INTERNAL, MUTATING  -------------------

    /// @dev we are charging fees on the deposit / withdrawal
    /// fees are charged before the tokens transfer and change the balance of the lp tokens
    function _chargeFees(
        uint256 thisNft,
        uint256[] memory tvls,
        uint256 supply,
        address[] memory tokens
    ) internal {
        IERC20RootVaultGovernance vg = IERC20RootVaultGovernance(address(_vaultGovernance));
        uint256 elapsed = block.timestamp - uint256(lastFeeCharge);
        IERC20RootVaultGovernance.DelayedProtocolParams memory delayedProtocolParams = vg.delayedProtocolParams();
        if (elapsed < delayedProtocolParams.managementFeeChargeDelay) {
            return;
        }
        lastFeeCharge = uint64(block.timestamp);
        // don't charge on initial deposit
        if (supply == 0) {
            return;
        }
        {
            bool needSkip = true;
            uint256[] memory pullExistentials = _pullExistentials;
            for (uint256 i = 0; i < pullExistentials.length; ++i) {
                if (tvls[i] >= pullExistentials[i]) {
                    needSkip = false;
                    break;
                }
            }
            if (needSkip) {
                return;
            }
        }
        IERC20RootVaultGovernance.DelayedStrategyParams memory strategyParams = vg.delayedStrategyParams(thisNft);
        uint256 protocolFee = vg.delayedProtocolPerVaultParams(thisNft).protocolFee;
        address protocolTreasury = vg.internalParams().protocolGovernance.protocolTreasury();
        _chargeManagementFees(
            strategyParams.managementFee,
            protocolFee,
            strategyParams.strategyTreasury,
            protocolTreasury,
            elapsed,
            supply
        );

        _chargePerformanceFees(
            supply,
            tvls,
            strategyParams.performanceFee,
            strategyParams.strategyPerformanceTreasury,
            tokens,
            delayedProtocolParams.oracle
        );
    }

    function _chargeManagementFees(
        uint256 managementFee,
        uint256 protocolFee,
        address strategyTreasury,
        address protocolTreasury,
        uint256 elapsed,
        uint256 lpSupply
    ) internal {
        if (managementFee > 0) {
            uint256 toMint = FullMath.mulDiv(
                managementFee * elapsed,
                lpSupply,
                CommonLibrary.YEAR * CommonLibrary.DENOMINATOR
            );
            _mint(strategyTreasury, toMint);
            emit ManagementFeesCharged(strategyTreasury, managementFee, toMint);
        }
        if (protocolFee > 0) {
            uint256 toMint = FullMath.mulDiv(
                protocolFee * elapsed,
                lpSupply,
                CommonLibrary.YEAR * CommonLibrary.DENOMINATOR
            );
            _mint(protocolTreasury, toMint);
            emit ProtocolFeesCharged(protocolTreasury, protocolFee, toMint);
        }
    }

    function _chargePerformanceFees(
        uint256 baseSupply,
        uint256[] memory baseTvls,
        uint256 performanceFee,
        address treasury,
        address[] memory tokens,
        IOracle oracle
    ) internal {
        if ((performanceFee == 0) || (baseSupply == 0)) {
            return;
        }
        uint256 tvlToken0 = helper.getTvlToken0(baseTvls, tokens, oracle);
        uint256 lpPriceD18 = FullMath.mulDiv(tvlToken0, CommonLibrary.D18, baseSupply);
        uint256 hwmsD18 = lpPriceHighWaterMarkD18;
        if (lpPriceD18 <= hwmsD18) {
            return;
        }
        uint256 toMint;
        if (hwmsD18 > 0) {
            toMint = FullMath.mulDiv(baseSupply, lpPriceD18 - hwmsD18, hwmsD18);
            toMint = FullMath.mulDiv(toMint, performanceFee, CommonLibrary.DENOMINATOR);
            _mint(treasury, toMint);
        }
        lpPriceHighWaterMarkD18 = lpPriceD18;
        emit PerformanceFeesCharged(treasury, performanceFee, toMint);
    }

    function _updateWithdrawnAmounts(uint256[] memory tokenAmounts) internal {
        uint256[] memory withdrawn = new uint256[](tokenAmounts.length);
        uint64 timestamp = uint64(block.timestamp);
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

    function _pushIntoGearbox(uint256[] memory tokenAmounts, bytes memory vaultOptions)
        internal
        returns (uint256[] memory actualTokenAmounts)
    {
        require(_nft != 0, ExceptionsLibrary.INIT);
        IIntegrationVault gearboxVault = IIntegrationVault(IAggregateVault(address(this)).subvaultAt(1));
        for (uint256 i = 0; i < _vaultTokens.length; i++) {
            if (tokenAmounts[i] > 0) {
                IERC20(_vaultTokens[i]).safeIncreaseAllowance(address(gearboxVault), tokenAmounts[i]);
            }
        }

        actualTokenAmounts = gearboxVault.transferAndPush(address(this), _vaultTokens, tokenAmounts, vaultOptions);

        for (uint256 i = 0; i < _vaultTokens.length; i++) {
            if (tokenAmounts[i] > 0) {
                IERC20(_vaultTokens[i]).safeApprove(address(gearboxVault), 0);
            }
        }
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

    /// @notice Emitted when callback in deposit failed
    /// @param reason Error reason
    event DepositCallbackLog(string reason);

    /// @notice Emitted when callback in withdraw failed
    /// @param reason Error reason
    event WithdrawCallbackLog(string reason);
}
