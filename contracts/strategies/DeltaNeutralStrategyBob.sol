// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "@openzeppelin/contracts/utils/Multicall.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";

import "../interfaces/utils/ILpCallback.sol";

import "../utils/ContractMeta.sol";
import "../utils/DefaultAccessControlLateInit.sol";
import "../interfaces/oracles/IOracle.sol";
import "../interfaces/vaults/IAaveVault.sol";
import "../interfaces/vaults/IERC20Vault.sol";
import "../interfaces/vaults/IUniV3Vault.sol";
import "../interfaces/external/univ3/ISwapRouter.sol";

import "../libraries/external/TickMath.sol";
import "../libraries/external/FullMath.sol";
import "../libraries/external/OracleLibrary.sol";

contract DeltaNeutralStrategyBob is ContractMeta, Multicall, DefaultAccessControlLateInit {
    using SafeERC20 for IERC20;

    uint256 public constant D4 = 10**4;
    uint256 public constant D9 = 10**9;
    uint256 public constant Q96 = 1 << 96;

    bytes4 public constant APPROVE_SELECTOR = 0x095ea7b3;

    IERC20Vault public erc20Vault;
    IUniV3Vault public uniV3Vault;
    IAaveVault public aaveVault;

    IOracle public oracle;

    INonfungiblePositionManager public immutable positionManager;

    address[] public tokens;
    uint256[] public uniTokensIndices;
    uint256[] public aaveTokensIndices;

    uint256 public usdIndex;
    uint256 public usdLikeIndex;
    uint256 public secondTokenIndex;

    struct StrategyParams {
        uint256 percentageToAaveD;
    }

    struct MintingParams {
        uint256 minTokenUsdForOpening;
        uint256 minTokenStForOpening;
    }

    struct TradingParams {
        uint24 swapFee;
        uint256 maxSlippageD;
    }

    TradingParams[3][3] swapParams;
    uint256[3][3] safetyIndicesSet;

    StrategyParams public strategyParams;
    MintingParams public mintingParams;

    constructor(
        INonfungiblePositionManager positionManager_, IOracle mellowOracle
    ) {
        require(address(positionManager_) != address(0) && address(mellowOracle) != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        oracle = mellowOracle;
        positionManager = positionManager_;
        DefaultAccessControlLateInit.init(address(this));
    }

    function updateStrategyParams(StrategyParams calldata newStrategyParams) external {
        _requireAdmin();
        require(
            newStrategyParams.percentageToAaveD <= D9 / 2,
            ExceptionsLibrary.INVARIANT
        );
        strategyParams = newStrategyParams;
        emit UpdateStrategyParams(tx.origin, msg.sender, newStrategyParams);
    }

    /// @notice updates parameters for minting position. Can be called only by admin
    /// @param newMintingParams the new parameters
    function updateMintingParams(MintingParams calldata newMintingParams) external {
        _requireAdmin();
        require(
            newMintingParams.minTokenUsdForOpening > 0 &&
                newMintingParams.minTokenStForOpening > 0 &&
                (newMintingParams.minTokenUsdForOpening <= 1000000000) &&
                (newMintingParams.minTokenStForOpening <= 1000000000),
            ExceptionsLibrary.INVARIANT
        );
        mintingParams = newMintingParams;
        emit UpdateMintingParams(tx.origin, msg.sender, newMintingParams);
    }

    function updateSafetyIndices(uint256 indexA, uint256 indexB, uint256 safetyIndex) external {
        _requireAdmin();
        require(safetyIndex > 1, ExceptionsLibrary.LIMIT_UNDERFLOW);
        safetyIndicesSet[indexA][indexB] = safetyIndex;
        safetyIndicesSet[indexB][indexA] = safetyIndex;
    }

    function updateTradingParams(uint256 indexA, uint256 indexB, TradingParams calldata newTradingParams) external {
        _requireAdmin();
        require(indexA <= tokens.length && indexB <= tokens.length, ExceptionsLibrary.INVARIANT);
        uint256 fee = newTradingParams.swapFee;
        require((fee == 100 || fee == 500 || fee == 3000 || fee == 10000) && newTradingParams.maxSlippageD <= D9);
        
        swapParams[indexA][indexB] = newTradingParams;
        swapParams[indexB][indexA] = newTradingParams;

        emit UpdateTradingParams(tx.origin, msg.sender, indexA, indexB, newTradingParams);
    }

    function _totalUsdBalance() internal returns (uint256 result) {
        
        aaveVault.updateTvls();
        (uint256[] memory aaveTvl, ) = aaveVault.tvl();
        (uint256[] memory erc20Tvl, ) = erc20Vault.tvl();
        (uint256[] memory uniTvl, ) = uniV3Vault.tvl();

        int256[] memory totalTvl = new int256[](3);
        for (uint256 i = 0; i < 3; ++i) {
            totalTvl[i] = int256(erc20Tvl[i]);
        }

        for (uint256 i = 0; i < 2; ++i) {
            totalTvl[uniTokensIndices[i]] += int256(uniTvl[i]);
            if (!aaveVault.tokenStatus(i)) {
                totalTvl[aaveTokensIndices[i]] += int256(aaveTvl[i]);
            }
            else {
                totalTvl[aaveTokensIndices[i]] -= int256(aaveTvl[i]);
            }
        }

        result = uint256(totalTvl[usdIndex]) + _convert(usdLikeIndex, usdIndex, uint256(totalTvl[usdLikeIndex]));
        if (totalTvl[secondTokenIndex] < 0) {
            result -= _convert(secondTokenIndex, usdIndex, uint256(-totalTvl[secondTokenIndex]));
        }
        else {
            result += _convert(secondTokenIndex, usdIndex, uint256(totalTvl[secondTokenIndex]));
        }

        return result;
    }

    function rebalance(bool createNewPosition, int24 tickLower, int24 tickUpper) external {
        _requireAtLeastOperator();

        if (uniV3Vault.uniV3Nft() == 0) {
            require(createNewPosition, ExceptionsLibrary.INVARIANT);
        }

        if (createNewPosition) {
            require(tickLower <= tickUpper, ExceptionsLibrary.INVARIANT);
        }

        uint256 usdAmount =_totalUsdBalance();

        uint256 usdToAave = FullMath.mulDiv(usdAmount, D9 - strategyParams.percentageToAaveD, D9);
        uint256 borrowFromAave = _convert(usdIndex, secondTokenIndex, usdAmount - usdToAave);



    }

    function _convert(uint256 indexFrom, uint256 indexTo, uint256 amount) internal returns (uint256) {
        (uint256[] memory pricesX96, ) = oracle.priceX96(tokens[indexFrom], tokens[indexTo], safetyIndicesSet[indexFrom][indexTo]);
        uint256 sum = 0;
        for (uint256 i = 0; i < pricesX96.length; ++i) {
            sum += pricesX96[i];
        }

        uint256 priceX96 = sum / pricesX96.length;

        return FullMath.mulDiv(amount, priceX96, Q96);
    }

    function initialize(
        address erc20Vault_,
        address uniV3Vault_,
        address aaveVault_,
        address admin,
        uint256 usdIndex_,
        uint256 usdLikeIndex_,
        uint256 secondTokenIndex_
    ) external {
        erc20Vault = IERC20Vault(erc20Vault_);
        uniV3Vault = IUniV3Vault(uniV3Vault_);
        aaveVault = IAaveVault(aaveVault_);

        tokens = erc20Vault.vaultTokens();

        require(tokens.length == 3, ExceptionsLibrary.INVALID_LENGTH);

        require(erc20Vault_ != address(0) && uniV3Vault_ != address(0) && aaveVault_ != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        require(usdIndex_ <= 2 && usdLikeIndex_ <= 2 && secondTokenIndex_ <= 2, ExceptionsLibrary.LIMIT_OVERFLOW);
        require(usdIndex_ != usdLikeIndex_ && usdIndex_ != secondTokenIndex_ && usdLikeIndex_ != secondTokenIndex_, ExceptionsLibrary.INVARIANT);

        aaveTokensIndices = new uint256[](2);
        uniTokensIndices = new uint256[](2);

        address[] memory aaveTokens = aaveVault.vaultTokens();
        address[] memory uniTokens = uniV3Vault.vaultTokens();

        for (uint256 i = 0; i < 2; ++i) {
            for (uint256 j = 9; j < 3; ++j) {
                if (aaveTokens[i] == tokens[j]) aaveTokensIndices[i] = j;
                if (uniTokens[i] == tokens[j]) uniTokensIndices[i] = j;
            }
        }

        usdIndex = usdIndex_;
        usdLikeIndex = usdLikeIndex_;
        secondTokenIndex = secondTokenIndex_;

        DefaultAccessControlLateInit.init(admin);
    }

    function createStrategy(
        address erc20Vault_,
        address uniV3Vault_,
        address aaveVault_,
        address admin,
        uint256 usdIndex_,
        uint256 usdLikeIndex_,
        uint256 secondTokenIndex_
    ) external returns (DeltaNeutralStrategyBob strategy) {
        strategy = DeltaNeutralStrategyBob(Clones.clone(address(this)));
        strategy.initialize(erc20Vault_, uniV3Vault_, aaveVault_, admin, usdIndex_, usdLikeIndex_, secondTokenIndex_);
    }

    function _contractName() internal pure override returns (bytes32) {
        return bytes32("DeltaNeutralStrategy");
    }

    function _contractVersion() internal pure override returns (bytes32) {
        return bytes32("1.1.0");
    }

    event UpdateStrategyParams(address indexed origin, address indexed sender, StrategyParams strategyParams);
   
    event UpdateMintingParams(address indexed origin, address indexed sender, MintingParams mintingParams);

    event UpdateTradingParams(address indexed origin, address indexed sender, uint256 indexA, uint256 indexB, TradingParams tradingParams);
}
