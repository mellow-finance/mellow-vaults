// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./libraries/Common.sol";
import "./interfaces/IVault.sol";
import "./interfaces/IProtocolGovernance.sol";
import "./interfaces/ILpIssuer.sol";
import "./DefaultAccessControl.sol";
import "./LpIssuerGovernance.sol";

contract LpIssuer is ILpIssuer, ERC20 {
    using SafeERC20 for IERC20;
    uint256 private _subvaultNft;
    IVaultGovernance internal _vaultGovernance;
    address[] internal _vaultTokens;
    mapping(address => bool) internal _vaultTokensIndex;

    /// @notice Creates a new contract
    /// @dev All subvault nfts must be owned by this vault before
    /// @param vaultGovernance_ Reference to VaultGovernance for this vault
    /// @param vaultTokens_ ERC20 tokens under Vault management
    /// @param name_ Name of the ERC-721 token
    /// @param symbol_ Symbol of the ERC-721 token
    constructor(
        IVaultGovernance vaultGovernance_,
        address[] memory vaultTokens_,
        string memory name_,
        string memory symbol_
    ) ERC20(name_, symbol_) {
        require(Common.isSortedAndUnique(vaultTokens_), "SAU");
        _vaultGovernance = vaultGovernance_;
        _vaultTokens = vaultTokens_;
        for (uint256 i = 0; i < vaultTokens_.length; i++) {
            _vaultTokensIndex[vaultTokens_[i]] = true;
        }
    }

    /// @inheritdoc ILpIssuer
    function subvaultNft() external view returns (uint256) {
        return _subvaultNft;
    }

    /// @notice Deposit tokens into LpIssuer
    /// @param tokenAmounts Amounts of tokens to push
    /// @param optimized Whether to use gas optimization or not. When `true` the call can have some gas cost reduction
    /// but the operation is not guaranteed to succeed. When `false` the gas cost could be higher but the operation is guaranteed to succeed.
    /// @param options Additional options that could be needed for some vaults. E.g. for Uniswap this could be `deadline` param.
    function deposit(
        uint256[] calldata tokenAmounts,
        bool optimized,
        bytes memory options
    ) external {
        require(_subvaultNft > 0, "INIT");
        for (uint256 i = 0; i < _tokens.length; i++) {
            IERC20(_tokens[i]).safeTransferFrom(msg.sender, address(_subvault()), tokenAmounts[i]);
        }
        uint256[] memory tvl = _subvault().tvl();
        uint256[] memory actualTokenAmounts = _subvault().push(_tokens, tokenAmounts, optimized, options);
        uint256 amountToMint;
        if (totalSupply() == 0) {
            for (uint256 i = 0; i < _tokens.length; i++) {
                // TODO: check if there could be smth better
                if (actualTokenAmounts[i] > amountToMint) {
                    amountToMint = actualTokenAmounts[i]; // some number correlated to invested assets volume
                }
            }
        }
        for (uint256 i = 0; i < _tokens.length; i++) {
            if (tvl[i] > 0) {
                uint256 newMint = (actualTokenAmounts[i] * totalSupply()) / tvl[i];
                // TODO: check this algo. The assumption is that everything is rounded down.
                // So that max token has the least error. Think about the case when one token is dust.
                if (newMint > amountToMint) {
                    amountToMint = newMint;
                }
            }
            if (tokenAmounts[i] > actualTokenAmounts[i]) {
                IERC20(_tokens[i]).safeTransfer(msg.sender, tokenAmounts[i] - actualTokenAmounts[i]);
            }
        }
        require(amountToMint + balanceOf(msg.sender) <= _limitPerAddress, "LPA");
        if (amountToMint > 0) {
            _mint(msg.sender, amountToMint);
        }

        emit Deposit(msg.sender, _tokens, actualTokenAmounts, amountToMint);
    }

    /// @notice Withdraw tokens from LpIssuer
    /// @param to Address to withdraw to
    /// @param lpTokenAmount Amount of token to withdraw
    /// @param optimized Whether to use gas optimization or not. When `true` the call can have some gas cost reduction
    /// but the operation is not guaranteed to succeed. When `false` the gas cost could be higher but the operation is guaranteed to succeed.
    /// @param options Additional options that could be needed for some vaults. E.g. for Uniswap this could be `deadline` param.
    function withdraw(
        address to,
        uint256 lpTokenAmount,
        bool optimized,
        bytes memory options
    ) external {
        require(_subvaultNft > 0, "INIT");
        require(totalSupply() > 0, "TS");
        uint256[] memory tokenAmounts = new uint256[](_tokens.length);
        uint256[] memory tvl = _subvault().tvl();
        for (uint256 i = 0; i < _tokens.length; i++) {
            tokenAmounts[i] = (lpTokenAmount * tvl[i]) / totalSupply();
        }
        uint256[] memory actualTokenAmounts = _subvault().pull(
            address(this),
            _tokens,
            tokenAmounts,
            optimized,
            options
        );
        uint256 protocolExitFee = governanceParams().protocolGovernance.protocolExitFee();
        address protocolTreasury = governanceParams().protocolGovernance.protocolTreasury();
        uint256[] memory exitFees = new uint256[](_tokens.length);
        for (uint256 i = 0; i < _tokens.length; i++) {
            if (actualTokenAmounts[i] == 0) {
                continue;
            }
            exitFees[i] = (actualTokenAmounts[i] * protocolExitFee) / Common.DENOMINATOR;
            actualTokenAmounts[i] -= exitFees[i];
            IERC20(_tokens[i]).safeTransfer(protocolTreasury, exitFees[i]);
            IERC20(_tokens[i]).safeTransfer(to, actualTokenAmounts[i]);
        }
        _burn(msg.sender, lpTokenAmount);
        emit Withdraw(msg.sender, _tokens, actualTokenAmounts, lpTokenAmount);
        emit ExitFeeCollected(msg.sender, protocolTreasury, _tokens, exitFees);
    }

    /// @inheritdoc ILpIssuer
    function addSubvault(uint256 nft) external {
        require(msg.sender == address(_vaultGovernance), "RVG");
        require(_subvaultNft == 0, "SBIN");
        require(nft > 0, "NFT0");
        _subvaultNft = nft;
    }

    function _subvault() internal returns (IVault) {
        return _vaultGovernance.internalParams().registry.vaultForNft(_subvaultNft);
    }

    event Deposit(address indexed from, address[] tokens, uint256[] actualTokenAmounts, uint256 lpTokenMinted);
    event Withdraw(address indexed from, address[] tokens, uint256[] actualTokenAmounts, uint256 lpTokenBurned);
    event ExitFeeCollected(address indexed from, address to, address[] tokens, uint256[] amounts);
}
