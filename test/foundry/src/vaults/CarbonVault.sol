// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../interfaces/vaults/ICarbonVault.sol";
import "../libraries/CommonLibrary.sol";
import "../libraries/external/FullMath.sol";
import "../interfaces/external/carbon/contracts/carbon/interfaces/ICarbonController.sol";
import "../interfaces/external/carbon/IWETH.sol";
import "./IntegrationVault.sol";

import "../interfaces/vaults/ICarbonVaultGovernance.sol";

import "forge-std/console2.sol";

contract CarbonVault is ICarbonVault, IntegrationVault {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.UintSet;

    uint256 public constant Q96 = 2 ** 96;
    uint256 public constant NO_WETH = 2;

    EnumerableSet.UintSet positions;

    ICarbonController public controller;
    address public weth;
    address public constant eth = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    bool public tokensReversed;
    uint256 public wethIndex;

    function tvl() public view returns (uint256[] memory minTokenAmounts, uint256[] memory maxTokenAmounts) {
        minTokenAmounts = new uint256[](2);

        address[] memory vaultTokens = _vaultTokens;

        uint256 positionsCount = positions.length();
        for (uint256 i = 0; i < positionsCount; ++i) {
            uint256 position = positions.at(i);
            Strategy memory strategy = controller.strategy(position);

            for (uint256 j = 0; j < 2; ++j) {
                Order memory order = strategy.orders[j];
                if (!tokensReversed) {
                    minTokenAmounts[j] += order.y;
                }
                else {
                    minTokenAmounts[1 - j] += order.y;
                }
            }
        }

        for (uint256 i = 0; i < 2; ++i) {
            minTokenAmounts[i] += IERC20(vaultTokens[i]).balanceOf(address(this));
        }

        maxTokenAmounts = minTokenAmounts;
    }

    function _bitwiseLength(uint256 self) internal pure returns (uint16 highest) {
        require(self != 0);
        uint256 val = self;
        highest = 1;
        for (uint8 i = 128; i >= 1; i >>= 1) {
            if (val & (1 << i) - 1 << i != 0) {
                highest += uint16(i);
                val >>= i;
            }
        }
    }
    
    function _g(uint256 x) internal view returns (uint256 res) {
        res = CommonLibrary.sqrt(x);
        uint16 b = _bitwiseLength(res);

        if (b >= 48) {
            res >>= (b - 48);
            res <<= (b - 48);
        }
    }

    function _e(uint256 x) internal pure returns (uint64) {
        uint16 b = _bitwiseLength(x);
        if (b >= 48) {
            b -= 48;
        }
        else {
            b = 0;
        }

        return uint64((x >> b) | (uint256(b) << 48));

    }

    function getPosition(uint256 index) external returns (uint256 nft) {
        require(index < positions.length(), ExceptionsLibrary.INVALID_TARGET);
        return positions.at(index);
    }

    function addPosition(uint256 lowerPriceLOX96, uint256 startPriceLOX96, uint256 upperPriceLOX96, uint256 lowerPriceROX96, uint256 startPriceROX96, uint256 upperPriceROX96, uint256 amount0, uint256 amount1) external returns (uint256 nft) {
        require(_isApprovedOrOwner(msg.sender));

        require(lowerPriceLOX96 <= startPriceLOX96 && startPriceLOX96 <= upperPriceLOX96, ExceptionsLibrary.INVARIANT);
        require(upperPriceLOX96 <= lowerPriceROX96, ExceptionsLibrary.INVARIANT);
        require(lowerPriceROX96 <= startPriceROX96 && startPriceROX96 <= upperPriceROX96, ExceptionsLibrary.INVARIANT);

        if (tokensReversed) {
            (amount0, amount1) = (amount1, amount0);
            lowerPriceLOX96 = FullMath.mulDiv(Q96, Q96, lowerPriceLOX96);
            upperPriceLOX96 = FullMath.mulDiv(Q96, Q96, upperPriceLOX96);
            startPriceLOX96 = FullMath.mulDiv(Q96, Q96, startPriceLOX96);

            lowerPriceROX96 = FullMath.mulDiv(Q96, Q96, lowerPriceROX96);
            upperPriceROX96 = FullMath.mulDiv(Q96, Q96, upperPriceROX96);
            startPriceROX96 = FullMath.mulDiv(Q96, Q96, startPriceROX96);

            (lowerPriceLOX96, upperPriceROX96) = (upperPriceROX96, lowerPriceLOX96);
            (upperPriceLOX96, lowerPriceROX96) = (lowerPriceROX96, upperPriceLOX96);
            (startPriceLOX96, startPriceROX96) = (startPriceROX96, startPriceLOX96);
        }

        ICarbonVaultGovernance.DelayedStrategyParams memory strategyParams = ICarbonVaultGovernance(address(_vaultGovernance))
            .delayedStrategyParams(_nft);

        {

            uint256 newPositionsCount = positions.length() + 1;
            uint256 maxPositionsCount = strategyParams.maximalPositionsCount;

            require(newPositionsCount <= maxPositionsCount, ExceptionsLibrary.LIMIT_OVERFLOW);

        }

        if (startPriceROX96 == upperPriceROX96) {
            require(amount0 == 0, ExceptionsLibrary.INVARIANT);
        }

        if (startPriceLOX96 == lowerPriceLOX96) {
            require(amount1 == 0, ExceptionsLibrary.INVARIANT);
        }

        _checkBalanceSpecial(0, _vaultTokens, amount0);
        _checkBalanceSpecial(1, _vaultTokens, amount1);

        Order[2] memory orders;

        {
            uint256 lowerPriceROT = _g(FullMath.mulDiv(Q96, Q96, upperPriceROX96));
            uint256 upperPriceROT = _g(FullMath.mulDiv(Q96, Q96, lowerPriceROX96));
            uint256 startPriceROT = _g(FullMath.mulDiv(Q96, Q96, startPriceROX96));

            uint128 maximalAmountOfOrder0 = uint128(amount0);
            if (lowerPriceROT != startPriceROT) {
                maximalAmountOfOrder0 = uint128(FullMath.mulDiv(amount0, upperPriceROT - lowerPriceROT, startPriceROT - lowerPriceROT));
            }

            orders[0] = Order(uint128(amount0), maximalAmountOfOrder0, _e(upperPriceROT - lowerPriceROT), _e(lowerPriceROT)); 
        }

        {
            uint256 lowerPriceLOT = _g(lowerPriceLOX96);
            uint256 upperPriceLOT = _g(upperPriceLOX96);
            uint256 startPriceLOT = _g(startPriceLOX96);

            uint128 maximalAmountOfOrder1 = uint128(amount1);
            if (lowerPriceLOT != startPriceLOT) {
                maximalAmountOfOrder1 = uint128(FullMath.mulDiv(amount1, upperPriceLOT - lowerPriceLOT, startPriceLOT - lowerPriceLOT));
            }

            orders[1] = Order(uint128(amount1), maximalAmountOfOrder1, _e(upperPriceLOT - lowerPriceLOT), _e(lowerPriceLOT)); 
        }

        uint256 val;
        if (wethIndex != NO_WETH) {
            if ((wethIndex == 0 && !tokensReversed) || (wethIndex == 1 && tokensReversed)) val = amount0;
            else val = amount1;
        }

        if (wethIndex != NO_WETH) {
            if (eth < _vaultTokens[1 - wethIndex]) {
                nft = controller.createStrategy{value: val}(Token.wrap(eth), Token.wrap(_vaultTokens[1 - wethIndex]), orders);
            }
            else {
                nft = controller.createStrategy{value: val}(Token.wrap(_vaultTokens[1 - wethIndex]), Token.wrap(eth), orders);
            }
        }
        else {
            nft = controller.createStrategy{value: val}(Token.wrap(_vaultTokens[0]), Token.wrap(_vaultTokens[1]), orders);
        }

        positions.add(nft);

        IERC20(_vaultTokens[0]).safeApprove(address(controller), 0);
        IERC20(_vaultTokens[1]).safeApprove(address(controller), 0);

    }

    /// @inheritdoc IERC721Receiver
    function onERC721Received(
        address,
        address,
        uint256,
        bytes memory
    ) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }

    function _checkBalanceSpecial(uint256 index, address[] memory vaultTokens, uint256 amount) internal {
        if (tokensReversed) {
            index = 1 - index;
        }        

        require(IERC20(vaultTokens[index]).balanceOf(address(this)) >= amount, ExceptionsLibrary.LIMIT_UNDERFLOW);
        IERC20(vaultTokens[index]).safeIncreaseAllowance(address(controller), amount);

        if (wethIndex == index) {
            IWETH(weth).withdraw(amount);
        }
    }

    function closePosition(uint256 nft) external {
        require(_isApprovedOrOwner(msg.sender));
        require(positions.contains(nft), ExceptionsLibrary.INVALID_TARGET);

        controller.deleteStrategy(nft);
        uint256 ethBalance = address(this).balance;

        IWETH(weth).deposit{value: ethBalance}();

        positions.remove(nft);
    }

    function updatePosition(uint256 nft, uint256 amount0, uint256 amount1) external {
        require(_isApprovedOrOwner(msg.sender));
        require(positions.contains(nft), ExceptionsLibrary.INVALID_TARGET);

        uint256 val;

        if (tokensReversed) {
            (amount0, amount1) = (amount1, amount0);
        }

        Strategy memory strategy = controller.strategy(nft);

        Order[2] memory currentOrders = strategy.orders;
        Order[2] memory newOrders;

        address[] memory vaultTokens = _vaultTokens;

        if (currentOrders[0].y == 0) {
            require(amount0 == 0, ExceptionsLibrary.INVARIANT);
            newOrders[0] = Order({
                y: currentOrders[0].y,
                z: currentOrders[0].z,
                A: currentOrders[0].A,
                B: currentOrders[0].B
            });
        }

        else {
            if (amount0 > uint256(currentOrders[0].y)) {
                uint256 delta = amount0 - uint256(currentOrders[0].y);
                if ((wethIndex == 0 && !tokensReversed) || (wethIndex == 1 && tokensReversed)) {
                    val = delta;
                }
                _checkBalanceSpecial(0, vaultTokens, delta);
            }

            newOrders[0] = Order({
                y: uint128(amount0),
                z: uint128(FullMath.mulDiv(uint256(currentOrders[0].z), amount0, uint256(currentOrders[0].y))),
                A: currentOrders[0].A,
                B: currentOrders[0].B
            });

        }

        if (currentOrders[1].y == 0) {
            require(amount1 == 0, ExceptionsLibrary.INVARIANT);
            newOrders[1] = Order({
                y: currentOrders[1].y,
                z: currentOrders[1].z,
                A: currentOrders[1].A,
                B: currentOrders[1].B
            });
        }

        else {
            if (amount1 > uint256(currentOrders[1].y)) {
                uint256 delta = amount1 - uint256(currentOrders[1].y);
                if ((wethIndex == 1 && !tokensReversed) || (wethIndex == 0 && tokensReversed)) {
                    val = delta;
                }
                _checkBalanceSpecial(1, vaultTokens, delta);
            }
            
            newOrders[1] = Order({
                y: uint128(amount1),
                z: uint128(FullMath.mulDiv(uint256(currentOrders[1].z), amount1, uint256(currentOrders[1].y))),
                A: currentOrders[1].A,
                B: currentOrders[1].B
            });

        }

        controller.updateStrategy{value: val}(nft, currentOrders, newOrders);
        uint256 ethBalance = address(this).balance;

        IWETH(weth).deposit{value: ethBalance}();

        IERC20(_vaultTokens[0]).safeApprove(address(controller), 0);
        IERC20(_vaultTokens[1]).safeApprove(address(controller), 0);
    }

    receive() external payable {}

    /// @inheritdoc ICarbonVault
    function initialize(uint256 nft_, address[] memory vaultTokens_) external {
        require(vaultTokens_.length == 2, ExceptionsLibrary.INVALID_LENGTH);
        _initialize(vaultTokens_, nft_);

        weth = ICarbonVaultGovernance(address(_vaultGovernance)).delayedProtocolParams().weth;
        controller = ICarbonVaultGovernance(address(_vaultGovernance)).delayedProtocolParams().controller;

        wethIndex = NO_WETH;

        for (uint256 i = 0; i < 2; ++i) {
            if (vaultTokens_[i] == weth) {
                wethIndex = i;
                if ((weth < vaultTokens_[1 - i]) != (eth < vaultTokens_[1 - i])) {
                    tokensReversed = true;
                }
            }
        }

        if (wethIndex != NO_WETH) {
            controller.pair(Token.wrap(eth), Token.wrap(vaultTokens_[1 - wethIndex]));
        }
        else {
            controller.pair(Token.wrap(vaultTokens_[0]), Token.wrap(vaultTokens_[1]));
        }

    }

    function _isReclaimForbidden(address token) internal view override returns (bool) {

        address[] memory vaultTokens = _vaultTokens;

        if (token == vaultTokens[0] || token == vaultTokens[1]) {
            return true;
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
        return tokenAmounts;
    }

    function _pull(
        address to,
        uint256[] memory tokenAmounts,
        bytes memory
    ) internal override returns (uint256[] memory actualTokenAmounts) {
        actualTokenAmounts = new uint256[](2);

        address[] memory vaultTokens = _vaultTokens;

        for (uint256 i = 0; i < 2; ++i) {
            uint256 balance = IERC20(vaultTokens[i]).balanceOf(address(this));
            actualTokenAmounts[i] = (balance < tokenAmounts[i]) ? balance : tokenAmounts[i];
            IERC20(vaultTokens[i]).safeTransfer(to, actualTokenAmounts[i]);
        }
    }

    /// @inheritdoc IntegrationVault
    function supportsInterface(bytes4 interfaceId) public view override(IERC165, IntegrationVault) returns (bool) {
        return super.supportsInterface(interfaceId) || (interfaceId == type(ICarbonVault).interfaceId);
    }
}
