// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "../libraries/external/FullMath.sol";

import "./DefaultAccessControlLateInit.sol";

contract VeloFarm is DefaultAccessControlLateInit, ERC20 {
    uint256 public constant D9 = 1e9;
    uint256 public constant MAX_PROTOCOL_FEE = 2e8; // 20%

    using SafeERC20 for IERC20;

    struct Epoch {
        uint256 amount;
        uint256 totalSupply;
    }

    Epoch[] private _epochs;

    mapping(address => uint256) public epochIterator;
    mapping(address => mapping(uint256 => int256)) public balanceDelta;
    mapping(address => bool) public hasDeposits;

    struct Storage {
        address lpToken;
        address rewardToken;
        address protocolTreasury;
        uint256 protocolFeeD9;
        uint256 totalCollectedAmounts;
        uint256 totalClaimedAmounts;
        string name;
        string symbol;
    }

    bytes32 public constant STORAGE_SLOT = keccak256("farm.storage");

    function _contractStorage() internal pure returns (Storage storage s) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            s.slot := slot
        }
    }

    constructor() ERC20("", "") {}

    function initialize(
        address lpToken_,
        address admin_,
        address protocolTreasury_,
        address rewardToken_,
        uint256 protocolFeeD9_
    ) external {
        Storage storage s = _contractStorage();
        s.name = string(abi.encodePacked(IERC20Metadata(lpToken_).name(), " instant farm"));
        s.symbol = string(abi.encodePacked(IERC20Metadata(lpToken_).symbol(), "IF"));

        if (
            lpToken_ == address(0) ||
            admin_ == address(0) ||
            protocolTreasury_ == address(0) ||
            rewardToken_ == address(0)
        ) {
            revert(ExceptionsLibrary.ADDRESS_ZERO);
        }
        if (protocolFeeD9_ > MAX_PROTOCOL_FEE) revert(ExceptionsLibrary.FORBIDDEN);
        s.lpToken = lpToken_;
        s.rewardToken = rewardToken_;
        s.protocolTreasury = protocolTreasury_;
        s.protocolFeeD9 = protocolFeeD9_;
        DefaultAccessControlLateInit.init(admin_);
    }

    function getStorage() public pure returns (Storage memory) {
        return _contractStorage();
    }

    function name() public view override returns (string memory) {
        return _contractStorage().name;
    }

    function symbol() public view override returns (string memory) {
        return _contractStorage().symbol;
    }

    function epochCount() external view returns (uint256) {
        return _epochs.length;
    }

    function epochAt(uint256 index) external view returns (Epoch memory) {
        return _epochs[index];
    }

    function updateProtocolTreasury(address newProtocolTreasury) external {
        _requireAdmin();
        if (newProtocolTreasury == address(0)) revert(ExceptionsLibrary.ADDRESS_ZERO);
        _contractStorage().protocolTreasury = newProtocolTreasury;
    }

    function decreaseProtocolFee(uint256 newProtocolFeeD9) external {
        _requireAdmin();
        if (newProtocolFeeD9 > MAX_PROTOCOL_FEE) revert(ExceptionsLibrary.FORBIDDEN);
        _contractStorage().protocolFeeD9 = newProtocolFeeD9;
    }

    function updateRewardAmounts() external returns (uint256 amount) {
        _requireAtLeastOperator();
        require(totalSupply() > 0, ExceptionsLibrary.VALUE_ZERO);
        address this_ = address(this);

        Storage memory s = _contractStorage();
        uint256 totalCollectedAmounts_ = s.totalCollectedAmounts;
        uint256 totalClaimedAmounts_ = s.totalClaimedAmounts;
        {
            uint256 farmBalanceBefore = totalCollectedAmounts_ - totalClaimedAmounts_;
            amount = IERC20(s.rewardToken).balanceOf(this_) - farmBalanceBefore;
            if (amount > 0) {
                _contractStorage().totalCollectedAmounts += amount;
                uint256 totalSupply_ = IERC20(s.lpToken).balanceOf(this_);
                if (s.protocolFeeD9 > 0) {
                    uint256 fee = FullMath.mulDiv(amount, s.protocolFeeD9, D9);
                    if (fee > 0) {
                        IERC20(s.rewardToken).safeTransfer(s.protocolTreasury, fee);
                        amount -= fee;
                    }
                }
                _epochs.push(Epoch({amount: amount, totalSupply: totalSupply_}));
                emit RewardAmountsUpdated(_epochs.length - 1, amount, totalSupply_);
            }
        }
    }

    function deposit(uint256 lpAmount, address to) external {
        IERC20(_contractStorage().lpToken).safeTransferFrom(msg.sender, address(this), lpAmount);
        _mint(to, lpAmount);
        if (!hasDeposits[to]) {
            hasDeposits[to] = true;
            epochIterator[to] = _epochs.length;
        }
    }

    function withdraw(uint256 lpAmount, address to) external {
        _burn(msg.sender, lpAmount);
        IERC20(_contractStorage().lpToken).safeTransfer(to, lpAmount);
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override {
        uint256 epochCount_ = _epochs.length;
        if (from != address(0)) {
            balanceDelta[from][epochCount_] -= int256(amount);
        }
        if (to != address(0)) {
            balanceDelta[to][epochCount_] += int256(amount);
        }
    }

    function claim(address to) external returns (uint256 amount) {
        address user = msg.sender;
        uint256 iterator = epochIterator[user];
        uint256 epochCount_ = _epochs.length;

        if (iterator == epochCount_) return amount;
        mapping(uint256 => int256) storage balanceDelta_ = balanceDelta[user];

        uint256 lpAmount = balanceOf(user);
        uint256 epochIndex = epochCount_;
        while (epochIndex >= iterator) {
            if (epochIndex < epochCount_) {
                Epoch memory epoch_ = _epochs[epochIndex];
                amount += FullMath.mulDiv(lpAmount, epoch_.amount, epoch_.totalSupply);
            }

            int256 delta = balanceDelta_[epochIndex];
            if (delta > 0) {
                lpAmount -= uint256(delta);
            } else if (delta < 0) {
                lpAmount += uint256(-delta);
            }
            if (epochIndex == 0) break;
            epochIndex--;
        }

        if (amount > 0) {
            Storage storage s = _contractStorage();
            IERC20(s.rewardToken).safeTransfer(to, amount);
            s.totalClaimedAmounts += amount;
        }
        epochIterator[user] = epochCount_;
    }

    event RewardAmountsUpdated(uint256 indexed lastEpochId, uint256 amount, uint256 totalSupply);
}
