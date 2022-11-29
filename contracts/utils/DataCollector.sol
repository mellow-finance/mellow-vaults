// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.9;

import "../interfaces/external/univ3/INonfungiblePositionManager.sol";
import "../interfaces/external/univ3/IUniswapV3Pool.sol";
import "../interfaces/external/univ3/IUniswapV3Factory.sol";

import "../interfaces/vaults/IUniV3Vault.sol";
import "../interfaces/vaults/IERC20RootVaultGovernance.sol";

import "../libraries/external/TickMath.sol";

import "./UniV3Helper.sol";

contract DataCollector {
    INonfungiblePositionManager public immutable positionManager;
    IERC20RootVaultGovernance public immutable rootVaultGovernance;
    IVaultRegistry public immutable vaultRegistry;
    IUniswapV3Factory public immutable factory;
    address public immutable usdc;
    UniV3Helper public immutable uniV3Helper;
    uint256 public constant Q96 = 2**96;

    struct VaultRequest {
        uint256[] erc20VaultNfts;
        uint256[] moneyVaultNfts;
        uint256[] uniV3VaultNfts;
        uint24 fee;
        uint256 rootVaultNft;
        address user;
        uint256 domainPositionNft;
    }

    struct VaultResponse {
        uint256[] pricesToUsdcX96;
        uint256 tokenLpLimitPerUser;
        uint256 tokenLpLimit;
        uint256 userLpBalance;
        uint256 totalSupply;
        uint256[][] erc20VaultTvls;
        uint256[][] moneyVaultTvls;
        uint256[][] uniV3VaultTvls;
        uint256[][] uniV3VaultSpotTvls;
        uint256[] rootVaultTvl;
        uint256[] rootVaultSpotTvl;
        uint256[] domainPositionSpotTvl;
    }

    constructor(
        address usdc_,
        INonfungiblePositionManager positionManager_,
        IERC20RootVaultGovernance rootVaultGovernance_,
        IVaultRegistry vaultRegistry_,
        UniV3Helper uniV3Helper_
    ) {
        require(
            usdc_ != address(0) &&
                address(positionManager_) != address(0) &&
                address(rootVaultGovernance_) != address(0) &&
                address(vaultRegistry_) != address(0) &&
                address(uniV3Helper_) != address(0)
        );
        usdc = usdc_;
        positionManager = positionManager_;
        rootVaultGovernance = rootVaultGovernance_;
        vaultRegistry = vaultRegistry_;
        uniV3Helper = uniV3Helper_;
        factory = IUniswapV3Factory(positionManager_.factory());
    }

    function collect(VaultRequest[] memory requests) external view returns (VaultResponse[] memory responses) {
        uint256 n = requests.length;
        responses = new VaultResponse[](n);
        for (uint256 requestIndex = 0; requestIndex < n; ++requestIndex) {
            VaultRequest memory request = requests[requestIndex];
            VaultResponse memory response;
            address[] memory vaultTokens;
            {
                response.erc20VaultTvls = new uint256[][](request.erc20VaultNfts.length);
                for (uint256 i = 0; i < request.erc20VaultNfts.length; ++i) {
                    (response.erc20VaultTvls[i], ) = IVault(vaultRegistry.vaultForNft(request.erc20VaultNfts[i])).tvl();
                }
            }

            {
                response.moneyVaultTvls = new uint256[][](request.moneyVaultNfts.length);
                for (uint256 i = 0; i < request.moneyVaultNfts.length; ++i) {
                    (response.moneyVaultTvls[i], ) = IVault(vaultRegistry.vaultForNft(request.moneyVaultNfts[i])).tvl();
                }
            }

            {
                IERC20RootVault rootVault = IERC20RootVault(vaultRegistry.vaultForNft(request.rootVaultNft));
                (response.rootVaultTvl, ) = rootVault.tvl();
                response.rootVaultSpotTvl = response.rootVaultTvl;
                response.totalSupply = rootVault.totalSupply();
                response.userLpBalance = rootVault.balanceOf(request.user);
                vaultTokens = rootVault.vaultTokens();
            }

            {
                response.uniV3VaultTvls = new uint256[][](request.uniV3VaultNfts.length);
                response.uniV3VaultSpotTvls = new uint256[][](request.uniV3VaultNfts.length);
                for (uint256 i = 0; i < request.uniV3VaultNfts.length; ++i) {
                    IUniV3Vault uniV3Vault = IUniV3Vault(vaultRegistry.vaultForNft(request.uniV3VaultNfts[i]));
                    (response.uniV3VaultTvls[i], ) = uniV3Vault.tvl();
                    uint128 liquidity = 0;
                    uint256 fees0 = 0;
                    uint256 fees1 = 0;
                    if (response.uniV3VaultTvls[i][0] > 0 || response.uniV3VaultTvls[i][1] > 0) {
                        (, , liquidity, fees0, fees1) = uniV3Helper.calculatePositionInfo(
                            positionManager,
                            uniV3Vault.pool(),
                            uniV3Vault.uniV3Nft()
                        );
                        response.uniV3VaultSpotTvls[i] = uniV3Vault.liquidityToTokenAmounts(liquidity);
                        response.uniV3VaultSpotTvls[i][0] += fees0;
                        response.uniV3VaultSpotTvls[i][1] += fees1;
                    } else {
                        response.uniV3VaultSpotTvls[i] = new uint256[](2);
                    }
                    response.rootVaultSpotTvl[0] -= response.uniV3VaultTvls[i][0];
                    response.rootVaultSpotTvl[1] -= response.uniV3VaultTvls[i][1];
                    response.rootVaultSpotTvl[0] += response.uniV3VaultSpotTvls[i][0];
                    response.rootVaultSpotTvl[1] += response.uniV3VaultSpotTvls[i][1];
                }
            }

            IERC20RootVaultGovernance.StrategyParams memory limits = rootVaultGovernance.strategyParams(
                request.rootVaultNft
            );

            response.tokenLpLimit = limits.tokenLimit;
            response.tokenLpLimitPerUser = limits.tokenLimitPerAddress;
            {
                response.pricesToUsdcX96 = new uint256[](vaultTokens.length);
                for (uint256 i = 0; i < vaultTokens.length; i++) {
                    address token = vaultTokens[i];
                    if (token == usdc) {
                        response.pricesToUsdcX96[i] = Q96;
                    } else {
                        IUniswapV3Pool pool = IUniswapV3Pool(factory.getPool(usdc, token, request.fee));
                        (uint160 sqrtPriceX96, , , , , , ) = pool.slot0();
                        uint256 priceX96 = FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, Q96);
                        if (pool.token0() == usdc) {
                            priceX96 = FullMath.mulDiv(Q96, Q96, priceX96);
                        }
                        response.pricesToUsdcX96[i] = priceX96;
                    }
                }
            }

            if (request.domainPositionNft != 0) {
                uint128 liquidity = 0;
                uint256 fees0 = 0;
                uint256 fees1 = 0;
                IUniswapV3Pool pool = IUniswapV3Pool(factory.getPool(vaultTokens[0], vaultTokens[1], request.fee));
                (, , liquidity, fees0, fees1) = uniV3Helper.calculatePositionInfo(
                    positionManager,
                    pool,
                    request.domainPositionNft
                );
                response.domainPositionSpotTvl = uniV3Helper.liquidityToTokenAmounts(
                    liquidity,
                    pool,
                    request.domainPositionNft,
                    positionManager
                );
                response.domainPositionSpotTvl[0] += fees0;
                response.domainPositionSpotTvl[1] += fees1;
            }

            responses[requestIndex] = response;
        }
    }
}
