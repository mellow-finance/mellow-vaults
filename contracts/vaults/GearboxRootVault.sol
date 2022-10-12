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
    uint256 public lpPriceHighWaterMarkD18;

    EnumerableSet.AddressSet private _depositorsAllowlist;

    IIntegrationVault public gearboxVault;
    IIntegrationVault public erc20Vault;
    address public primaryToken;

    bool public wasDeposit;
    bool public isClosed;

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
        address
    ) external {
        require(vaultTokens_.length == 1, ExceptionsLibrary.INVALID_LENGTH);
        _initialize(vaultTokens_, nft_, strategy_, subvaultNfts_);
        _initERC20(_getTokenName(bytes("Mellow Lp Token "), nft_), _getTokenName(bytes("MLP"), nft_));

        erc20Vault = IIntegrationVault(IAggregateVault(address(this)).subvaultAt(0));
        gearboxVault = IIntegrationVault(IAggregateVault(address(this)).subvaultAt(1));
        primaryToken = vaultTokens_[0];

        currentEpoch = 1;

        lastFeeCharge = uint64(block.timestamp);
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
        require(!isClosed, ExceptionsLibrary.FORBIDDEN);

        uint256 thisNft = _nft;

        if (!wasDeposit) {
            require(tokenAmounts[0] >= 10 * _pullExistentials[0], ExceptionsLibrary.LIMIT_UNDERFLOW);
            require(tokenAmounts[0] <= _pullExistentials[0] * _pullExistentials[0], ExceptionsLibrary.LIMIT_OVERFLOW);
        }

        IERC20RootVaultGovernance.DelayedStrategyParams memory delayedStrategyParams = IERC20RootVaultGovernance(
            address(_vaultGovernance)
        ).delayedStrategyParams(thisNft);
        require(
            !delayedStrategyParams.privateVault || _depositorsAllowlist.contains(msg.sender),
            ExceptionsLibrary.FORBIDDEN
        );

        (uint256[] memory minTvl, ) = gearboxVault.tvl();
        _chargeFees(thisNft, minTvl[0], totalSupply - totalLpTokensWaitingWithdrawal);

        uint256 supply = totalSupply - totalLpTokensWaitingWithdrawal;
        uint256 lpAmount;

        if (!wasDeposit) {
            lpAmount = tokenAmounts[0];
        } else {
            lpAmount = FullMath.mulDiv(supply, tokenAmounts[0], minTvl[0]);
        }

        require(lpAmount >= minLpTokens, ExceptionsLibrary.LIMIT_UNDERFLOW);
        require(lpAmount != 0, ExceptionsLibrary.VALUE_ZERO);
        IERC20RootVaultGovernance.StrategyParams memory params = IERC20RootVaultGovernance(address(_vaultGovernance))
            .strategyParams(thisNft);
        require(lpAmount + balanceOf[msg.sender] <= params.tokenLimitPerAddress, ExceptionsLibrary.LIMIT_OVERFLOW);
        require(lpAmount + supply <= params.tokenLimit, ExceptionsLibrary.LIMIT_OVERFLOW);

        IERC20(primaryToken).safeTransferFrom(msg.sender, address(this), tokenAmounts[0]);

        if (!wasDeposit) {
            _mint(address(0), lpAmount);
            wasDeposit = true;
        } else {
            _mint(msg.sender, lpAmount);
        }

        actualTokenAmounts = _pushIntoGearbox(tokenAmounts[0], vaultOptions);

        emit Deposit(msg.sender, _vaultTokens, actualTokenAmounts, lpAmount);
    }

    uint256 currentEpoch;

    mapping(address => uint256) public primaryTokensToWithdraw;
    mapping(address => uint256) public lpTokensToWithdraw;
    mapping(address => uint256) public withdrawalRequests;
    mapping(address => uint256) public latestRequestEpoch;

    mapping(uint256 => uint256) public epochToPriceForLpTokenD18;

    uint256 totalCurrentEpochLpWitdrawalRequests;
    uint256 totalLpTokensWaitingWithdrawal;
    uint256 lastEpochChangeTimestamp;

    /// @inheritdoc IGearboxRootVault
    function registerWithdrawal(uint256 lpTokenAmount) external returns (uint256 amountRegistered) {
        uint256 userLatestRequestEpoch = latestRequestEpoch[msg.sender];

        if (currentEpoch == userLatestRequestEpoch || userLatestRequestEpoch == 0) {
            uint256 senderBalance = balanceOf[msg.sender] -
                lpTokensToWithdraw[msg.sender] -
                withdrawalRequests[msg.sender];
            if (lpTokenAmount > senderBalance) {
                lpTokenAmount = senderBalance;
            }

            withdrawalRequests[msg.sender] += lpTokenAmount;
            latestRequestEpoch[msg.sender] = currentEpoch;
        } else {
            _processHangingWithdrawal(msg.sender, false);

            uint256 senderBalance = balanceOf[msg.sender] - lpTokensToWithdraw[msg.sender];
            if (lpTokenAmount > senderBalance) {
                lpTokenAmount = senderBalance;
            }

            withdrawalRequests[msg.sender] = lpTokenAmount;
            latestRequestEpoch[msg.sender] = currentEpoch;
        }

        totalCurrentEpochLpWitdrawalRequests += lpTokenAmount;
        emit WithdrawalRegistered(msg.sender, lpTokenAmount);
        return lpTokenAmount;
    }

    /// @inheritdoc IGearboxRootVault
    function cancelWithdrawal(uint256 lpTokenAmount) external returns (uint256 amountRemained) {
        require(latestRequestEpoch[msg.sender] == currentEpoch, ExceptionsLibrary.DISABLED);

        if (withdrawalRequests[msg.sender] > lpTokenAmount) {
            withdrawalRequests[msg.sender] -= lpTokenAmount;
            totalCurrentEpochLpWitdrawalRequests -= lpTokenAmount;
            emit WithdrawalCancelled(msg.sender, lpTokenAmount);
        } else {
            totalCurrentEpochLpWitdrawalRequests -= withdrawalRequests[msg.sender];
            emit WithdrawalCancelled(msg.sender, withdrawalRequests[msg.sender]);
            withdrawalRequests[msg.sender] = 0;
        }

        return withdrawalRequests[msg.sender];
    }

    /// @inheritdoc IGearboxRootVault
    function invokeExecution() public {
        IGearboxVaultGovernance governance = IGearboxVaultGovernance(address(IVault(gearboxVault).vaultGovernance()));
        uint256 withdrawDelay = governance.delayedProtocolParams().withdrawDelay;

        require(lastEpochChangeTimestamp + withdrawDelay <= block.timestamp || isClosed, ExceptionsLibrary.INVARIANT);
        lastEpochChangeTimestamp = block.timestamp;

        (uint256[] memory minTokenAmounts, ) = gearboxVault.tvl();
        _chargeFees(_nft, minTokenAmounts[0], totalSupply - totalLpTokensWaitingWithdrawal);

        uint256 totalAmount = FullMath.mulDiv(
            totalCurrentEpochLpWitdrawalRequests,
            minTokenAmounts[0],
            totalSupply - totalLpTokensWaitingWithdrawal
        );

        uint256[] memory tokenAmounts = new uint256[](1);
        tokenAmounts[0] = totalAmount;
        uint256[] memory pulledAmounts = gearboxVault.pull(address(erc20Vault), _vaultTokens, tokenAmounts, "");
        totalAmount = pulledAmounts[0];

        if (totalCurrentEpochLpWitdrawalRequests > 0) {
            totalLpTokensWaitingWithdrawal += totalCurrentEpochLpWitdrawalRequests;
            epochToPriceForLpTokenD18[currentEpoch] = FullMath.mulDiv(
                totalAmount,
                D18,
                totalCurrentEpochLpWitdrawalRequests
            );
            totalCurrentEpochLpWitdrawalRequests = 0;
        }

        currentEpoch += 1;
    }

    /// @inheritdoc IGearboxRootVault
    function withdraw(address to, bytes[] memory vaultsOptions)
        external
        nonReentrant
        returns (uint256[] memory actualTokenAmounts)
    {
        uint256 userLatestRequestEpoch = latestRequestEpoch[msg.sender];
        if (currentEpoch != userLatestRequestEpoch && userLatestRequestEpoch != 0) {
            _processHangingWithdrawal(msg.sender, true);
        }

        uint256 lpTokensToBurn = lpTokensToWithdraw[msg.sender];
        uint256 primaryTokensToPull = primaryTokensToWithdraw[msg.sender];

        uint256[] memory tokenAmounts = new uint256[](1);
        tokenAmounts[0] = primaryTokensToPull;

        _burn(msg.sender, lpTokensToBurn);
        actualTokenAmounts = _pull(address(this), tokenAmounts, vaultsOptions);
        lpTokensToWithdraw[msg.sender] = 0;
        primaryTokensToWithdraw[msg.sender] = 0;

        totalLpTokensWaitingWithdrawal -= lpTokensToBurn;

        IERC20(primaryToken).safeTransfer(to, actualTokenAmounts[0]);

        emit Withdraw(msg.sender, _vaultTokens, actualTokenAmounts, lpTokensToBurn);
    }

    function shutdown() external {
        _requireAtLeastStrategy();
        require(!isClosed, ExceptionsLibrary.DUPLICATE);
        isClosed = true;
        invokeExecution();
    }

    function reopen() external {
        _requireAtLeastStrategy();
        isClosed = false;
    }

    // -------------------  INTERNAL, VIEW  -------------------

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
        uint256 tvl,
        uint256 supply
    ) internal {
        IERC20RootVaultGovernance vg = IERC20RootVaultGovernance(address(_vaultGovernance));
        uint256 elapsed = block.timestamp - uint256(lastFeeCharge);
        IERC20RootVaultGovernance.DelayedProtocolParams memory delayedProtocolParams = vg.delayedProtocolParams();
        if (elapsed < delayedProtocolParams.managementFeeChargeDelay) {
            return;
        }

        lastFeeCharge = uint64(block.timestamp);
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

        _chargePerformanceFees(supply, tvl, strategyParams.performanceFee, strategyParams.strategyPerformanceTreasury);
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
        uint256 tvl,
        uint256 performanceFee,
        address treasury
    ) internal {
        if ((performanceFee == 0) || (baseSupply == 0)) {
            return;
        }

        uint256 lpPriceD18 = FullMath.mulDiv(tvl, CommonLibrary.D18, baseSupply);
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

    function _processHangingWithdrawal(address addr, bool nullifyRequest) internal {
        uint256 pendingRequest = withdrawalRequests[addr];
        uint256 userLatestRequestEpoch = latestRequestEpoch[addr];
        uint256 tokenAmount = FullMath.mulDiv(pendingRequest, epochToPriceForLpTokenD18[userLatestRequestEpoch], D18);
        primaryTokensToWithdraw[addr] += tokenAmount;
        lpTokensToWithdraw[addr] += pendingRequest;

        if (nullifyRequest) {
            withdrawalRequests[addr] = 0;
            latestRequestEpoch[addr] = 0;
        }
    }

    function _pushIntoGearbox(uint256 amount, bytes memory vaultOptions)
        internal
        returns (uint256[] memory actualTokenAmounts)
    {
        require(_nft != 0, ExceptionsLibrary.INIT);

        uint256[] memory tokenAmounts = new uint256[](1);
        tokenAmounts[0] = amount;

        IERC20(primaryToken).safeIncreaseAllowance(address(gearboxVault), amount);
        actualTokenAmounts = gearboxVault.transferAndPush(address(this), _vaultTokens, tokenAmounts, vaultOptions);
        IERC20(primaryToken).safeApprove(address(gearboxVault), 0);
    }

    // --------------------------  EVENTS  --------------------------

    /// @notice Emitted when management fees are charged
    /// @param treasury Treasury receiver of the fee
    /// @param feeRate Fee percent applied denominated in 10 ** 9
    /// @param amount Amount of lp token minted
    event ManagementFeesCharged(address indexed treasury, uint256 feeRate, uint256 amount);

    event WithdrawalRegistered(address indexed addr, uint256 lpAmountRegistered);

    event WithdrawalCancelled(address indexed addr, uint256 lpAmountCancelled);

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
