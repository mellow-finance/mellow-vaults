// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/external/univ2/periphery/IWETH.sol";
import "../interfaces/IProtocolGovernance.sol";
import "../interfaces/vaults/IERC20RootVault.sol";
import "../interfaces/oracles/IChainlinkOracle.sol";
import "../interfaces/utils/ISwapper.sol";
import "../libraries/external/FullMath.sol";
import "../libraries/ExceptionsLibrary.sol";
import "../libraries/PermissionIdsLibrary.sol";

import "./DefaultAccessControl.sol";

contract InchDepositWrapper is DefaultAccessControl {
    using SafeERC20 for IERC20;
    using SafeERC20 for IERC20RootVault;

    IChainlinkOracle public immutable mellowOracle;
    IProtocolGovernance public immutable governance;
    address public immutable weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    ISwapper public immutable swapHelper;

    uint256 public slippageD9;

    uint256 public constant Q96 = 2**96;
    uint256 public constant D18 = 10**18;
    uint256 public constant D9 = 10**9;

    mapping(address => mapping(address => uint256)) public pairToMask;

    constructor(
        IChainlinkOracle mellowOracle_,
        IProtocolGovernance governance_,
        ISwapper swapHelper_,
        address admin,
        uint256 initialSlippageD9
    ) DefaultAccessControl(admin) {
        mellowOracle = mellowOracle_;
        governance = governance_;
        swapHelper = swapHelper_;
        slippageD9 = initialSlippageD9;
    }

    function _convert(
        address token0,
        address token1,
        uint256 amount
    ) internal view returns (uint256) {
        (uint256[] memory pricesX96, ) = mellowOracle.priceX96(token0, token1, pairToMask[token0][token1]);

        uint256 sum = 0;
        for (uint256 i = 0; i < pricesX96.length; ++i) {
            sum += pricesX96[i];
        }

        require(sum != 0, ExceptionsLibrary.INVALID_TARGET);
        return FullMath.mulDiv(amount, sum / pricesX96.length, Q96);
    }

    function setSlippage(uint256 newSlippageD9) external {
        _requireAdmin();
        require(newSlippageD9 <= D9, ExceptionsLibrary.INVARIANT);
        slippageD9 = newSlippageD9;
    }

    function setMask(
        address token0,
        address token1,
        uint256 mask
    ) external {
        _requireAdmin();
        pairToMask[token0][token1] = mask;
        pairToMask[token1][token0] = mask;
    }

    function deposit(
        IERC20RootVault rootVault,
        address token,
        uint256 amount,
        uint256 minLpTokens,
        bytes calldata vaultOptions,
        bytes[] calldata swapOptions,
        uint256 minAmountOut
    ) external payable returns (uint256[] memory actualTokenAmounts) {
        if (msg.value > 0) {
            require(token == weth, ExceptionsLibrary.INVALID_TOKEN);
            require(msg.value == amount, ExceptionsLibrary.INVARIANT);
            IWETH(weth).deposit{value: msg.value}();
        }

        require(governance.hasPermission(token, PermissionIdsLibrary.ERC20_TRANSFER), ExceptionsLibrary.FORBIDDEN);

        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        address[] memory vaultTokens = rootVault.vaultTokens();
        uint256[] memory swapAmounts = calcSwapAmounts(rootVault, amount);

        IERC20(token).safeIncreaseAllowance(address(swapHelper), amount);

        for (uint256 i = 0; i < vaultTokens.length; ++i) {
            if (vaultTokens[i] != token) {
                uint256 expectedAmountOut = _convert(vaultTokens[0], vaultTokens[i], swapAmounts[i]);

                uint256 oldBalance = IERC20(vaultTokens[i]).balanceOf(address(this));

                swapHelper.swap(token, vaultTokens[i], swapAmounts[i], minAmountOut, swapOptions[i]);

                require(
                    IERC20(vaultTokens[i]).balanceOf(address(this)) - oldBalance >=
                        FullMath.mulDiv(expectedAmountOut, D9 - slippageD9, D9),
                    ExceptionsLibrary.LIMIT_UNDERFLOW
                );
            }
        }

        IERC20(token).safeApprove(address(swapHelper), 0);

        {
            uint256[] memory balances = new uint256[](vaultTokens.length);
            for (uint256 i = 0; i < vaultTokens.length; ++i) {
                balances[i] = IERC20(vaultTokens[i]).balanceOf(address(this));
                if (balances[i] > 0) {
                    IERC20(vaultTokens[i]).safeIncreaseAllowance(address(rootVault), balances[i]);
                }
            }

            actualTokenAmounts = rootVault.deposit(balances, minLpTokens, vaultOptions);
        }

        uint256 lpReceived = rootVault.balanceOf(address(this));

        for (uint256 i = 0; i < vaultTokens.length; ++i) {
            IERC20(vaultTokens[i]).safeApprove(address(rootVault), 0);
        }

        rootVault.safeTransfer(msg.sender, rootVault.balanceOf(address(this)));
        for (uint256 i = 0; i < vaultTokens.length; ++i) {
            uint256 balance = IERC20(vaultTokens[i]).balanceOf(address(this));
            if (balance > 0) {
                IERC20(vaultTokens[i]).safeTransfer(msg.sender, balance);
            }
        }

        uint256 tokenBalance = IERC20(token).balanceOf(address(this));
        if (tokenBalance > 0) {
            IERC20(token).safeTransfer(msg.sender, tokenBalance);
        }

        emit Deposit(msg.sender, address(rootVault), vaultTokens, actualTokenAmounts, lpReceived);
    }

    function calcSwapAmounts(IERC20RootVault rootVault, uint256 amount)
        public
        view
        returns (uint256[] memory swapAmounts)
    {
        (, uint256[] memory maxTvl) = rootVault.tvl();

        address[] memory vaultTokens = rootVault.vaultTokens();

        swapAmounts = new uint256[](maxTvl.length);

        uint256[] memory convertedAmounts = new uint256[](vaultTokens.length);
        convertedAmounts[0] = maxTvl[0];

        uint256 totalToken0Tvl = maxTvl[0];
        for (uint256 i = 1; i < vaultTokens.length; ++i) {
            convertedAmounts[i] = _convert(vaultTokens[i], vaultTokens[0], maxTvl[i]);
            totalToken0Tvl += convertedAmounts[i];
        }

        for (uint256 i = 0; i < vaultTokens.length; ++i) {
            swapAmounts[i] = FullMath.mulDiv(convertedAmounts[i], amount, totalToken0Tvl);
        }
    }

    /// @notice Emitted when liquidity is deposited
    /// @param from The source address for the liquidity
    /// @param tokens ERC20 tokens deposited
    /// @param actualTokenAmounts Token amounts deposited
    /// @param lpTokenMinted LP tokens received by the liquidity provider
    event Deposit(
        address indexed from,
        address indexed to,
        address[] tokens,
        uint256[] actualTokenAmounts,
        uint256 lpTokenMinted
    );
}
