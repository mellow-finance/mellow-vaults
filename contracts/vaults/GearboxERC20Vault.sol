// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import "./IntegrationVault.sol";

import "../libraries/ExceptionsLibrary.sol";
import "../interfaces/vaults/IERC20Vault.sol";
import "../interfaces/vaults/IGearboxVault.sol";
import "../interfaces/external/gearbox/helpers/curve/ICurvePool.sol";

/// @notice Vault that stores ERC20 tokens.
contract GearboxERC20Vault is IERC20Vault, IntegrationVault {

    uint256 public constant EMPTY = 0;
    uint256 public constant PARTIAL = 1; 
    uint256 public constant FULL = 2;  

    uint256 public constant D9 = 10**9;
    uint256 public constant Q96 = 2**96;

    uint256 public constant MAX_LENGTH = 126;

    using SafeERC20 for IERC20;

    address[] public subvaultsList;
    uint256[] public limitsList;
    
    uint256 public subvaultsStatusMask;
    uint256 public totalDeposited;

    address public curveAdapter;
    address public convexAdapter;

    uint256 totalLimit;

    function adjustAllPositions() external {
        require(_isApprovedOrOwner(msg.sender), ExceptionsLibrary.FORBIDDEN);

        for (uint256 i = 0; i < subvaultsList.length; ++i) {
            IGearboxVault(subvaultsList[i]).adjustPosition();
        }
    }

    function addSubvault(address addr, uint256 limit) external {

        require(_isApprovedOrOwner(msg.sender), ExceptionsLibrary.FORBIDDEN);

        IGearboxVault vault = IGearboxVault(addr);

        require(subvaultsList.length < MAX_LENGTH, ExceptionsLibrary.INVALID_LENGTH);

        uint256 marginalFactorD9 = vault.marginalFactorD9();
        uint256 supposedBorrow = FullMath.mulDiv(limit, marginalFactorD9 - D9, D9);
        (uint256 minBorrow, uint256 maxBorrow) = vault.creditFacade().limits();
        require(supposedBorrow > minBorrow && supposedBorrow < maxBorrow, ExceptionsLibrary.INVALID_VALUE);

        subvaultsList.push(addr);
        limitsList.push(limit);

        totalLimit += limit;

        _makeSorted();
    }

    function changeLimit(uint256 index, uint256 limit) public {
        require(_isApprovedOrOwner(msg.sender), ExceptionsLibrary.FORBIDDEN);
        require(index < subvaultsList.length, ExceptionsLibrary.INVALID_TARGET);
        uint256 status = (subvaultsStatusMask & (3 << (2 * index))) >> (2 * index);
        require(status == EMPTY || msg.sender == address(this), ExceptionsLibrary.FORBIDDEN);

        IGearboxVault vault = IGearboxVault(subvaultsList[index]);

        uint256 marginalFactorD9 = vault.marginalFactorD9();
        uint256 supposedBorrow = FullMath.mulDiv(limit, marginalFactorD9 - D9, D9);
        (uint256 minBorrow, uint256 maxBorrow) = vault.creditFacade().limits();
        require(supposedBorrow > minBorrow && supposedBorrow < maxBorrow, ExceptionsLibrary.INVALID_VALUE);

        totalLimit += limit;
        totalLimit -= limitsList[index];

        limitsList[index] = limit;
        
        _makeSorted();
    }

    function changeLimitAndFactor(uint256 index, uint256 limit, uint256 factor) external {
        require(_isApprovedOrOwner(msg.sender), ExceptionsLibrary.FORBIDDEN);

        IGearboxVault vault = IGearboxVault(subvaultsList[index]);
        vault.updateTargetMarginalFactor(factor);

        GearboxERC20Vault(address(this)).changeLimit(index, limit);
    }

    function _makeSorted() internal {
        uint256 len = subvaultsList.length;
        for (uint256 i = 1; i < len; ++i) {
            if (limitsList[i] < limitsList[i - 1]) {
                (limitsList[i - 1], limitsList[i]) = (limitsList[i], limitsList[i - 1]);
                (subvaultsList[i - 1], subvaultsList[i]) = (subvaultsList[i], subvaultsList[i - 1]);
            }
        }

        for (uint256 i = len; i > 1; --i) {
            if (limitsList[i - 1] < limitsList[i - 2]) {
                (limitsList[i - 1], limitsList[i - 2]) = (limitsList[i - 2], limitsList[i - 1]);
                (subvaultsList[i - 1], subvaultsList[i - 2]) = (subvaultsList[i - 2], subvaultsList[i - 1]);
            }
        }
    }

    function _getTvl(address vault) internal {
        (uint256[] memory vaultTvls, ) = IGearboxVault.tvl();
        return vaultTvls[0];
    }

    function _depositTo(uint256 index, uint256 mask, uint256 amount, uint256 status) internal returns (uint256, uint256) {

        IGearboxVault vault = IGearboxVault(subvaultsList[index]);

        if (status == EMPTY) {
            (uint256 minBorrowingLimit, ) = vault.creditFacade().limits();
            uint256 minimalNecessaryAmount = FullMath.mulDiv(minBorrowingLimit, D9, (vault.marginalFactorD9() - D9)) + 1;
            if (amount < minimalNecessaryAmount) {
                return (mask, amount);
            }
        }

        uint256 vaultTvl = _getTvl(subvaultsList[index]);
        uint256 limit = limitsList.at(index);

        if (vaultTvl >= limit) {
            return (mask, amount);
        }

        uint256 toDeposit = limit - vaultTvl;
        IERC20(_vaultTokens[0]).safeTransfer(address(vault), toDeposit);

        if (status == EMPTY) {
            vault.openCreditAccount(curveAdapter, convexAdapter);
        }

        vault.adjustPosition();
    }

    function distributeDeposits() external {

        require(_isApprovedOrOwner(msg.sender), ExceptionsLibrary.FORBIDDEN);
        if (totalDeposited == 0) {
            return;
        }

        uint256 vaultCount = subvaultsList.length;
        uint256 mask = subvaultsStatusMask;
        uint256 remainingDeposited = totalDeposited;

        uint256 specialVault = 0;

        for (uint256 i = 0; i < vaultCount; ++i) {
            uint256 status = (mask & (3 << (2 * i))) >> (2 * i);
            if (status == PARTIAL) {
                specialVault = i + 1;
            }
        }

        if (specialVault != 0) {
            (mask, remainingDeposited) = _depositTo(specialVault - 1, mask, remainingDeposited, PARTIAL);
        }

        for (uint256 i = 0; i < vaultCount && totalDeposited > 0; ++i) {
            uint256 status = (mask & (3 << (2 * i))) >> (2 * i);
            if (status == EMPTY) {
                (mask, remainingDeposited) = _depositTo(i, mask, remainingDeposited, status);
            }
        }

        totalDeposited = remainingDeposited;
        subvaultsStatusMask = mask;
    }

    function withdraw(uint256 tvlBefore, uint256 shareD) external returns (uint256 withdrawn) {
        uint256 vaultCount = subvaultsList.length;

        uint256 toWithdraw = FullMath.mulDiv(tvlBefore, shareD, D9);
        uint256 mask = subvaultsStatusMask;

        if (totalDeposited > toWithdraw) {
            totalDeposited -= toWithdraw;
            return toWithdraw;
        }

        toWithdraw -= totalDeposited;

        totalDeposited = 0;

        for (uint256 helpI = 0; helpI < 2 * vaultCount && toWithdraw > 0; ++helpI) {

            uint256 i = helpI;
            if (helpI >= vaultCount) {
                i = 2*vaultCount - helpI - 1;
            }

            if (limitsList[i] < toWithdraw) {
                continue;
            }
            uint256 status = (mask & (3 << (2 * i))) >> (2 * i);
            if (status == PARTIAL) {
                uint256 partialVaultTvl = _getTvl(subvaultsList[i]);
                if (partialVaultTvl < toWithdraw) {
                    continue;
                }
                mask ^= (1 << (2 * i));
            }
            mask ^= (1 << (2 * i + 1));
            IGearboxVault(subvaultsList[i]).closeCreditAccount();

            uint256 vaultTvl = _getTvl(subvaultsList[i]);

            uint256[] tokenAmounts = new uint256[](1);
            tokenAmounts[0] = vaultTvl;
            IGearboxVault(subvaultsList[i]).pull(address(this), _vaultTokens, tokenAmounts, "");

            if (vaultTvl <= toWithdraw) {
                toWithdraw -= vaultTvl;
            }

            else {
                toWithdraw = 0;
            }
        }

        uint256 newTvl = tvlBefore; ////////// CHANGE!!!
        uint256 loss = 0;

        if (newTvl < tvlBefore) {
            loss = tvlBefore - newTvl;
        }

        subvaultsStatusMask = mask;

        return FullMath.mulDiv(tvlBefore, shareD, D9) - loss;
    }

    function setAdapters(address curveAdapter_, address convexAdapter_) external {
        require(_isApprovedOrOwner(msg.sender), ExceptionsLibrary.FORBIDDEN);

        curveAdapter = curveAdapter_;
        convexAdapter = convexAdapter_;
    }

    // -------------------  EXTERNAL, VIEW  -------------------

    /// @inheritdoc IVault
    function tvl() public view returns (uint256[] memory minTokenAmounts, uint256[] memory maxTokenAmounts) {
        address[] memory tokens = _vaultTokens;
        uint256 len = tokens.length;
        minTokenAmounts = new uint256[](len);
        for (uint256 i = 0; i < len; ++i) {
            minTokenAmounts[i] = IERC20(tokens[i]).balanceOf(address(this));
        }
        maxTokenAmounts = minTokenAmounts;
    }

    // -------------------  EXTERNAL, MUTATING  -------------------
    /// @inheritdoc IERC20Vault
    function initialize(uint256 nft_, address[] memory vaultTokens_) external {
        _initialize(vaultTokens_, nft_);
    }

    // -------------------  INTERNAL, VIEW  -----------------------
    function _isReclaimForbidden(address token) internal view override returns (bool) {
        uint256 len = _vaultTokens.length;
        for (uint256 i = 0; i < len; ++i) {
            if (token == _vaultTokens[i]) {
                return true;
            }
        }
        return false;
    }

    // -------------------  INTERNAL, MUTATING  -------------------

    function _push(uint256[] memory tokenAmounts, bytes memory)
        internal
        pure
        override
        returns (uint256[] memory actualTokenAmounts)
    {
        // no-op, tokens are already on balance
        return tokenAmounts;
    }

    function _pull(
        address to,
        uint256[] memory tokenAmounts,
        bytes memory options
    ) internal override returns (uint256[] memory actualTokenAmounts) {
        actualTokenAmounts = new uint256[](tokenAmounts.length);
        uint256[] memory pushTokenAmounts = new uint256[](tokenAmounts.length);
        address[] memory tokens = _vaultTokens;
        IVaultRegistry registry = _vaultGovernance.internalParams().registry;
        address owner = registry.ownerOf(_nft);

        for (uint256 i = 0; i < tokenAmounts.length; ++i) {
            IERC20 vaultToken = IERC20(tokens[i]);
            uint256 balance = vaultToken.balanceOf(address(this));
            uint256 amount = tokenAmounts[i] < balance ? tokenAmounts[i] : balance;
            IERC20(tokens[i]).safeTransfer(to, amount);
            actualTokenAmounts[i] = amount;
            if (owner != to) {
                // this will equal to amounts pulled + any accidental prior balances on `to`;
                pushTokenAmounts[i] = IERC20(tokens[i]).balanceOf(to);
            }
        }
        if (owner != to) {
            // if we pull as a strategy, make sure everything is pushed
            IIntegrationVault(to).push(tokens, pushTokenAmounts, options);
            // any accidental prior balances + push leftovers
            uint256[] memory reclaimed = IIntegrationVault(to).reclaimTokens(tokens);
            for (uint256 i = 0; i < tokenAmounts.length; i++) {
                // equals to exactly how much is pushed
                actualTokenAmounts[i] = actualTokenAmounts[i] >= reclaimed[i]
                    ? actualTokenAmounts[i] - reclaimed[i]
                    : 0;
            }
        }
    }

    /// @inheritdoc IntegrationVault
    function supportsInterface(bytes4 interfaceId) public view override(IERC165, IntegrationVault) returns (bool) {
        return super.supportsInterface(interfaceId) || (interfaceId == type(IERC20Vault).interfaceId);
    }
}
