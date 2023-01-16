// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.9;
import "../libraries/ExceptionsLibrary.sol";
import "../interfaces/utils/IERC20RootVaultHelper.sol";
import "../libraries/CommonLibrary.sol";
import "../libraries/external/FullMath.sol";

contract ERC20RootVaultHelper is IERC20RootVaultHelper {
    function getTvlToken0(
        uint256[] calldata tvls,
        address[] calldata tokens,
        IOracle oracle
    ) external view returns (uint256 tvl0) {
        tvl0 = tvls[0];
        for (uint256 i = 1; i < tvls.length; i++) {
            (uint256[] memory pricesX96, ) = oracle.priceX96(tokens[0], tokens[i], 0x30);
            require(pricesX96.length > 0, ExceptionsLibrary.VALUE_ZERO);
            uint256 priceX96 = 0;
            for (uint256 j = 0; j < pricesX96.length; j++) {
                priceX96 += pricesX96[j];
            }
            priceX96 /= pricesX96.length;
            tvl0 += FullMath.mulDiv(tvls[i], CommonLibrary.Q96, priceX96);
        }
    }
}
