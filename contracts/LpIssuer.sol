// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./libraries/Common.sol";
import "./interfaces/IVault.sol";
import "./interfaces/IProtocolGovernance.sol";
import "./interfaces/ILpIssuer.sol";
import "./DefaultAccessControl.sol";
import "./LpIssuerGovernance.sol";

/// @notice Contract that mints and burns LP tokens in exchange for ERC20 liquidity.
contract LpIssuer is ILpIssuer, ERC20 {
    using SafeERC20 for IERC20;
    uint256 private _subvaultNft;
    IVaultGovernance internal _vaultGovernance;
    address[] internal _vaultTokens;
    mapping(address => bool) internal _vaultTokensIndex;

    /// @notice Creates a new contract.
    /// @dev All subvault nfts must be owned by this vault before.
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

    function vaultGovernance() external view returns (IVaultGovernance) {
        return _vaultGovernance;
    }

    function vaultTokens() external view returns (address[] memory) {
        return _vaultTokens;
    }

    /// @inheritdoc ILpIssuer
    function subvaultNft() external view returns (uint256) {
        return _subvaultNft;
    }

    /// @notice Deposit tokens into LpIssuer
    /// @param tokenAmounts Amounts of tokens to push
    /// @param options Additional options that could be needed for some vaults. E.g. for Uniswap this could be `deadline` param.
    function deposit(uint256[] calldata tokenAmounts, bytes memory options) external {
        require(_subvaultNft > 0, "INIT");
        uint256[] memory tvl = _subvault().tvl();
        IVault subvault = _subvault();
        for (uint256 i = 0; i < _vaultTokens.length; i++) {
            _allowTokenIfNecessary(_vaultTokens[i], address(subvault));
            IERC20(_vaultTokens[i]).safeTransferFrom(msg.sender, address(this), tokenAmounts[i]);
        }
        uint256[] memory actualTokenAmounts = subvault.transferAndPush(
            address(this),
            _vaultTokens,
            tokenAmounts,
            options
        );
        uint256 amountToMint;
        if (totalSupply() == 0) {
            for (uint256 i = 0; i < _vaultTokens.length; i++) {
                // TODO: check if there could be smth better
                if (actualTokenAmounts[i] > amountToMint) {
                    amountToMint = actualTokenAmounts[i]; // some number correlated to invested assets volume
                }
            }
        }
        for (uint256 i = 0; i < _vaultTokens.length; i++) {
            if (tvl[i] > 0) {
                uint256 newMint = (actualTokenAmounts[i] * totalSupply()) / tvl[i];
                // TODO: check this algo. The assumption is that everything is rounded down.
                // So that max token has the least error. Think about the case when one token is dust.
                if (newMint > amountToMint) {
                    amountToMint = newMint;
                }
            }
            if (tokenAmounts[i] > actualTokenAmounts[i]) {
                IERC20(_vaultTokens[i]).safeTransfer(msg.sender, tokenAmounts[i] - actualTokenAmounts[i]);
            }
        }
        require(
            amountToMint + balanceOf(msg.sender) <=
                ILpIssuerGovernance(address(_vaultGovernance)).strategyParams(_selfNft()).tokenLimitPerAddress,
            "LPA"
        );
        if (amountToMint > 0) {
            _mint(msg.sender, amountToMint);
        }

        emit Deposit(msg.sender, _vaultTokens, actualTokenAmounts, amountToMint);
    }

    /// @notice Withdraw tokens from LpIssuer
    /// @param to Address to withdraw to
    /// @param lpTokenAmount Amount of token to withdraw
    /// @param options Additional options that could be needed for some vaults. E.g. for Uniswap this could be `deadline` param.
    function withdraw(
        address to,
        uint256 lpTokenAmount,
        bytes memory options
    ) external {
        require(_subvaultNft > 0, "INIT");
        require(totalSupply() > 0, "TS0");
        uint256[] memory tokenAmounts = new uint256[](_vaultTokens.length);
        uint256[] memory tvl = _subvault().tvl();
        for (uint256 i = 0; i < _vaultTokens.length; i++) {
            tokenAmounts[i] = (lpTokenAmount * tvl[i]) / totalSupply();
        }
        uint256[] memory actualTokenAmounts = _subvault().pull(address(this), _vaultTokens, tokenAmounts, options);
        for (uint256 i = 0; i < _vaultTokens.length; i++) {
            if (actualTokenAmounts[i] == 0) {
                continue;
            }
            actualTokenAmounts[i];
            IERC20(_vaultTokens[i]).safeTransfer(to, actualTokenAmounts[i]);
        }
        _burn(msg.sender, lpTokenAmount);
        emit Withdraw(msg.sender, _vaultTokens, actualTokenAmounts, lpTokenAmount);
    }

    /// @inheritdoc ILpIssuer
    function addSubvault(uint256 nft) external {
        require(msg.sender == address(_vaultGovernance), "RVG");
        require(_subvaultNft == 0, "SBIN");
        require(nft > 0, "NFT0");
        _subvaultNft = nft;
    }

    function _allowTokenIfNecessary(address token, address to) internal {
        if (IERC20(token).allowance(address(to), address(this)) < type(uint256).max / 2) {
            IERC20(token).approve(address(to), type(uint256).max);
        }
    }

    function _subvault() internal view returns (IVault) {
        return IVault(_vaultGovernance.internalParams().registry.vaultForNft(_subvaultNft));
    }

    function _selfNft() internal view returns (uint256) {
        IVaultRegistry registry = _vaultGovernance.internalParams().registry;
        return registry.nftForVault(address(this));
    }

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
