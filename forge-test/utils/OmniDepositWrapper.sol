// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

// import "forge-std/src/Test.sol";
// import "forge-std/src/Vm.sol";

// import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
// import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// import "../../src/utils/OmniDepositWrapper.sol";
// import "./Constants.sol";

// contract OmniDepositWrapperTest is Test {
//     using SafeERC20 for IERC20;

//     uint256 public constant Q96 = 2**96;

//     address public immutable u = address(uint160(bytes20(keccak256(abi.encode(address(this))))));

//     function testUniswap1() external {
//         vm.startPrank(u);
//         OmniDepositWrapper omniWrapper = new OmniDepositWrapper(
//             Constants.uniswapV3Router,
//             IUniswapV3Factory(Constants.uniswapV3Factory)
//         );
//         OmniDepositWrapper.Data memory d;

//         d.rootVault = 0x1FCD3926b6DFa2A90Fe49A383C732b31f1ee54eB;
//         d.tokenIn = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
//         d.amountIn = 10 * 1e8; // 10 wtbc
//         d.from = u;
//         d.to = u;
//         d.router = Constants.uniswapV3Router;
//         d.wrapper = address(0);
//         d.farm = address(0);
//         d.vaultOptions = new bytes(0);
//         d.minReminders = new uint256[](2);
//         d.callbacks = new bytes[](0);
//         deal(d.tokenIn, u, d.amountIn);
//         IERC20(d.tokenIn).safeApprove(address(omniWrapper), type(uint256).max);
//         d = omniWrapper.getUniswapData(d);
//         d.minLpAmount = (d.minLpAmount * 99) / 100;
//         {
//             (, uint256[] memory returnedAmounts) = omniWrapper.deposit(d);
//             address[] memory vaultTokens = IERC20RootVault(d.rootVault).vaultTokens();
//             for (uint256 i = 0; i < vaultTokens.length; i++) {
//                 console2.log(
//                     IERC20Metadata(vaultTokens[i]).symbol(),
//                     returnedAmounts[i],
//                     returnedAmounts[i] / 10**IERC20Metadata(vaultTokens[i]).decimals()
//                 );
//             }
//         }
//         vm.stopPrank();
//     }

//     function testUniswap2() external {
//         vm.startPrank(u);
//         OmniDepositWrapper omniWrapper = new OmniDepositWrapper(
//             Constants.uniswapV3Router,
//             IUniswapV3Factory(Constants.uniswapV3Factory)
//         );
//         OmniDepositWrapper.Data memory d;

//         d.rootVault = 0x460d89CaD1E65d06Ebc18E206A09bBD02AE883e6;
//         d.tokenIn = 0x64aa3364F17a4D01c6f1751Fd97C2BD3D7e7f1D5;
//         d.amountIn = 1000 * 1e9; // 1000 OHM
//         d.from = u;
//         d.to = u;
//         d.router = Constants.uniswapV3Router;
//         d.wrapper = 0x231002439E1BD5b610C3d98321EA760002b9Ff64;
//         d.farm = address(0);
//         d.vaultOptions = new bytes(0);
//         d.minReminders = new uint256[](2);
//         d.callbacks = new bytes[](0);
//         deal(d.tokenIn, u, d.amountIn);
//         IERC20(d.tokenIn).safeApprove(address(omniWrapper), type(uint256).max);
//         d = omniWrapper.getUniswapData(d);
//         d.minLpAmount = (d.minLpAmount * 99) / 100;
//         {
//             (, uint256[] memory returnedAmounts) = omniWrapper.deposit(d);
//             address[] memory vaultTokens = IERC20RootVault(d.rootVault).vaultTokens();
//             for (uint256 i = 0; i < vaultTokens.length; i++) {
//                 console2.log(
//                     IERC20Metadata(vaultTokens[i]).symbol(),
//                     returnedAmounts[i],
//                     returnedAmounts[i] / 10**IERC20Metadata(vaultTokens[i]).decimals()
//                 );
//             }
//         }
//         vm.stopPrank();
//     }

//     function testUniswap3() external {
//         vm.startPrank(u);
//         OmniDepositWrapper omniWrapper = new OmniDepositWrapper(
//             Constants.uniswapV3Router,
//             IUniswapV3Factory(Constants.uniswapV3Factory)
//         );
//         OmniDepositWrapper.Data memory d;

//         d.rootVault = 0xCE0e8fC4d256CE8555ED5AACf3480677680651d7;
//         d.tokenIn = 0xae78736Cd615f374D3085123A210448E74Fc6393;
//         d.amountIn = 10 ether; // 10 reth
//         d.from = u;
//         d.to = u;
//         d.router = Constants.uniswapV3Router;
//         d.wrapper = 0x9B8058Fa941835D5F287680D2f569935356B9730;
//         d.farm = 0x7051126223a559E3500bd0843924d971f55F0533;
//         d.vaultOptions = new bytes(0);
//         d.minReminders = new uint256[](2);
//         d.callbacks = new bytes[](0);
//         deal(d.tokenIn, u, d.amountIn);
//         IERC20(d.tokenIn).safeApprove(address(omniWrapper), type(uint256).max);
//         d = omniWrapper.getUniswapData(d);
//         d.minLpAmount = (d.minLpAmount * 99) / 100;
//         {
//             (, uint256[] memory returnedAmounts) = omniWrapper.deposit(d);
//             address[] memory vaultTokens = IERC20RootVault(d.rootVault).vaultTokens();
//             for (uint256 i = 0; i < vaultTokens.length; i++) {
//                 console2.log(
//                     IERC20Metadata(vaultTokens[i]).symbol(),
//                     returnedAmounts[i],
//                     returnedAmounts[i] / 10**IERC20Metadata(vaultTokens[i]).decimals()
//                 );
//             }
//         }
//         vm.stopPrank();
//     }

//     function getUniswapPrice(
//         address tokenIn,
//         address tokenOut,
//         uint24 fee
//     ) public view returns (uint256 priceX96) {
//         if (tokenIn == tokenOut) return Q96;
//         IUniswapV3Pool pool = IUniswapV3Pool(
//             IUniswapV3Factory(Constants.uniswapV3Factory).getPool(tokenIn, tokenOut, fee)
//         );
//         (uint160 sqrtPriceX96, , , , , , ) = pool.slot0();
//         priceX96 = FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, Q96);
//         if (tokenIn == pool.token0()) {
//             priceX96 = FullMath.mulDiv(Q96, Q96, priceX96);
//         }
//     }

//     function testOffchain1() external {
//         vm.startPrank(u);
//         OmniDepositWrapper omniWrapper = new OmniDepositWrapper(
//             Constants.uniswapV3Router,
//             IUniswapV3Factory(Constants.uniswapV3Factory)
//         );
//         OmniDepositWrapper.Data memory d;

//         d.rootVault = 0x1FCD3926b6DFa2A90Fe49A383C732b31f1ee54eB;
//         d.tokenIn = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
//         d.amountIn = 10 * 1e8; // 10 wtbc
//         d.from = u;
//         d.to = u;
//         d.router = Constants.uniswapV3Router;
//         d.wrapper = address(0);
//         d.farm = address(0);
//         d.vaultOptions = new bytes(0);
//         d.minReminders = new uint256[](2);
//         d.callbacks = new bytes[](0);
//         deal(d.tokenIn, u, d.amountIn);
//         IERC20(d.tokenIn).safeApprove(address(omniWrapper), type(uint256).max);

//         uint256[] memory pricesX96 = new uint256[](2);
//         address[] memory tokens = IERC20RootVault(d.rootVault).vaultTokens();
//         pricesX96[0] = getUniswapPrice(d.tokenIn, tokens[0], 500);
//         pricesX96[1] = getUniswapPrice(d.tokenIn, tokens[1], 500);

//         d = omniWrapper.getOffchainData(d, pricesX96);
//         uint256[] memory swappingAmounts = new uint256[](2);
//         bytes[] memory callbacks = new bytes[](2);
//         uint256 index = 0;
//         for (uint256 i = 0; i < swappingAmounts.length; i++) {
//             swappingAmounts[i] = uint256(bytes32(d.callbacks[i]));
//             if (swappingAmounts[i] == 0) continue;
//             callbacks[index++] = abi.encodeWithSelector(
//                 ISwapRouter.exactInputSingle.selector,
//                 ISwapRouter.ExactInputSingleParams({
//                     tokenIn: d.tokenIn,
//                     tokenOut: tokens[i],
//                     amountIn: swappingAmounts[i],
//                     fee: 500,
//                     deadline: type(uint256).max,
//                     sqrtPriceLimitX96: 0,
//                     amountOutMinimum: 0,
//                     recipient: address(omniWrapper)
//                 })
//             );
//         }
//         assembly {
//             mstore(callbacks, index)
//         }
//         d.router = Constants.uniswapV3Router;
//         d.callbacks = callbacks;
//         d.minLpAmount = (d.minLpAmount * 99) / 100;
//         {
//             (, uint256[] memory returnedAmounts) = omniWrapper.deposit(d);
//             address[] memory vaultTokens = IERC20RootVault(d.rootVault).vaultTokens();
//             for (uint256 i = 0; i < vaultTokens.length; i++) {
//                 console2.log(
//                     IERC20Metadata(vaultTokens[i]).symbol(),
//                     returnedAmounts[i],
//                     returnedAmounts[i] / 10**IERC20Metadata(vaultTokens[i]).decimals()
//                 );
//             }
//         }
//         vm.stopPrank();
//     }

//     function testOffchain2() external {
//         vm.startPrank(u);
//         OmniDepositWrapper omniWrapper = new OmniDepositWrapper(
//             Constants.uniswapV3Router,
//             IUniswapV3Factory(Constants.uniswapV3Factory)
//         );
//         OmniDepositWrapper.Data memory d;

//         d.rootVault = 0x460d89CaD1E65d06Ebc18E206A09bBD02AE883e6;
//         d.tokenIn = 0x64aa3364F17a4D01c6f1751Fd97C2BD3D7e7f1D5;
//         d.amountIn = 1000 * 1e9; // 1000 OHM
//         d.from = u;
//         d.to = u;
//         d.router = Constants.uniswapV3Router;
//         d.wrapper = 0x231002439E1BD5b610C3d98321EA760002b9Ff64;
//         d.farm = address(0);
//         d.vaultOptions = new bytes(0);
//         d.minReminders = new uint256[](2);
//         d.callbacks = new bytes[](0);
//         deal(d.tokenIn, u, d.amountIn);
//         IERC20(d.tokenIn).safeApprove(address(omniWrapper), type(uint256).max);

//         uint256[] memory pricesX96 = new uint256[](2);
//         address[] memory tokens = IERC20RootVault(d.rootVault).vaultTokens();
//         pricesX96[0] = getUniswapPrice(d.tokenIn, tokens[0], 3000);
//         pricesX96[1] = getUniswapPrice(d.tokenIn, tokens[1], 3000);

//         d = omniWrapper.getOffchainData(d, pricesX96);
//         uint256[] memory swappingAmounts = new uint256[](2);
//         bytes[] memory callbacks = new bytes[](2);
//         uint256 index = 0;
//         for (uint256 i = 0; i < swappingAmounts.length; i++) {
//             swappingAmounts[i] = uint256(bytes32(d.callbacks[i]));
//             if (swappingAmounts[i] == 0) continue;
//             callbacks[index++] = abi.encodeWithSelector(
//                 ISwapRouter.exactInputSingle.selector,
//                 ISwapRouter.ExactInputSingleParams({
//                     tokenIn: d.tokenIn,
//                     tokenOut: tokens[i],
//                     amountIn: swappingAmounts[i],
//                     fee: 3000,
//                     deadline: type(uint256).max,
//                     sqrtPriceLimitX96: 0,
//                     amountOutMinimum: 0,
//                     recipient: address(omniWrapper)
//                 })
//             );
//         }
//         assembly {
//             mstore(callbacks, index)
//         }
//         d.router = Constants.uniswapV3Router;
//         d.callbacks = callbacks;
//         d.minLpAmount = (d.minLpAmount * 99) / 100;

//         {
//             (, uint256[] memory returnedAmounts) = omniWrapper.deposit(d);
//             address[] memory vaultTokens = IERC20RootVault(d.rootVault).vaultTokens();
//             for (uint256 i = 0; i < vaultTokens.length; i++) {
//                 console2.log(
//                     IERC20Metadata(vaultTokens[i]).symbol(),
//                     returnedAmounts[i],
//                     returnedAmounts[i] / 10**IERC20Metadata(vaultTokens[i]).decimals()
//                 );
//             }
//         }
//         vm.stopPrank();
//     }

//     function testOffchain3() external {
//         vm.startPrank(u);
//         OmniDepositWrapper omniWrapper = new OmniDepositWrapper(
//             Constants.uniswapV3Router,
//             IUniswapV3Factory(Constants.uniswapV3Factory)
//         );
//         OmniDepositWrapper.Data memory d;

//         d.rootVault = 0xCE0e8fC4d256CE8555ED5AACf3480677680651d7;
//         d.tokenIn = 0xae78736Cd615f374D3085123A210448E74Fc6393;
//         d.amountIn = 10 ether; // 10 reth
//         d.from = u;
//         d.to = u;
//         d.router = Constants.uniswapV3Router;
//         d.wrapper = 0x9B8058Fa941835D5F287680D2f569935356B9730;
//         d.farm = 0x7051126223a559E3500bd0843924d971f55F0533;
//         d.vaultOptions = new bytes(0);
//         d.minReminders = new uint256[](2);
//         d.callbacks = new bytes[](0);
//         deal(d.tokenIn, u, d.amountIn);
//         IERC20(d.tokenIn).safeApprove(address(omniWrapper), type(uint256).max);

//         uint256[] memory pricesX96 = new uint256[](2);
//         address[] memory tokens = IERC20RootVault(d.rootVault).vaultTokens();
//         pricesX96[0] = getUniswapPrice(d.tokenIn, tokens[0], 500);
//         pricesX96[1] = getUniswapPrice(d.tokenIn, tokens[1], 500);

//         d = omniWrapper.getOffchainData(d, pricesX96);
//         uint256[] memory swappingAmounts = new uint256[](2);
//         bytes[] memory callbacks = new bytes[](2);
//         uint256 index = 0;
//         for (uint256 i = 0; i < swappingAmounts.length; i++) {
//             swappingAmounts[i] = uint256(bytes32(d.callbacks[i]));
//             if (swappingAmounts[i] == 0) continue;
//             callbacks[index++] = abi.encodeWithSelector(
//                 ISwapRouter.exactInputSingle.selector,
//                 ISwapRouter.ExactInputSingleParams({
//                     tokenIn: d.tokenIn,
//                     tokenOut: tokens[i],
//                     amountIn: swappingAmounts[i],
//                     fee: 500,
//                     deadline: type(uint256).max,
//                     sqrtPriceLimitX96: 0,
//                     amountOutMinimum: 0,
//                     recipient: address(omniWrapper)
//                 })
//             );
//         }
//         assembly {
//             mstore(callbacks, index)
//         }
//         d.router = Constants.uniswapV3Router;
//         d.callbacks = callbacks;
//         d.minLpAmount = (d.minLpAmount * 99) / 100;
//         {
//             (, uint256[] memory returnedAmounts) = omniWrapper.deposit(d);
//             address[] memory vaultTokens = IERC20RootVault(d.rootVault).vaultTokens();
//             for (uint256 i = 0; i < vaultTokens.length; i++) {
//                 console2.log(
//                     IERC20Metadata(vaultTokens[i]).symbol(),
//                     returnedAmounts[i],
//                     returnedAmounts[i] / 10**IERC20Metadata(vaultTokens[i]).decimals()
//                 );
//             }
//         }
//         vm.stopPrank();
//     }

//     function testOffchain4() external {
//         vm.startPrank(u);
//         OmniDepositWrapper omniWrapper = new OmniDepositWrapper(
//             Constants.uniswapV3Router,
//             IUniswapV3Factory(Constants.uniswapV3Factory)
//         );
//         OmniDepositWrapper.Data memory d;

//         d.rootVault = 0x1FCD3926b6DFa2A90Fe49A383C732b31f1ee54eB;
//         d.tokenIn = Constants.usdc;
//         d.amountIn = 1e5 * 1e6; // 100k usdc
//         d.from = u;
//         d.to = u;
//         d.router = Constants.uniswapV3Router;
//         d.wrapper = address(0);
//         d.farm = address(0);
//         d.vaultOptions = new bytes(0);
//         d.minReminders = new uint256[](2);
//         d.callbacks = new bytes[](0);
//         deal(d.tokenIn, u, d.amountIn);
//         IERC20(d.tokenIn).safeApprove(address(omniWrapper), type(uint256).max);

//         uint256[] memory pricesX96 = new uint256[](2);
//         address[] memory tokens = IERC20RootVault(d.rootVault).vaultTokens();
//         pricesX96[0] = getUniswapPrice(d.tokenIn, tokens[0], 500);
//         pricesX96[1] = getUniswapPrice(d.tokenIn, tokens[1], 500);

//         d = omniWrapper.getOffchainData(d, pricesX96);
//         uint256[] memory swappingAmounts = new uint256[](2);
//         bytes[] memory callbacks = new bytes[](2);
//         uint256 index = 0;
//         for (uint256 i = 0; i < swappingAmounts.length; i++) {
//             swappingAmounts[i] = uint256(bytes32(d.callbacks[i]));
//             if (swappingAmounts[i] == 0) continue;
//             callbacks[index++] = abi.encodeWithSelector(
//                 ISwapRouter.exactInputSingle.selector,
//                 ISwapRouter.ExactInputSingleParams({
//                     tokenIn: d.tokenIn,
//                     tokenOut: tokens[i],
//                     amountIn: swappingAmounts[i],
//                     fee: 500,
//                     deadline: type(uint256).max,
//                     sqrtPriceLimitX96: 0,
//                     amountOutMinimum: 0,
//                     recipient: address(omniWrapper)
//                 })
//             );
//         }
//         assembly {
//             mstore(callbacks, index)
//         }
//         d.router = Constants.uniswapV3Router;
//         d.callbacks = callbacks;
//         d.minLpAmount = (d.minLpAmount * 99) / 100;
//         {
//             (, uint256[] memory returnedAmounts) = omniWrapper.deposit(d);
//             address[] memory vaultTokens = IERC20RootVault(d.rootVault).vaultTokens();
//             for (uint256 i = 0; i < vaultTokens.length; i++) {
//                 console2.log(
//                     IERC20Metadata(vaultTokens[i]).symbol(),
//                     returnedAmounts[i],
//                     returnedAmounts[i] / 10**IERC20Metadata(vaultTokens[i]).decimals()
//                 );
//             }
//         }
//         vm.stopPrank();
//     }
// }
