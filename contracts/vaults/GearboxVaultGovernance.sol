// SPDX-License-Identifier: BSL-1.1
pragma solidity 0.8.9;

import "../interfaces/vaults/IGearboxVaultGovernance.sol";
import "../libraries/ExceptionsLibrary.sol";
import "../libraries/CommonLibrary.sol";
import "../utils/ContractMeta.sol";
import "./VaultGovernance.sol";
import "../interfaces/external/gearbox/ICreditFacade.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract GearboxVaultGovernance is ContractMeta, IGearboxVaultGovernance, VaultGovernance {
    uint256 public constant D9 = 10**9;

    /// @notice Creates a new contract
    constructor(InternalParams memory internalParams_, DelayedProtocolParams memory delayedProtocolParams_)
        VaultGovernance(internalParams_)
    {
        require(delayedProtocolParams_.withdrawDelay <= 86400 * 30, ExceptionsLibrary.INVALID_VALUE);
        require(delayedProtocolParams_.univ3Adapter != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        require(delayedProtocolParams_.crv != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        require(delayedProtocolParams_.cvx != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        require(delayedProtocolParams_.uniswapRouter != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        require(delayedProtocolParams_.minSlippageD9 <= D9, ExceptionsLibrary.INVARIANT);
        require(delayedProtocolParams_.minSmallPoolsSlippageD9 <= D9, ExceptionsLibrary.INVARIANT);
        require(delayedProtocolParams_.minCurveSlippageD9 <= D9, ExceptionsLibrary.INVARIANT);
        _delayedProtocolParams = abi.encode(delayedProtocolParams_);
    }

    // -------------------  EXTERNAL, VIEW  -------------------

    /// @inheritdoc IGearboxVaultGovernance
    function delayedProtocolParams() public view returns (DelayedProtocolParams memory) {
        // params are initialized in constructor, so cannot be 0
        return abi.decode(_delayedProtocolParams, (DelayedProtocolParams));
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return super.supportsInterface(interfaceId) || interfaceId == type(IGearboxVaultGovernance).interfaceId;
    }

    /// @inheritdoc IGearboxVaultGovernance
    function stagedDelayedProtocolParams() external view returns (DelayedProtocolParams memory) {
        if (_stagedDelayedProtocolParams.length == 0) {
            return
                DelayedProtocolParams({
                    withdrawDelay: 0,
                    referralCode: 0,
                    univ3Adapter: address(0),
                    crv: address(0),
                    cvx: address(0),
                    minSlippageD9: 0,
                    minSmallPoolsSlippageD9: 0,
                    minCurveSlippageD9: 0,
                    uniswapRouter: address(0)
                });
        }
        return abi.decode(_stagedDelayedProtocolParams, (DelayedProtocolParams));
    }

    /// @inheritdoc IGearboxVaultGovernance
    function stagedDelayedProtocolPerVaultParams(uint256 nft)
        external
        view
        returns (DelayedProtocolPerVaultParams memory)
    {
        if (_stagedDelayedProtocolPerVaultParams[nft].length == 0) {
            return
                DelayedProtocolPerVaultParams({
                    primaryToken: address(0),
                    curveAdapter: address(0),
                    convexAdapter: address(0),
                    facade: address(0),
                    initialMarginalValueD9: 0
                });
        }
        return abi.decode(_stagedDelayedProtocolPerVaultParams[nft], (DelayedProtocolPerVaultParams));
    }

    /// @inheritdoc IGearboxVaultGovernance
    function operatorParams() external view returns (OperatorParams memory) {
        if (_operatorParams.length == 0) {
            return OperatorParams({largePoolFeeUsed: 500});
        }
        return abi.decode(_operatorParams, (OperatorParams));
    }

    /// @inheritdoc IGearboxVaultGovernance
    function delayedProtocolPerVaultParams(uint256 nft) external view returns (DelayedProtocolPerVaultParams memory) {
        if (_delayedProtocolPerVaultParams[nft].length == 0) {
            return
                DelayedProtocolPerVaultParams({
                    primaryToken: address(0),
                    curveAdapter: address(0),
                    convexAdapter: address(0),
                    facade: address(0),
                    initialMarginalValueD9: 0
                });
        }
        return abi.decode(_delayedProtocolPerVaultParams[nft], (DelayedProtocolPerVaultParams));
    }

    // -------------------  EXTERNAL, MUTATING  -------------------

    /// @inheritdoc IGearboxVaultGovernance
    function stageDelayedProtocolParams(DelayedProtocolParams memory params) external {
        require(params.withdrawDelay <= 86400 * 30, ExceptionsLibrary.INVALID_VALUE);
        require(params.univ3Adapter != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        require(params.crv != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        require(params.cvx != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        require(params.uniswapRouter != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        require(params.minSlippageD9 <= D9, ExceptionsLibrary.INVARIANT);
        require(params.minSmallPoolsSlippageD9 <= D9, ExceptionsLibrary.INVARIANT);
        require(params.minCurveSlippageD9 <= D9, ExceptionsLibrary.INVARIANT);
        _stageDelayedProtocolParams(abi.encode(params));
        emit StageDelayedProtocolParams(tx.origin, msg.sender, params, _delayedProtocolParamsTimestamp);
    }

    /// @inheritdoc IGearboxVaultGovernance
    function commitDelayedProtocolParams() external {
        _commitDelayedProtocolParams();
        emit CommitDelayedProtocolParams(
            tx.origin,
            msg.sender,
            abi.decode(_delayedProtocolParams, (DelayedProtocolParams))
        );
    }

    function stageDelayedProtocolPerVaultParams(uint256 nft, DelayedProtocolPerVaultParams calldata params) external {
        require(params.primaryToken != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        require(params.curveAdapter != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        require(params.convexAdapter != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        require(params.facade != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        require(params.initialMarginalValueD9 >= D9, ExceptionsLibrary.INVALID_VALUE);
        _stageDelayedProtocolPerVaultParams(nft, abi.encode(params));
        emit StageDelayedProtocolPerVaultParams(
            tx.origin,
            msg.sender,
            nft,
            params,
            _delayedStrategyParamsTimestamp[nft]
        );
    }

    /// @inheritdoc IGearboxVaultGovernance
    function commitDelayedProtocolPerVaultParams(uint256 nft) external {
        _commitDelayedProtocolPerVaultParams(nft);
        emit CommitDelayedProtocolPerVaultParams(
            tx.origin,
            msg.sender,
            nft,
            abi.decode(_delayedProtocolPerVaultParams[nft], (DelayedProtocolPerVaultParams))
        );
    }

    /// @inheritdoc IGearboxVaultGovernance
    function setOperatorParams(OperatorParams calldata params) external {
        require(params.largePoolFeeUsed == 500 || params.largePoolFeeUsed == 3000, ExceptionsLibrary.FORBIDDEN);
        _setOperatorParams(abi.encode(params));
        emit SetOperatorParams(tx.origin, msg.sender, params);
    }

    /// @inheritdoc IGearboxVaultGovernance
    function createVault(
        address[] memory vaultTokens_,
        address owner_,
        address helper_
    ) external returns (IGearboxVault vault, uint256 nft) {
        address vaddr;
        (vaddr, nft) = _createVault(owner_);
        IGearboxVault gearboxVault = IGearboxVault(vaddr);

        gearboxVault.initialize(nft, vaultTokens_, helper_);
        vault = IGearboxVault(vaddr);
    }

    // -------------------  INTERNAL, VIEW  -------------------

    function _contractName() internal pure override returns (bytes32) {
        return bytes32("GearboxVaultGovernance");
    }

    function _contractVersion() internal pure override returns (bytes32) {
        return bytes32("1.0.0");
    }

    // --------------------------  EVENTS  --------------------------

    /// @notice Emitted when new DelayedProtocolPerVaultParams are staged for commit
    /// @param origin Origin of the transaction (tx.origin)
    /// @param sender Sender of the call (msg.sender)
    /// @param nft VaultRegistry NFT of the vault
    /// @param params New params that were staged for commit
    /// @param when When the params could be committed
    event StageDelayedProtocolPerVaultParams(
        address indexed origin,
        address indexed sender,
        uint256 indexed nft,
        DelayedProtocolPerVaultParams params,
        uint256 when
    );

    /// @notice Emitted when new DelayedProtocolPerVaultParams are committed
    /// @param origin Origin of the transaction (tx.origin)
    /// @param sender Sender of the call (msg.sender)
    /// @param nft VaultRegistry NFT of the vault
    /// @param params New params that are committed
    event CommitDelayedProtocolPerVaultParams(
        address indexed origin,
        address indexed sender,
        uint256 indexed nft,
        DelayedProtocolPerVaultParams params
    );

    /// @notice Emitted when new DelayedProtocolParams are staged for commit
    /// @param origin Origin of the transaction (tx.origin)
    /// @param sender Sender of the call (msg.sender)
    /// @param params New params that were staged for commit
    /// @param when When the params could be committed
    event StageDelayedProtocolParams(
        address indexed origin,
        address indexed sender,
        DelayedProtocolParams params,
        uint256 when
    );

    /// @notice Emitted when new OperatorParams are set.
    /// @param origin Origin of the transaction (tx.origin)
    /// @param sender Sender of the call (msg.sender)
    /// @param params New params that are set
    event SetOperatorParams(address indexed origin, address indexed sender, OperatorParams params);

    /// @notice Emitted when new DelayedProtocolParams are committed
    /// @param origin Origin of the transaction (tx.origin)
    /// @param sender Sender of the call (msg.sender)
    /// @param params New params that are committed
    event CommitDelayedProtocolParams(address indexed origin, address indexed sender, DelayedProtocolParams params);
}
