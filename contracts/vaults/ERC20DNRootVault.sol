// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "../libraries/external/FullMath.sol";
import "../libraries/ExceptionsLibrary.sol";
import "../interfaces/vaults/IERC20DNRootVaultGovernance.sol";
import "../interfaces/vaults/IERC20DNRootVault.sol";
import "../interfaces/vaults/IUniV3Vault.sol";
import "../interfaces/utils/ILpCallback.sol";
import "../interfaces/oracles/IOracle.sol";
import "../utils/ERC20Token.sol";
import "../interfaces/utils/IERC20RootVaultHelper.sol";

import "./AaveVault.sol";
import "./AggregateVault.sol";

/// @notice Contract that mints and burns LP tokens in exchange for ERC20 liquidity.
contract ERC20DNRootVault is IERC20DNRootVault, ERC20Token, ReentrancyGuard, AggregateVault {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    bytes4 public constant SUPPORTS_INTERFACE_SELECTOR = AaveVault.supportsInterface.selector;
    uint256 public constant Q96 = (1 << 96);

    /// @inheritdoc IERC20DNRootVault
    uint64 public lastFeeCharge;
    /// @inheritdoc IERC20DNRootVault
    uint64 public totalWithdrawnAmountsTimestamp;
    /// @inheritdoc IERC20DNRootVault
    uint256[] public totalWithdrawnAmounts;
    /// @inheritdoc IERC20DNRootVault
    uint256 public lpPriceHighWaterMarkD18;

    EnumerableSet.AddressSet private _depositorsAllowlist;
    IERC20RootVaultHelper public helper;

    bool[][] public isSubvaultAndTokenPositive;

    IUniswapV3Factory public factory;
    uint24[][] public poolFees;

    uint256 public specialToken;

    function tvl()
        public
        view
        override(IVault, AggregateVault)
        returns (uint256[] memory minTokenAmounts, uint256[] memory maxTokenAmounts)
    {
        address[] memory vaultTokens = _vaultTokens;

        bool[][] memory isSubvaultAndTokenPositive_ = isSubvaultAndTokenPositive;

        uint256 subvaultsCount = isSubvaultAndTokenPositive_.length;
        uint256 tokensCount = isSubvaultAndTokenPositive_[0].length;

        int256[] memory signedMinTokenAmounts = new int256[](1);
        int256[] memory signedMaxTokenAmounts = new int256[](1);

        minTokenAmounts = new uint256[](vaultTokens.length);
        maxTokenAmounts = new uint256[](vaultTokens.length);

        for (uint256 i = 0; i < subvaultsCount; ++i) {
            IIntegrationVault subvault = IIntegrationVault(IAggregateVault(address(this)).subvaultAt(i));
            (uint256[] memory minSubvaultTvl, uint256[] memory maxSubvaultTvl) = subvault.tvl();

            address[] memory subvaultTokens = subvault.vaultTokens();
            uint256 subvaultTokenId = 0;
            for (
                uint256 tokenId = 0;
                tokenId < vaultTokens.length && subvaultTokenId < subvaultTokens.length;
                ++tokenId
            ) {
                if (subvaultTokens[subvaultTokenId] == vaultTokens[tokenId]) {
                    if (isSubvaultAndTokenPositive[i][tokenId]) {
                        signedMinTokenAmounts[tokenId] += int256(minSubvaultTvl[subvaultTokenId]);
                        signedMaxTokenAmounts[tokenId] += int256(maxSubvaultTvl[subvaultTokenId]);
                    } else {
                        signedMinTokenAmounts[tokenId] -= int256(maxSubvaultTvl[subvaultTokenId]);
                        signedMaxTokenAmounts[tokenId] -= int256(minSubvaultTvl[subvaultTokenId]);
                    }
                    subvaultTokenId += 1;
                }
            }
        }

        int256 minTvl = signedMinTokenAmounts[specialToken];
        int256 maxTvl = signedMaxTokenAmounts[specialToken];

        for (uint256 i = 0; i < tokensCount; ++i) {
            if (i == specialToken) continue;
            minTvl += _getSpecialTokenAmount(vaultTokens, i, signedMinTokenAmounts[i]);
            maxTvl += _getSpecialTokenAmount(vaultTokens, i, signedMaxTokenAmounts[i]);
        }

        require(minTvl >= 0, ExceptionsLibrary.INVALID_STATE);

        minTokenAmounts[0] = uint256(minTvl);
        maxTokenAmounts[0] = uint256(maxTvl);
    }

    function _getSpecialTokenAmount(
        address[] memory vaultTokens,
        uint256 index,
        int256 amount
    ) internal view returns (int256 expectedAmount) {
        address tokenFrom = vaultTokens[index];
        address tokenTo = vaultTokens[specialToken];

        IUniswapV3Pool poolHere = IUniswapV3Pool(factory.getPool(tokenFrom, tokenTo, poolFees[index][specialToken]));

        (uint256 sqrtPriceX96, , , , , , ) = poolHere.slot0();

        uint256 priceX96 = FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, Q96);

        if (tokenFrom != poolHere.token0()) {
            priceX96 = FullMath.mulDiv(Q96, Q96, priceX96);
        }

        if (amount > 0) {
            return int256(FullMath.mulDiv(uint256(amount), priceX96, Q96));
        } else {
            return -int256(FullMath.mulDiv(uint256(-amount), priceX96, Q96));
        }
    }

    // -------------------  EXTERNAL, VIEW  -------------------
    /// @inheritdoc IERC20DNRootVault
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
        return super.supportsInterface(interfaceId) || type(IERC20DNRootVault).interfaceId == interfaceId;
    }

    // -------------------  EXTERNAL, MUTATING  -------------------
    /// @inheritdoc IERC20DNRootVault
    function addDepositorsToAllowlist(address[] calldata depositors) external {
        _requireAtLeastStrategy();
        for (uint256 i = 0; i < depositors.length; i++) {
            _depositorsAllowlist.add(depositors[i]);
        }
    }

    /// @inheritdoc IERC20DNRootVault
    function removeDepositorsFromAllowlist(address[] calldata depositors) external {
        _requireAtLeastStrategy();
        for (uint256 i = 0; i < depositors.length; i++) {
            _depositorsAllowlist.remove(depositors[i]);
        }
    }

    function setFee(
        uint256 indexA,
        uint256 indexB,
        uint24 fee
    ) public {
        require((fee == 100 || fee == 500 || fee == 3000 || fee == 10000), ExceptionsLibrary.INVARIANT);
        _requireAdmin();
        poolFees[indexA][indexB] = fee;
    }

    /// @inheritdoc IERC20DNRootVault
    function initialize(
        uint256 nft_,
        address[] memory vaultTokens_,
        address strategy_,
        uint256[] memory subvaultNfts_,
        IERC20RootVaultHelper helper_,
        IUniswapV3Factory factory_,
        bool[][] memory isSubvaultAndTokenPositive_,
        uint256 specialToken_
    ) external {
        _initialize(vaultTokens_, nft_, strategy_, subvaultNfts_);
        _initERC20(_getTokenName(bytes("Mellow Lp Token "), nft_), _getTokenName(bytes("MLP"), nft_));

        require(subvaultNfts_.length == isSubvaultAndTokenPositive_.length, ExceptionsLibrary.INVALID_LENGTH);
        for (uint256 i = 0; i < isSubvaultAndTokenPositive_.length; ++i) {
            require(vaultTokens_.length == isSubvaultAndTokenPositive_[i].length, ExceptionsLibrary.INVALID_LENGTH);
        }

        isSubvaultAndTokenPositive = isSubvaultAndTokenPositive_;

        uint256 len = vaultTokens_.length;

        specialToken = specialToken_;

        totalWithdrawnAmounts = new uint256[](len);
        lastFeeCharge = uint64(block.timestamp);
        helper = helper_;

        factory = factory_;
    }

    /// @inheritdoc IERC20DNRootVault
    function deposit(
        uint256 amount,
        uint256 minLpTokens,
        bytes memory vaultOptions
    ) external virtual nonReentrant returns (uint256 actualAmount) {
        address vaultGovernance = address(_vaultGovernance);

        require(
            !IERC20DNRootVaultGovernance(vaultGovernance).operatorParams().disableDeposit,
            ExceptionsLibrary.FORBIDDEN
        );

        uint256 thisNft = _nft;

        if (totalSupply == 0) {
            uint256 pullExistentialsForToken = _pullExistentials[specialToken];
            require(amount >= 10 * pullExistentialsForToken, ExceptionsLibrary.LIMIT_UNDERFLOW);
            require(amount <= pullExistentialsForToken * pullExistentialsForToken, ExceptionsLibrary.LIMIT_OVERFLOW);
        }

        IERC20DNRootVaultGovernance.DelayedStrategyParams memory delayedStrategyParams = IERC20DNRootVaultGovernance(
            vaultGovernance
        ).delayedStrategyParams(thisNft);
        require(
            !delayedStrategyParams.privateVault || _depositorsAllowlist.contains(msg.sender),
            ExceptionsLibrary.FORBIDDEN
        );

        if (totalSupply > 0) {
            if (delayedStrategyParams.depositCallbackAddress != address(0)) {
                ILpCallback(delayedStrategyParams.depositCallbackAddress).depositCallback("");
            }
        }

        (, uint256[] memory maxTvl) = tvl();
        _chargeFees(thisNft, maxTvl[0], totalSupply);

        uint256 supply = totalSupply;
        uint256 lpAmount;

        if (supply == 0) {
            lpAmount = amount;
        } else {
            uint256 tvlValue = maxTvl[0];
            lpAmount = FullMath.mulDiv(supply, amount, tvlValue);
            amount = FullMath.mulDiv(tvlValue, lpAmount, supply);
        }

        require(lpAmount >= minLpTokens, ExceptionsLibrary.LIMIT_UNDERFLOW);
        require(lpAmount != 0, ExceptionsLibrary.VALUE_ZERO);
        IERC20DNRootVaultGovernance.StrategyParams memory params = IERC20DNRootVaultGovernance(vaultGovernance)
            .strategyParams(thisNft);
        require(
            lpAmount + balanceOf[msg.sender] <= params.tokenLimitPerAddress && lpAmount + supply <= params.tokenLimit,
            ExceptionsLibrary.LIMIT_OVERFLOW
        );

        IERC20(_vaultTokens[specialToken]).safeTransferFrom(msg.sender, address(this), amount);

        if (supply == 0) {
            _mint(address(0), lpAmount);
        } else {
            _mint(msg.sender, lpAmount);
        }

        uint256[] memory tokenAmounts = new uint256[](3);
        tokenAmounts[specialToken] = amount;

        uint256[] memory actualTokenAmounts = _push(tokenAmounts, vaultOptions);
        actualAmount = actualTokenAmounts[specialToken];

        if (supply > 0) {
            if (delayedStrategyParams.depositCallbackAddress != address(0)) {
                ILpCallback(delayedStrategyParams.depositCallbackAddress).depositCallback("");
            }
        }

        emit Deposit(msg.sender, _vaultTokens, actualAmount, lpAmount);
    }

    /// @inheritdoc IERC20DNRootVault
    function withdraw(
        address to,
        uint256 lpTokenAmount,
        uint256 minTokenAmount,
        bytes[] memory vaultsOptions
    ) external nonReentrant returns (uint256 actualAmount) {
        uint256 supply = totalSupply;
        require(supply > 0, ExceptionsLibrary.VALUE_ZERO);

        uint256[] memory tokenAmounts = new uint256[](_vaultTokens.length);
        (uint256[] memory minTvl, ) = tvl();
        _chargeFees(_nft, minTvl[0], supply);
        supply = totalSupply;
        uint256 balance = balanceOf[msg.sender];
        if (lpTokenAmount > balance) {
            lpTokenAmount = balance;
        }

        {
            uint256 thisNft = _nft;
            IERC20DNRootVaultGovernance.DelayedStrategyParams
                memory delayedStrategyParams = IERC20DNRootVaultGovernance(address(_vaultGovernance))
                    .delayedStrategyParams(thisNft);

            uint256 shareX96 = FullMath.mulDiv(lpTokenAmount, Q96, supply);

            bytes memory q = abi.encode(shareX96);

            if (delayedStrategyParams.withdrawCallbackAddress != address(0)) {
                ILpCallback(delayedStrategyParams.withdrawCallbackAddress).withdrawCallback(q);
            }
        }

        tokenAmounts[specialToken] = FullMath.mulDiv(lpTokenAmount, minTvl[0], supply);

        address erc20Vault = IAggregateVault(address(this)).subvaultAt(0);
        uint256 erc20VaultBalance = IERC20(_vaultTokens[specialToken]).balanceOf(erc20Vault);

        if (erc20VaultBalance < tokenAmounts[specialToken]) {
            tokenAmounts[specialToken] = erc20VaultBalance;
        }

        require(tokenAmounts[specialToken] >= minTokenAmount, ExceptionsLibrary.LIMIT_UNDERFLOW);
        actualAmount = tokenAmounts[specialToken];

        _pull(to, tokenAmounts, vaultsOptions);

        _updateWithdrawnAmounts(actualAmount);
        _burn(msg.sender, lpTokenAmount);

        emit Withdraw(msg.sender, _vaultTokens, actualAmount, lpTokenAmount);
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

    function _requireAdmin() internal view {
        uint256 nft_ = _nft;
        IVaultGovernance.InternalParams memory internalParams = _vaultGovernance.internalParams();
        require(
            (internalParams.protocolGovernance.isAdmin(msg.sender) ||
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
        uint256 tvlValue,
        uint256 supply
    ) internal {
        IERC20DNRootVaultGovernance vg = IERC20DNRootVaultGovernance(address(_vaultGovernance));
        uint256 elapsed = block.timestamp - uint256(lastFeeCharge);
        IERC20DNRootVaultGovernance.DelayedProtocolParams memory delayedProtocolParams = vg.delayedProtocolParams();
        if (elapsed < delayedProtocolParams.managementFeeChargeDelay || supply == 0) {
            return;
        }

        lastFeeCharge = uint64(block.timestamp);
        IERC20DNRootVaultGovernance.DelayedStrategyParams memory strategyParams = vg.delayedStrategyParams(thisNft);
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
            tvlValue,
            strategyParams.performanceFee,
            strategyParams.strategyPerformanceTreasury
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
        uint256 tvlValue,
        uint256 performanceFee,
        address treasury
    ) internal {
        if ((performanceFee == 0) || (baseSupply == 0)) {
            return;
        }

        uint256 lpPriceD18 = FullMath.mulDiv(tvlValue, CommonLibrary.D18, baseSupply);
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

    function _updateWithdrawnAmounts(uint256 amount) internal {
        uint256[] memory withdrawn = new uint256[](_vaultTokens.length);
        uint64 timestamp = uint64(block.timestamp);
        IProtocolGovernance protocolGovernance = _vaultGovernance.internalParams().protocolGovernance;
        if (timestamp != totalWithdrawnAmountsTimestamp) {
            totalWithdrawnAmountsTimestamp = timestamp;
        } else {
            for (uint256 i = 0; i < withdrawn.length; i++) {
                withdrawn[i] = totalWithdrawnAmounts[i];
            }
        }

        withdrawn[specialToken] += amount;
        require(
            withdrawn[specialToken] <= protocolGovernance.withdrawLimit(_vaultTokens[specialToken]),
            ExceptionsLibrary.LIMIT_OVERFLOW
        );

        for (uint256 i = 0; i < withdrawn.length; ++i) {
            totalWithdrawnAmounts[i] = withdrawn[i];
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
    /// @param actualAmount Token amount deposited
    /// @param lpTokenMinted LP tokens received by the liquidity provider
    event Deposit(address indexed from, address[] tokens, uint256 actualAmount, uint256 lpTokenMinted);

    /// @notice Emitted when liquidity is withdrawn
    /// @param from The source address for the liquidity
    /// @param tokens ERC20 tokens withdrawn
    /// @param actualAmount Token amount withdrawn
    /// @param lpTokenBurned LP tokens burned from the liquidity provider
    event Withdraw(address indexed from, address[] tokens, uint256 actualAmount, uint256 lpTokenBurned);

    /// @notice Emitted when callback in deposit failed
    /// @param reason Error reason
    event DepositCallbackLog(string reason);

    /// @notice Emitted when callback in withdraw failed
    /// @param reason Error reason
    event WithdrawCallbackLog(string reason);
}
