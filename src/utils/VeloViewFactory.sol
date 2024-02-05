// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";

import "./VeloDeployFactory.sol";

contract VeloViewFactory {
    struct UserInfo {
        address rootVault;
        address farm;
        uint256 protocolFeeD9;
        bool isClosed;
        uint256 lpBalance;
        uint256 amount0;
        uint256 amount1;
        address pool;
        uint256 pendingRewards;
    }

    VeloDeployFactory public immutable factory;

    constructor(VeloDeployFactory factory_) {
        factory = factory_;
    }

    function getUserInfo(address user) external view returns (UserInfo[] memory userInfos) {
        address[] memory pools_ = factory.pools();
        userInfos = new UserInfo[](pools_.length);

        uint256 iterator = 0;
        for (uint256 i = 0; i < pools_.length; i++) {
            address pool = pools_[i];
            VeloDeployFactory.VaultInfo memory info = factory.getVaultInfoByPool(pool);
            UserInfo memory userInfo;
            userInfo.rootVault = address(info.rootVault);
            userInfo.farm = address(info.depositWrapper);
            userInfo.protocolFeeD9 = IVeloVault(address(info.veloVaults[0])).strategyParams().protocolFeeD9;
            {
                userInfo.isClosed = true;
                (address strategy_, ) = VeloDepositWrapper(info.depositWrapper).strategyInfo();
                if (strategy_ != address(0)) {
                    address[] memory depositorsAllowlist = info.rootVault.depositorsAllowlist();
                    for (uint256 j = 0; j < depositorsAllowlist.length; j++) {
                        if (depositorsAllowlist[j] == info.depositWrapper) {
                            userInfo.isClosed = false;
                            break;
                        }
                    }
                }
            }
            userInfo.lpBalance = info.rootVault.balanceOf(user);
            {
                (uint256[] memory tvl, ) = info.rootVault.tvl();
                uint256 totalSupply = info.rootVault.totalSupply();
                require(tvl.length == 2, "Invalid length");
                userInfo.amount0 = FullMath.mulDiv(tvl[0], userInfo.lpBalance, totalSupply);
                userInfo.amount1 = FullMath.mulDiv(tvl[1], userInfo.lpBalance, totalSupply);
            }
            userInfo.pool = address(info.pool);
            userInfo.pendingRewards = VeloDepositWrapper(info.depositWrapper).earned(user);

            if (userInfo.amount0 > 0 || userInfo.amount1 > 0 || userInfo.pendingRewards > 0) {
                userInfos[iterator++] = userInfo;
            }
        }

        assembly {
            mstore(userInfos, iterator)
        }
    }
}
