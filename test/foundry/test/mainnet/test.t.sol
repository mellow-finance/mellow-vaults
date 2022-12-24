// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "forge-std/console2.sol";

import "../../src/interfaces/external/univ3/IUniswapV3Pool.sol";
import "../../src/interfaces/external/chainlink/IAggregatorV3.sol";

import "../../src/ProtocolGovernance.sol";
import "../../src/MockOracle.sol";
import "../helpers/MockRouter.t.sol";
import "../../src/ERC20RootVaultHelper.sol";
import "../../src/VaultRegistry.sol";

import "../../src/vaults/GearboxVault.sol";
import "../../src/vaults/GearboxRootVault.sol";
import "../../src/vaults/ERC20Vault.sol";

import "../../src/vaults/GearboxVaultGovernance.sol";
import "../../src/vaults/ERC20VaultGovernance.sol";
import "../../src/vaults/ERC20RootVaultGovernance.sol";

import "../../src/utils/GearboxHelper.sol";

import "../../src/external/ConvexBaseRewardPool.sol";
import "../../src/interfaces/IDegenNft.sol";

import "../helpers/MockDistributor.t.sol";


contract ZTest is Test {

    function setUp() public {

    }

    uint256 internal constant steth_decimals = 18;
    bytes4 public constant TOKENS_PER_STETH_SELECTOR = 0x9576a0c8;

    function _stethToWsteth(uint256 amount) internal view returns (uint256) {
        address wsteth = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
        (bool res, bytes memory data) = wsteth.staticcall(abi.encodePacked(TOKENS_PER_STETH_SELECTOR));
        if (!res) {
            assembly {
                let returndata_size := mload(data)
                revert(add(32, data), returndata_size)
            }
        }
        uint256 tokensPerStEth = abi.decode(data, (uint256));
        return FullMath.mulDiv(amount, 10**steth_decimals, tokensPerStEth);
    }


    function test() public {
        IUniswapV3Pool q = IUniswapV3Pool(0xD340B57AAcDD10F96FC1CF10e15921936F41E29c);
        (uint160 sqrtPriceX96, , , , , ,) = q.slot0();

        IAggregatorV3 stEth = IAggregatorV3(0xCfE54B5cD566aB89272946F602D76Ea879CAb4a8);
        (, int256 answer, , , ) = stEth.latestRoundData();

        IAggregatorV3 weth = IAggregatorV3(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419);
        (, int256 answer2, , , ) = weth.latestRoundData();

        uint256 kek = 10**18;
        kek = FullMath.mulDiv(FullMath.mulDiv(_stethToWsteth(kek), 2**96, 10**18), uint256(answer), uint256(answer2));
        uint256 priceX96 = FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, 2**96);
        
        uint256 delta = 0;
        if (kek < priceX96) {
            delta = priceX96 - kek;
        }
        else {
            delta = kek - priceX96;
        }

        uint256 tickDelta = FullMath.mulDiv(delta, 10**4, 2**96);
        console2.log(tickDelta);

    }

    
}
