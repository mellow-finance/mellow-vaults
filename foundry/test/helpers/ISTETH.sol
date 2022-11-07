// SPDX-License-Identifier: UNLICENSED
// !! THIS FILE WAS AUTOGENERATED BY abi-to-sol v0.6.6. SEE SOURCE BELOW. !!
pragma solidity ^0.8.9;

interface ISTETH {
    function resume() external;

    function name() external pure returns (string memory);

    function stop() external;

    function hasInitialized() external view returns (bool);

    function approve(address _spender, uint256 _amount) external returns (bool);

    function STAKING_CONTROL_ROLE() external view returns (bytes32);

    function initialize(
        address _depositContract,
        address _oracle,
        address _operators,
        address _treasury,
        address _insuranceFund
    ) external;

    function getInsuranceFund() external view returns (address);

    function totalSupply() external view returns (uint256);

    function getSharesByPooledEth(uint256 _ethAmount) external view returns (uint256);

    function isStakingPaused() external view returns (bool);

    function transferFrom(
        address _sender,
        address _recipient,
        uint256 _amount
    ) external returns (bool);

    function getOperators() external view returns (address);

    function getEVMScriptExecutor(bytes memory _script) external view returns (address);

    function setStakingLimit(uint256 _maxStakeLimit, uint256 _stakeLimitIncreasePerBlock) external;

    function RESUME_ROLE() external view returns (bytes32);

    function decimals() external pure returns (uint8);

    function getRecoveryVault() external view returns (address);

    function DEPOSIT_ROLE() external view returns (bytes32);

    function DEPOSIT_SIZE() external view returns (uint256);

    function getTotalPooledEther() external view returns (uint256);

    function PAUSE_ROLE() external view returns (bytes32);

    function increaseAllowance(address _spender, uint256 _addedValue) external returns (bool);

    function getTreasury() external view returns (address);

    function isStopped() external view returns (bool);

    function MANAGE_WITHDRAWAL_KEY() external view returns (bytes32);

    function getBufferedEther() external view returns (uint256);

    function receiveELRewards() external payable;

    function getELRewardsWithdrawalLimit() external view returns (uint256);

    function SIGNATURE_LENGTH() external view returns (uint256);

    function getWithdrawalCredentials() external view returns (bytes32);

    function getCurrentStakeLimit() external view returns (uint256);

    function setELRewardsWithdrawalLimit(uint16 _limitPoints) external;

    function handleOracleReport(uint256 _beaconValidators, uint256 _beaconBalance) external;

    function getStakeLimitFullInfo()
        external
        view
        returns (
            bool isStakingPaused,
            bool isStakingLimitSet,
            uint256 currentStakeLimit,
            uint256 maxStakeLimit,
            uint256 maxStakeLimitGrowthBlocks,
            uint256 prevStakeLimit,
            uint256 prevStakeBlockNumber
        );

    function SET_EL_REWARDS_WITHDRAWAL_LIMIT_ROLE() external view returns (bytes32);

    function getELRewardsVault() external view returns (address);

    function balanceOf(address _account) external view returns (uint256);

    function resumeStaking() external;

    function getFeeDistribution()
        external
        view
        returns (
            uint16 treasuryFeeBasisPoints,
            uint16 insuranceFeeBasisPoints,
            uint16 operatorsFeeBasisPoints
        );

    function getPooledEthByShares(uint256 _sharesAmount) external view returns (uint256);

    function setELRewardsVault(address _executionLayerRewardsVault) external;

    function allowRecoverability(address token) external view returns (bool);

    function MANAGE_PROTOCOL_CONTRACTS_ROLE() external view returns (bytes32);

    function appId() external view returns (bytes32);

    function getOracle() external view returns (address);

    function getInitializationBlock() external view returns (uint256);

    function setFeeDistribution(
        uint16 _treasuryFeeBasisPoints,
        uint16 _insuranceFeeBasisPoints,
        uint16 _operatorsFeeBasisPoints
    ) external;

    function setFee(uint16 _feeBasisPoints) external;

    function transferShares(address _recipient, uint256 _sharesAmount) external returns (uint256);

    function depositBufferedEther(uint256 _maxDeposits) external;

    function symbol() external pure returns (string memory);

    function MANAGE_FEE() external view returns (bytes32);

    function transferToVault(address _token) external;

    function canPerform(
        address _sender,
        bytes32 _role,
        uint256[] memory _params
    ) external view returns (bool);

    function submit(address _referral) external payable returns (uint256);

    function WITHDRAWAL_CREDENTIALS_LENGTH() external view returns (uint256);

    function decreaseAllowance(address _spender, uint256 _subtractedValue) external returns (bool);

    function getEVMScriptRegistry() external view returns (address);

    function PUBKEY_LENGTH() external view returns (uint256);

    function SET_EL_REWARDS_VAULT_ROLE() external view returns (bytes32);

    function transfer(address _recipient, uint256 _amount) external returns (bool);

    function getDepositContract() external view returns (address);

    function getBeaconStat()
        external
        view
        returns (
            uint256 depositedValidators,
            uint256 beaconValidators,
            uint256 beaconBalance
        );

    function removeStakingLimit() external;

    function BURN_ROLE() external view returns (bytes32);

    function getFee() external view returns (uint16 feeBasisPoints);

    function kernel() external view returns (address);

    function getTotalShares() external view returns (uint256);

    function allowance(address _owner, address _spender) external view returns (uint256);

    function isPetrified() external view returns (bool);

    function setProtocolContracts(
        address _oracle,
        address _treasury,
        address _insuranceFund
    ) external;

    function setWithdrawalCredentials(bytes32 _withdrawalCredentials) external;

    function STAKING_PAUSE_ROLE() external view returns (bytes32);

    function depositBufferedEther() external;

    function burnShares(address _account, uint256 _sharesAmount) external returns (uint256 newTotalShares);

    function sharesOf(address _account) external view returns (uint256);

    function pauseStaking() external;

    function getTotalELRewardsCollected() external view returns (uint256);

    event ScriptResult(address indexed executor, bytes script, bytes input, bytes returnData);
    event RecoverToVault(address indexed vault, address indexed token, uint256 amount);
    event TransferShares(address indexed from, address indexed to, uint256 sharesValue);
    event SharesBurnt(
        address indexed account,
        uint256 preRebaseTokenAmount,
        uint256 postRebaseTokenAmount,
        uint256 sharesAmount
    );
    event Stopped();
    event Resumed();
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event StakingPaused();
    event StakingResumed();
    event StakingLimitSet(uint256 maxStakeLimit, uint256 stakeLimitIncreasePerBlock);
    event StakingLimitRemoved();
    event ProtocolContactsSet(address oracle, address treasury, address insuranceFund);
    event FeeSet(uint16 feeBasisPoints);
    event FeeDistributionSet(
        uint16 treasuryFeeBasisPoints,
        uint16 insuranceFeeBasisPoints,
        uint16 operatorsFeeBasisPoints
    );
    event ELRewardsReceived(uint256 amount);
    event ELRewardsWithdrawalLimitSet(uint256 limitPoints);
    event WithdrawalCredentialsSet(bytes32 withdrawalCredentials);
    event ELRewardsVaultSet(address executionLayerRewardsVault);
    event Submitted(address indexed sender, uint256 amount, address referral);
    event Unbuffered(uint256 amount);
    event Withdrawal(
        address indexed sender,
        uint256 tokenAmount,
        uint256 sentFromBuffer,
        bytes32 indexed pubkeyHash,
        uint256 etherAmount
    );
}

// THIS FILE WAS AUTOGENERATED FROM THE FOLLOWING ABI JSON:
/*
[{"inputs":[],"name":"resume","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"name","outputs":[{"name":"","type":"string"}],"stateMutability":"pure","type":"function"},{"inputs":[],"name":"stop","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"hasInitialized","outputs":[{"name":"","type":"bool"}],"stateMutability":"view","type":"function"},{"inputs":[{"name":"_spender","type":"address"},{"name":"_amount","type":"uint256"}],"name":"approve","outputs":[{"name":"","type":"bool"}],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"STAKING_CONTROL_ROLE","outputs":[{"name":"","type":"bytes32"}],"stateMutability":"view","type":"function"},{"inputs":[{"name":"_depositContract","type":"address"},{"name":"_oracle","type":"address"},{"name":"_operators","type":"address"},{"name":"_treasury","type":"address"},{"name":"_insuranceFund","type":"address"}],"name":"initialize","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"getInsuranceFund","outputs":[{"name":"","type":"address"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"totalSupply","outputs":[{"name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[{"name":"_ethAmount","type":"uint256"}],"name":"getSharesByPooledEth","outputs":[{"name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"isStakingPaused","outputs":[{"name":"","type":"bool"}],"stateMutability":"view","type":"function"},{"inputs":[{"name":"_sender","type":"address"},{"name":"_recipient","type":"address"},{"name":"_amount","type":"uint256"}],"name":"transferFrom","outputs":[{"name":"","type":"bool"}],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"getOperators","outputs":[{"name":"","type":"address"}],"stateMutability":"view","type":"function"},{"inputs":[{"name":"_script","type":"bytes"}],"name":"getEVMScriptExecutor","outputs":[{"name":"","type":"address"}],"stateMutability":"view","type":"function"},{"inputs":[{"name":"_maxStakeLimit","type":"uint256"},{"name":"_stakeLimitIncreasePerBlock","type":"uint256"}],"name":"setStakingLimit","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"RESUME_ROLE","outputs":[{"name":"","type":"bytes32"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"decimals","outputs":[{"name":"","type":"uint8"}],"stateMutability":"pure","type":"function"},{"inputs":[],"name":"getRecoveryVault","outputs":[{"name":"","type":"address"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"DEPOSIT_ROLE","outputs":[{"name":"","type":"bytes32"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"DEPOSIT_SIZE","outputs":[{"name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"getTotalPooledEther","outputs":[{"name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"PAUSE_ROLE","outputs":[{"name":"","type":"bytes32"}],"stateMutability":"view","type":"function"},{"inputs":[{"name":"_spender","type":"address"},{"name":"_addedValue","type":"uint256"}],"name":"increaseAllowance","outputs":[{"name":"","type":"bool"}],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"getTreasury","outputs":[{"name":"","type":"address"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"isStopped","outputs":[{"name":"","type":"bool"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"MANAGE_WITHDRAWAL_KEY","outputs":[{"name":"","type":"bytes32"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"getBufferedEther","outputs":[{"name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"receiveELRewards","outputs":[],"stateMutability":"payable","type":"function"},{"inputs":[],"name":"getELRewardsWithdrawalLimit","outputs":[{"name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"SIGNATURE_LENGTH","outputs":[{"name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"getWithdrawalCredentials","outputs":[{"name":"","type":"bytes32"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"getCurrentStakeLimit","outputs":[{"name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[{"name":"_limitPoints","type":"uint16"}],"name":"setELRewardsWithdrawalLimit","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"name":"_beaconValidators","type":"uint256"},{"name":"_beaconBalance","type":"uint256"}],"name":"handleOracleReport","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"getStakeLimitFullInfo","outputs":[{"name":"isStakingPaused","type":"bool"},{"name":"isStakingLimitSet","type":"bool"},{"name":"currentStakeLimit","type":"uint256"},{"name":"maxStakeLimit","type":"uint256"},{"name":"maxStakeLimitGrowthBlocks","type":"uint256"},{"name":"prevStakeLimit","type":"uint256"},{"name":"prevStakeBlockNumber","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"SET_EL_REWARDS_WITHDRAWAL_LIMIT_ROLE","outputs":[{"name":"","type":"bytes32"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"getELRewardsVault","outputs":[{"name":"","type":"address"}],"stateMutability":"view","type":"function"},{"inputs":[{"name":"_account","type":"address"}],"name":"balanceOf","outputs":[{"name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"resumeStaking","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"getFeeDistribution","outputs":[{"name":"treasuryFeeBasisPoints","type":"uint16"},{"name":"insuranceFeeBasisPoints","type":"uint16"},{"name":"operatorsFeeBasisPoints","type":"uint16"}],"stateMutability":"view","type":"function"},{"inputs":[{"name":"_sharesAmount","type":"uint256"}],"name":"getPooledEthByShares","outputs":[{"name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[{"name":"_executionLayerRewardsVault","type":"address"}],"name":"setELRewardsVault","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"name":"token","type":"address"}],"name":"allowRecoverability","outputs":[{"name":"","type":"bool"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"MANAGE_PROTOCOL_CONTRACTS_ROLE","outputs":[{"name":"","type":"bytes32"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"appId","outputs":[{"name":"","type":"bytes32"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"getOracle","outputs":[{"name":"","type":"address"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"getInitializationBlock","outputs":[{"name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[{"name":"_treasuryFeeBasisPoints","type":"uint16"},{"name":"_insuranceFeeBasisPoints","type":"uint16"},{"name":"_operatorsFeeBasisPoints","type":"uint16"}],"name":"setFeeDistribution","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"name":"_feeBasisPoints","type":"uint16"}],"name":"setFee","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"name":"_recipient","type":"address"},{"name":"_sharesAmount","type":"uint256"}],"name":"transferShares","outputs":[{"name":"","type":"uint256"}],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"name":"_maxDeposits","type":"uint256"}],"name":"depositBufferedEther","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"symbol","outputs":[{"name":"","type":"string"}],"stateMutability":"pure","type":"function"},{"inputs":[],"name":"MANAGE_FEE","outputs":[{"name":"","type":"bytes32"}],"stateMutability":"view","type":"function"},{"inputs":[{"name":"_token","type":"address"}],"name":"transferToVault","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"name":"_sender","type":"address"},{"name":"_role","type":"bytes32"},{"name":"_params","type":"uint256[]"}],"name":"canPerform","outputs":[{"name":"","type":"bool"}],"stateMutability":"view","type":"function"},{"inputs":[{"name":"_referral","type":"address"}],"name":"submit","outputs":[{"name":"","type":"uint256"}],"stateMutability":"payable","type":"function"},{"inputs":[],"name":"WITHDRAWAL_CREDENTIALS_LENGTH","outputs":[{"name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[{"name":"_spender","type":"address"},{"name":"_subtractedValue","type":"uint256"}],"name":"decreaseAllowance","outputs":[{"name":"","type":"bool"}],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"getEVMScriptRegistry","outputs":[{"name":"","type":"address"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"PUBKEY_LENGTH","outputs":[{"name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"SET_EL_REWARDS_VAULT_ROLE","outputs":[{"name":"","type":"bytes32"}],"stateMutability":"view","type":"function"},{"inputs":[{"name":"_recipient","type":"address"},{"name":"_amount","type":"uint256"}],"name":"transfer","outputs":[{"name":"","type":"bool"}],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"getDepositContract","outputs":[{"name":"","type":"address"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"getBeaconStat","outputs":[{"name":"depositedValidators","type":"uint256"},{"name":"beaconValidators","type":"uint256"},{"name":"beaconBalance","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"removeStakingLimit","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"BURN_ROLE","outputs":[{"name":"","type":"bytes32"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"getFee","outputs":[{"name":"feeBasisPoints","type":"uint16"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"kernel","outputs":[{"name":"","type":"address"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"getTotalShares","outputs":[{"name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[{"name":"_owner","type":"address"},{"name":"_spender","type":"address"}],"name":"allowance","outputs":[{"name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"isPetrified","outputs":[{"name":"","type":"bool"}],"stateMutability":"view","type":"function"},{"inputs":[{"name":"_oracle","type":"address"},{"name":"_treasury","type":"address"},{"name":"_insuranceFund","type":"address"}],"name":"setProtocolContracts","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"name":"_withdrawalCredentials","type":"bytes32"}],"name":"setWithdrawalCredentials","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"STAKING_PAUSE_ROLE","outputs":[{"name":"","type":"bytes32"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"depositBufferedEther","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"name":"_account","type":"address"},{"name":"_sharesAmount","type":"uint256"}],"name":"burnShares","outputs":[{"name":"newTotalShares","type":"uint256"}],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"name":"_account","type":"address"}],"name":"sharesOf","outputs":[{"name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"pauseStaking","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"getTotalELRewardsCollected","outputs":[{"name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"stateMutability":"payable","type":"fallback"},{"anonymous":false,"inputs":[{"indexed":true,"name":"executor","type":"address"},{"indexed":false,"name":"script","type":"bytes"},{"indexed":false,"name":"input","type":"bytes"},{"indexed":false,"name":"returnData","type":"bytes"}],"name":"ScriptResult","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"name":"vault","type":"address"},{"indexed":true,"name":"token","type":"address"},{"indexed":false,"name":"amount","type":"uint256"}],"name":"RecoverToVault","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"name":"from","type":"address"},{"indexed":true,"name":"to","type":"address"},{"indexed":false,"name":"sharesValue","type":"uint256"}],"name":"TransferShares","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"name":"account","type":"address"},{"indexed":false,"name":"preRebaseTokenAmount","type":"uint256"},{"indexed":false,"name":"postRebaseTokenAmount","type":"uint256"},{"indexed":false,"name":"sharesAmount","type":"uint256"}],"name":"SharesBurnt","type":"event"},{"anonymous":false,"inputs":[],"name":"Stopped","type":"event"},{"anonymous":false,"inputs":[],"name":"Resumed","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"name":"from","type":"address"},{"indexed":true,"name":"to","type":"address"},{"indexed":false,"name":"value","type":"uint256"}],"name":"Transfer","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"name":"owner","type":"address"},{"indexed":true,"name":"spender","type":"address"},{"indexed":false,"name":"value","type":"uint256"}],"name":"Approval","type":"event"},{"anonymous":false,"inputs":[],"name":"StakingPaused","type":"event"},{"anonymous":false,"inputs":[],"name":"StakingResumed","type":"event"},{"anonymous":false,"inputs":[{"indexed":false,"name":"maxStakeLimit","type":"uint256"},{"indexed":false,"name":"stakeLimitIncreasePerBlock","type":"uint256"}],"name":"StakingLimitSet","type":"event"},{"anonymous":false,"inputs":[],"name":"StakingLimitRemoved","type":"event"},{"anonymous":false,"inputs":[{"indexed":false,"name":"oracle","type":"address"},{"indexed":false,"name":"treasury","type":"address"},{"indexed":false,"name":"insuranceFund","type":"address"}],"name":"ProtocolContactsSet","type":"event"},{"anonymous":false,"inputs":[{"indexed":false,"name":"feeBasisPoints","type":"uint16"}],"name":"FeeSet","type":"event"},{"anonymous":false,"inputs":[{"indexed":false,"name":"treasuryFeeBasisPoints","type":"uint16"},{"indexed":false,"name":"insuranceFeeBasisPoints","type":"uint16"},{"indexed":false,"name":"operatorsFeeBasisPoints","type":"uint16"}],"name":"FeeDistributionSet","type":"event"},{"anonymous":false,"inputs":[{"indexed":false,"name":"amount","type":"uint256"}],"name":"ELRewardsReceived","type":"event"},{"anonymous":false,"inputs":[{"indexed":false,"name":"limitPoints","type":"uint256"}],"name":"ELRewardsWithdrawalLimitSet","type":"event"},{"anonymous":false,"inputs":[{"indexed":false,"name":"withdrawalCredentials","type":"bytes32"}],"name":"WithdrawalCredentialsSet","type":"event"},{"anonymous":false,"inputs":[{"indexed":false,"name":"executionLayerRewardsVault","type":"address"}],"name":"ELRewardsVaultSet","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"name":"sender","type":"address"},{"indexed":false,"name":"amount","type":"uint256"},{"indexed":false,"name":"referral","type":"address"}],"name":"Submitted","type":"event"},{"anonymous":false,"inputs":[{"indexed":false,"name":"amount","type":"uint256"}],"name":"Unbuffered","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"name":"sender","type":"address"},{"indexed":false,"name":"tokenAmount","type":"uint256"},{"indexed":false,"name":"sentFromBuffer","type":"uint256"},{"indexed":true,"name":"pubkeyHash","type":"bytes32"},{"indexed":false,"name":"etherAmount","type":"uint256"}],"name":"Withdrawal","type":"event"}]
*/
