// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "../libraries/external/FullMath.sol";
import "../libraries/ExceptionsLibrary.sol";
import "../interfaces/vaults/IERC20RootVaultGovernance.sol";
import "../interfaces/vaults/IERC20RootVault.sol";
import "../interfaces/vaults/IUniV3Vault.sol";
import "../interfaces/utils/ILpCallback.sol";
import "../utils/ERC20Token.sol";
import "../interfaces/utils/IERC20RootVaultHelper.sol";

import "./AaveVault.sol";
import "./AggregateVault.sol";

/// @notice Contract that mints and burns LP tokens in exchange for ERC20 liquidity.
contract ERC20DNRootVault is IERC20RootVault, ERC20Token, ReentrancyGuard, AggregateVault {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    bytes4 public constant SUPPORTS_INTERFACE_SELECTOR = AaveVault.supportsInterface.selector;
    uint256 public constant Q96 = (1 << 96);

    /// @inheritdoc IERC20RootVault
    uint64 public lastFeeCharge;
    /// @inheritdoc IERC20RootVault
    uint64 public totalWithdrawnAmountsTimestamp;
    /// @inheritdoc IERC20RootVault
    uint256[] public totalWithdrawnAmounts;
    /// @inheritdoc IERC20RootVault
    uint256 public lpPriceHighWaterMarkD18;
    EnumerableSet.AddressSet private _depositorsAllowlist;
    IERC20RootVaultHelper public helper;

    function tvl()
        public
        view
        override(IVault, AggregateVault)
        returns (uint256[] memory minTokenAmounts, uint256[] memory maxTokenAmounts)
    {
        minTokenAmounts = new uint256[](2);
        maxTokenAmounts = new uint256[](2);

        int256 totalToken1TvlMin = 0;
        int256 totalToken1TvlMax = 0;

        for (uint256 i = 0; i < 3; ++i) {
            (uint256[] memory minSubvaultTvl, uint256[] memory maxSubvaultTvl) = IIntegrationVault(
                IAggregateVault(address(this)).subvaultAt(i)
            ).tvl();
            minTokenAmounts[0] += minSubvaultTvl[0];
            maxTokenAmounts[0] += maxSubvaultTvl[0];
            if (i == 2) {
                totalToken1TvlMax -= int256(minSubvaultTvl[1]);
                totalToken1TvlMin -= int256(maxSubvaultTvl[1]);
            } else {
                totalToken1TvlMin += int256(minSubvaultTvl[1]);
                totalToken1TvlMax += int256(maxSubvaultTvl[1]);
            }
        }

        if (totalToken1TvlMin < 0) {
            minTokenAmounts[0] -= _getZeroTokenAmount(uint256(-totalToken1TvlMin));
        } else {
            minTokenAmounts[0] += _getZeroTokenAmount(uint256(totalToken1TvlMin));
        }

        if (totalToken1TvlMax < 0) {
            maxTokenAmounts[0] -= _getZeroTokenAmount(uint256(-totalToken1TvlMax));
        } else {
            maxTokenAmounts[0] += _getZeroTokenAmount(uint256(totalToken1TvlMax));
        }
    }

    function _getZeroTokenAmount(uint256 amount) internal view returns (uint256 expectedAmount) {
        IUniswapV3Pool pool = IUniswapV3Pool(IUniV3Vault(IAggregateVault(address(this)).subvaultAt(1)).pool());

        (uint160 sqrtPriceX96, , , , , , ) = pool.slot0();
        uint256 priceX96 = FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, Q96);

        if (_vaultTokens[0] == pool.token1()) {
            expectedAmount = FullMath.mulDiv(amount, priceX96, Q96);
        } else {
            expectedAmount = FullMath.mulDiv(amount, Q96, priceX96);
        }
    }

    // -------------------  EXTERNAL, VIEW  -------------------
    /// @inheritdoc IERC20RootVault
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
        return super.supportsInterface(interfaceId) || type(IERC20RootVault).interfaceId == interfaceId;
    }

    // -------------------  EXTERNAL, MUTATING  -------------------
    /// @inheritdoc IERC20RootVault
    function addDepositorsToAllowlist(address[] calldata depositors) external {
        _requireAtLeastStrategy();
        for (uint256 i = 0; i < depositors.length; i++) {
            _depositorsAllowlist.add(depositors[i]);
        }
    }

    /// @inheritdoc IERC20RootVault
    function removeDepositorsFromAllowlist(address[] calldata depositors) external {
        _requireAtLeastStrategy();
        for (uint256 i = 0; i < depositors.length; i++) {
            _depositorsAllowlist.remove(depositors[i]);
        }
    }

    /// @inheritdoc IERC20RootVault
    function initialize(
        uint256 nft_,
        address[] memory vaultTokens_,
        address strategy_,
        uint256[] memory subvaultNfts_,
        IERC20RootVaultHelper helper_
    ) external {
        _initialize(vaultTokens_, nft_, strategy_, subvaultNfts_);
        _initERC20(_getTokenName(bytes("Mellow Lp Token "), nft_), _getTokenName(bytes("MLP"), nft_));
        require(vaultTokens_.length == 2, ExceptionsLibrary.INVALID_LENGTH);
        {
            address aaveVault = _vaultGovernance.internalParams().registry.vaultForNft(subvaultNfts_[2]);
            (, bytes memory returndata) = aaveVault.call{value: 0}(
                abi.encodePacked(SUPPORTS_INTERFACE_SELECTOR, abi.encode(type(IAaveVault).interfaceId))
            );
            bool ifSupports = abi.decode(returndata, (bool));
            require(ifSupports, ExceptionsLibrary.INVARIANT);
        }
        uint256 len = vaultTokens_.length;
        totalWithdrawnAmounts = new uint256[](len);
        lastFeeCharge = uint64(block.timestamp);
        helper = helper_;
    }

    /// @inheritdoc IERC20RootVault
    function deposit(
        uint256[] memory tokenAmounts,
        uint256 minLpTokens,
        bytes memory vaultOptions
    ) external virtual nonReentrant returns (uint256[] memory actualTokenAmounts) {
        address vaultGovernance = address(_vaultGovernance);
        tokenAmounts[1] = 0;
        require(
            !IERC20RootVaultGovernance(vaultGovernance).operatorParams().disableDeposit,
            ExceptionsLibrary.FORBIDDEN
        );

        uint256 thisNft = _nft;

        if (totalSupply == 0) {
            uint256 pullExistentialsForToken = _pullExistentials[0];
            require(tokenAmounts[0] >= 10 * pullExistentialsForToken, ExceptionsLibrary.LIMIT_UNDERFLOW);
            require(
                tokenAmounts[0] <= pullExistentialsForToken * pullExistentialsForToken,
                ExceptionsLibrary.LIMIT_OVERFLOW
            );
        }

        IERC20RootVaultGovernance.DelayedStrategyParams memory delayedStrategyParams = IERC20RootVaultGovernance(
            vaultGovernance
        ).delayedStrategyParams(thisNft);
        require(
            !delayedStrategyParams.privateVault || _depositorsAllowlist.contains(msg.sender),
            ExceptionsLibrary.FORBIDDEN
        );

        (, uint256[] memory maxTvl) = tvl();
        _chargeFees(thisNft, maxTvl[0], totalSupply);

        uint256 supply = totalSupply;
        uint256 lpAmount;

        if (supply == 0) {
            lpAmount = tokenAmounts[0];
        } else {
            uint256 tvlValue = maxTvl[0];
            lpAmount = FullMath.mulDiv(supply, tokenAmounts[0], tvlValue);
            tokenAmounts[0] = FullMath.mulDiv(tvlValue, lpAmount, supply);
        }

        require(lpAmount >= minLpTokens, ExceptionsLibrary.LIMIT_UNDERFLOW);
        require(lpAmount != 0, ExceptionsLibrary.VALUE_ZERO);
        IERC20RootVaultGovernance.StrategyParams memory params = IERC20RootVaultGovernance(vaultGovernance)
            .strategyParams(thisNft);
        require(lpAmount + balanceOf[msg.sender] <= params.tokenLimitPerAddress, ExceptionsLibrary.LIMIT_OVERFLOW);
        require(lpAmount + supply <= params.tokenLimit, ExceptionsLibrary.LIMIT_OVERFLOW);

        IERC20(_vaultTokens[0]).safeTransferFrom(msg.sender, address(this), tokenAmounts[0]);

        if (supply == 0) {
            _mint(address(0), lpAmount);
        } else {
            _mint(msg.sender, lpAmount);
        }

        actualTokenAmounts = _push(tokenAmounts, vaultOptions);

        if (supply > 0) {
            uint256 shareX96 = FullMath.mulDiv(lpAmount, Q96, supply);

            bytes memory q = abi.encode(shareX96);

            if (delayedStrategyParams.depositCallbackAddress != address(0)) {
                ILpCallback(delayedStrategyParams.depositCallbackAddress).depositCallback(q);
            }
        }

        emit Deposit(msg.sender, _vaultTokens, actualTokenAmounts, lpAmount);
    }

    /// @inheritdoc IERC20RootVault
    function withdraw(
        address to,
        uint256 lpTokenAmount,
        uint256[] memory minTokenAmounts,
        bytes[] memory vaultsOptions
    ) external nonReentrant returns (uint256[] memory actualTokenAmounts) {
        uint256 supply = totalSupply;
        require(supply > 0, ExceptionsLibrary.VALUE_ZERO);
        require(minTokenAmounts[1] == 0, ExceptionsLibrary.INVALID_VALUE);

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
            IERC20RootVaultGovernance.DelayedStrategyParams memory delayedStrategyParams = IERC20RootVaultGovernance(
                address(_vaultGovernance)
            ).delayedStrategyParams(thisNft);

            uint256 shareX96 = FullMath.mulDiv(lpTokenAmount, Q96, supply);

            bytes memory q = abi.encode(shareX96);

            if (delayedStrategyParams.withdrawCallbackAddress != address(0)) {
                ILpCallback(delayedStrategyParams.withdrawCallbackAddress).withdrawCallback(q);
            }
        }

        tokenAmounts[0] = FullMath.mulDiv(lpTokenAmount, minTvl[0], supply);
        address erc20Vault = IAggregateVault(address(this)).subvaultAt(0);
        uint256 erc20VaultBalance = IERC20(_vaultTokens[0]).balanceOf(erc20Vault);

        if (erc20VaultBalance < tokenAmounts[0]) {
            tokenAmounts[0] = erc20VaultBalance;
        }

        _pull(to, tokenAmounts, vaultsOptions);

        _updateWithdrawnAmounts(actualTokenAmounts);
        _burn(msg.sender, lpTokenAmount);

        emit Withdraw(msg.sender, _vaultTokens, actualTokenAmounts, lpTokenAmount);
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
        uint256 tvlValue,
        uint256 supply
    ) internal {
        IERC20RootVaultGovernance vg = IERC20RootVaultGovernance(address(_vaultGovernance));
        uint256 elapsed = block.timestamp - uint256(lastFeeCharge);
        IERC20RootVaultGovernance.DelayedProtocolParams memory delayedProtocolParams = vg.delayedProtocolParams();
        if (elapsed < delayedProtocolParams.managementFeeChargeDelay || supply == 0) {
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

        _chargePerformanceFees(supply, tvlValue, strategyParams.performanceFee, strategyParams.strategyPerformanceTreasury);
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
