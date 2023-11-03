// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "../libraries/external/FullMath.sol";

import "./DefaultAccessControl.sol";

contract InstantFarm is DefaultAccessControl, ERC20 {
    using SafeERC20 for IERC20;

    struct Epoch {
        uint256[] amounts;
        uint256 totalSupply;
    }

    Epoch[] private _epochs;
    address public immutable lpToken;

    address[] public rewardTokens;
    uint256[] public totalCollectedAmounts;
    uint256[] public totalClaimedAmounts;

    mapping(address => uint256) public epochIterator;
    mapping(address => mapping(uint256 => int256)) public balanceDelta;

    constructor(
        address lpToken_,
        address admin_,
        address[] memory rewardTokens_
    )
        DefaultAccessControl(admin_)
        ERC20(
            string(abi.encode(ERC20(lpToken_).symbol(), "IF")),
            string(abi.encode(ERC20(lpToken_).name(), " instant farm"))
        )
    {
        require(rewardTokens_.length > 0, ExceptionsLibrary.INVALID_LENGTH);
        for (uint256 i = 0; i < rewardTokens_.length; i++) {
            require(rewardTokens_[i] != address(0) && rewardTokens_[i] != lpToken_, ExceptionsLibrary.INVALID_VALUE);
        }
        lpToken = lpToken_;
        rewardTokens = rewardTokens_;

        totalCollectedAmounts = new uint256[](rewardTokens_.length);
        totalClaimedAmounts = new uint256[](rewardTokens_.length);
    }

    function epoch(uint256 index) external view returns (Epoch memory) {
        return _epochs[index];
    }

    function updateRewardAmounts() external returns (uint256[] memory amounts) {
        _requireAtLeastOperator();
        require(totalSupply() > 0, ExceptionsLibrary.VALUE_ZERO);
        address[] memory tokens = rewardTokens;
        amounts = new uint256[](tokens.length);
        address this_ = address(this);

        uint256[] memory totalCollectedAmounts_ = totalCollectedAmounts;
        uint256[] memory totalClaimedAmounts_ = totalClaimedAmounts;
        bool isNonZeroAmounts = false;
        for (uint256 i = 0; i < tokens.length; i++) {
            uint256 farmBalanceBefore = totalCollectedAmounts_[i] - totalClaimedAmounts_[i];
            amounts[i] = IERC20(tokens[i]).balanceOf(this_) - farmBalanceBefore;
            if (amounts[i] > 0) {
                isNonZeroAmounts = true;
                totalCollectedAmounts[i] += amounts[i];
            }
        }

        if (isNonZeroAmounts) {
            _epochs.push(Epoch({amounts: amounts, totalSupply: IERC20(lpToken).balanceOf(this_)}));
        }
    }

    function deposit(uint256 lpAmount, address to) external {
        IERC20(lpToken).safeTransferFrom(msg.sender, address(this), lpAmount);
        _mint(to, lpAmount);
        uint256 epochCount = _epochs.length;
        balanceDelta[to][epochCount] += int256(lpAmount);
    }

    function withdraw(uint256 lpAmount, address to) external {
        _burn(msg.sender, lpAmount);
        IERC20(lpToken).safeTransfer(to, lpAmount);
        uint256 epochCount = _epochs.length;
        balanceDelta[to][epochCount] -= int256(lpAmount);
    }

    function claim(address user, address to) external returns (uint256[] memory amounts) {
        require(to == user || msg.sender == user, ExceptionsLibrary.FORBIDDEN);
        uint256 iterator = epochIterator[user];
        uint256 epochCount = _epochs.length;
        address[] memory tokens = rewardTokens;
        amounts = new uint256[](tokens.length);
        if (iterator == epochCount) return amounts;
        mapping(uint256 => int256) storage userLpDelta = balanceDelta[user];

        uint256 userLpAmount = balanceOf(user);
        uint256 epochIndex = epochCount;
        while (epochIndex >= iterator) {
            if (epochIndex < epochCount) {
                Epoch memory epoch_ = _epochs[epochIndex];
                for (uint256 i = 0; i < tokens.length; i++) {
                    amounts[i] += FullMath.mulDiv(userLpAmount, epoch_.amounts[i], epoch_.totalSupply);
                }
            }

            int256 delta = userLpDelta[epochIndex];
            if (delta > 0) {
                userLpAmount -= uint256(delta);
            } else if (delta < 0) {
                userLpAmount += uint256(-delta);
            }
            if (epochIndex == 0) break;
            epochIndex--;
        }

        for (uint256 i = 0; i < amounts.length; i++) {
            if (amounts[i] > 0) {
                IERC20(tokens[i]).safeTransfer(to, amounts[i]);
                totalClaimedAmounts[i] += amounts[i];
            }
        }
        epochIterator[user] = epochCount;
    }
}
