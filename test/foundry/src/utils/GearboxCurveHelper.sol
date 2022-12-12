// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./GearboxHelper.sol";
import "../interfaces/external/gearbox/ICreditFacade.sol";
import "../interfaces/external/gearbox/ICurveV1Adapter.sol";
import "../interfaces/external/gearbox/IUniswapV3Adapter.sol";
import "../libraries/external/FullMath.sol";

contract GearboxCurveHelper {

    using SafeERC20 for IERC20;

    uint256 constant D9 = 10**9;
    uint256 constant X96 = 2**96;

    bool public parametersSet;

    GearboxHelper parentHelper;

    function setParameters() external {
        parametersSet = true;
        parentHelper = GearboxHelper(msg.sender);
    }

    function makeTokensBalanced(address univ3Adapter, address primaryToken, address creditAccount, ICurveV1Adapter curveAdapter, ICreditManagerV2 creditManager, bool is3crv, int128 crv3Index, address crvPool3, MultiCall memory debtManagementCall, uint256[] memory swapPricesX96, bool tryUniswapBalancing) external {
        
        if (!tryUniswapBalancing) {
            MultiCall[] memory debtCall = new MultiCall[](1);
            debtCall[0] = debtManagementCall;
            parentHelper.gearboxVault().multicall(debtCall);
            return;
        }

        uint256 numberOfCoins = curveAdapter.nCoins();
        if (is3crv) {
            numberOfCoins += 2;
        }

        address[] memory tokens = new address[](numberOfCoins);
        uint256[] memory sharesD = new uint256[](numberOfCoins);

        uint256 totalBalance = 0;
        uint256 curveCoins = curveAdapter.nCoins();

        for (uint256 i = 0; i < curveCoins; ++i) {
            address tokenI = curveAdapter.coins(i);
            uint256 balanceI = curveAdapter.balances(i);
            tokens[i] = tokenI;
            sharesD[i] = balanceI;
            totalBalance += balanceI;
        }

        for (uint256 i = 0; i < curveCoins; ++i) {
            sharesD[i] = FullMath.mulDiv(sharesD[i], D9, totalBalance);
        }

        if (is3crv) {
            uint256 total3crvBalance = 0;
            ICurveV1Adapter crv3Adapter = ICurveV1Adapter(creditManager.contractToAdapter(crvPool3));
            uint256 multiplier = sharesD[uint128(crv3Index)];

            for (uint256 i = 0; i < crv3Adapter.nCoins(); ++i) {
                address tokenI = crv3Adapter.coins(i);
                uint256 balanceI = crv3Adapter.balances(i);

                uint256 position = uint256(uint128(crv3Index));
                if (i > 0) {
                    position = curveCoins + i - 1;
                }

                tokens[position] = tokenI;
                sharesD[position] = balanceI;
                totalBalance += balanceI;
            }

            for (uint256 i = 0; i < crv3Adapter.nCoins(); ++i) {
                uint256 position = uint256(uint128(crv3Index));
                if (i > 0) {
                    position = curveCoins + i - 1;
                }

                sharesD[position] = FullMath.mulDiv(sharesD[position], multiplier, totalBalance);
            }
        }

        uint256 startBalance = IERC20(primaryToken).balanceOf(creditAccount);

        MultiCall[] memory calls = new MultiCall[](curveCoins);
        calls[0] = debtManagementCall;

        uint256 pointer = 1;

        for (uint256 i = 0; i < numberOfCoins; ++i) {
            if (tokens[i] == primaryToken) {
                continue;
            }

            uint256 toSwap = FullMath.mulDiv(startBalance, sharesD[i], D9);
            ISwapRouter.ExactInputParams memory inputParams = ISwapRouter.ExactInputParams({
                path: abi.encodePacked(primaryToken, uint24(100), tokens[i]),
                recipient: creditAccount,
                deadline: block.timestamp + 1,
                amountIn: toSwap,
                amountOutMinimum: FullMath.mulDiv(toSwap, swapPricesX96[2 * pointer], X96)
            });

            calls[pointer] = MultiCall({ // swap deposit to primary token
                target: univ3Adapter,
                callData: abi.encodeWithSelector(ISwapRouter.exactInput.selector, inputParams)
            });

            pointer += 1;

        }   

        parentHelper.gearboxVault().multicall(calls);
    }


    function makeTokensUnbalanced(address univ3Adapter, address primaryToken, address creditAccount, ICurveV1Adapter curveAdapter, ICreditManagerV2 creditManager, bool is3crv, int128 crv3Index, address crv3Pool, uint256[] memory swapPricesX96, bool tryUniswapBalancing) external {
        
        if (!tryUniswapBalancing) {
            return;
        }

        uint256 numberOfCoins = curveAdapter.nCoins();
        if (is3crv) {
            numberOfCoins += 2;
        }

        address[] memory tokens = new address[](numberOfCoins);

        for (uint256 i = 0; i < numberOfCoins; ++i) {
            address tokenI = curveAdapter.coins(i);
            tokens[i] = tokenI;
        }

        if (is3crv) {
            ICurveV1Adapter crv3Adapter = ICurveV1Adapter(creditManager.contractToAdapter(crv3Pool));

            for (uint256 i = 0; i < crv3Adapter.nCoins(); ++i) {
                address tokenI = crv3Adapter.coins(i);

                uint256 position = uint256(uint128(crv3Index));
                if (i > 0) {
                    position = numberOfCoins + i - 1;
                }

                tokens[position] = tokenI;
            }
        }

        MultiCall[] memory calls = new MultiCall[](numberOfCoins - 1);

        uint256 pointer = 0;

        for (uint256 i = 0; i < numberOfCoins; ++i) {
            if (tokens[i] == primaryToken) {
                continue;
            }

            uint256 toSwap = IERC20(tokens[i]).balanceOf(creditAccount);

            ISwapRouter.ExactInputParams memory inputParams = ISwapRouter.ExactInputParams({
                path: abi.encodePacked(tokens[i], uint24(100), primaryToken),
                recipient: creditAccount,
                deadline: block.timestamp + 1,
                amountIn: toSwap,
                amountOutMinimum: FullMath.mulDiv(toSwap, X96, swapPricesX96[2 * pointer + 1])
            });

            calls[pointer] = MultiCall({ 
                target: univ3Adapter,
                callData: abi.encodeWithSelector(ISwapRouter.exactInput.selector, inputParams)
            });

            pointer += 1;

        }   

        parentHelper.gearboxVault().multicall(calls);
    }
    
}
