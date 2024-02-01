// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

// import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
// import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
// import "@openzeppelin/contracts/proxy/Clones.sol";

// import "./VeloDeployFactory.sol";

// contract VeloViewFactory {
//     VeloDeployFactory public immutable factory;

//     constructor(VeloDeployFactory factory_) {
//         factory = factory_;
//     }

//     function getUserInfo(address user) external view returns (VeloDeployFactory.UserInfo[] memory userInfos) {
//         address[] memory pools_ = factory.pools();
//         userInfos = new VeloDeployFactory.UserInfo[](pools_.length);
//         VeloDeployFactory.InternalParams memory params = factory.getInternalParams();

//         uint256 iterator = 0;
//         for (uint256 i = 0; i < pools_.length; i++) {
//             address pool = pools_[i];
//             VeloDeployFactory.VaultInfo memory info = factory.getVaultInfoByPool(pool);
//             VeloDeployFactory.UserInfo memory userInfo;
//             userInfo.rootVault = address(info.rootVault);
//             userInfo.farm = address(info.farm);
//             userInfo.farmFee = VeloFarm(info.farm).getStorage().protocolFeeD9;
//             {
//                 userInfo.isClosed = true;
//                 if (
//                     VeloDepositWrapper(params.addresses.depositWrapper).depositInfo(address(info.rootVault)).strategy !=
//                     address(0)
//                 ) {
//                     address[] memory depositorsAllowlist = info.rootVault.depositorsAllowlist();
//                     for (uint256 j = 0; j < depositorsAllowlist.length; j++) {
//                         if (depositorsAllowlist[j] == params.addresses.depositWrapper) {
//                             userInfo.isClosed = false;
//                             break;
//                         }
//                     }
//                 }
//             }
//             userInfo.lpBalance = info.rootVault.balanceOf(user);
//             {
//                 (uint256[] memory tvl, ) = info.rootVault.tvl();
//                 uint256 totalSupply = info.rootVault.totalSupply();
//                 require(tvl.length == 2, "Invalid length");
//                 userInfo.amount0 = FullMath.mulDiv(tvl[0], userInfo.lpBalance, totalSupply);
//                 userInfo.amount1 = FullMath.mulDiv(tvl[1], userInfo.lpBalance, totalSupply);
//             }
//             userInfo.pool = address(info.pool);
//             userInfo.pendingRewards = VeloFarm(info.farm).rewards(user);

//             if (userInfo.amount0 > 0 || userInfo.amount1 > 0 || userInfo.pendingRewards > 0) {
//                 userInfos[iterator++] = userInfo;
//             }
//         }

//         assembly {
//             mstore(userInfos, iterator)
//         }
//     }
// }
