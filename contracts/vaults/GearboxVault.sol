// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.9;

import "./IntegrationVault.sol";
import "../interfaces/external/gearbox/ICreditFacade.sol";
import "../interfaces/external/gearbox/ICurveV1Adapter.sol";
import "../interfaces/external/gearbox/IConvexV1BoosterAdapter.sol";
import "../libraries/ExceptionsLibrary.sol";
import "../interfaces/vaults/IGearboxVault.sol";
import "../interfaces/vaults/IGearboxVaultGovernance.sol";

abstract contract GearboxVault is IGearboxVault, IntegrationVault {

    ICreditFacade private _creditFacade;

    address public primaryToken;
    address public secondaryToken;
    address public curveAdapter;
    address public convexAdapter;

    bool public isPrimaryTokenZero;
    
    function initialize(uint256 nft_, address primaryToken_, address secondaryToken_, address curveAdapter_, address convexAdapter_, address facade_, uint256 convexPoolId_) external {
        address[] memory vaultTokens = new address[](1);
        vaultTokens[0] = primaryToken_;
        _initialize(vaultTokens, nft_);

        primaryToken = primaryToken_;
        secondaryToken = secondaryToken_;
        curveAdapter = curveAdapter_;
        convexAdapter = convexAdapter_;

        _creditFacade = ICreditFacade(facade_);

        _verifyInstances(convexPoolId_);
    }

    function _verifyInstances(uint256 convexPoolId) internal {
        ICreditFacade creditFacade = _creditFacade;
        ICurveV1Adapter curveAdapter_ = ICurveV1Adapter(curveAdapter);
        IConvexV1BoosterAdapter convexAdapter_ = IConvexV1BoosterAdapter(convexAdapter);

        require(creditFacade.isTokenAllowed(primaryToken), ExceptionsLibrary.INVALID_TOKEN);
        creditFacade.enableToken(secondaryToken);

        address token0 = curveAdapter_.token0();
        address token1 = curveAdapter_.token1();
        require((token0 == primaryToken && token1 == secondaryToken) || (token1 == primaryToken && token0 == secondaryToken), ExceptionsLibrary.INVALID_TARGET);
        if (token0 == primaryToken) {
            isPrimaryTokenZero = true;
        }

        address lpToken = curveAdapter_.lp_token();
        IBooster.PoolInfo memory poolInfo = convexAdapter_.poolInfo(convexPoolId);
        require(lpToken == poolInfo.lptoken, ExceptionsLibrary.INVALID_TARGET);
    }

}