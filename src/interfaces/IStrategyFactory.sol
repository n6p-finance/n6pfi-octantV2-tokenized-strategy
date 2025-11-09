// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.24;

interface IStrategyFactory {
    // ===========================================
    // TYPE DEFINITIONS
    // ===========================================
    
    enum AdapterType {
        AAVE_V3,
        MORPHO_V2,
        SPARK,
        HYBRID
    }
    
    enum StrategyType {
        AAVE_V3,
        MORPHO_V2,
        SPARK,
        HYBRID
    }
    
    enum DeploymentType {
        SINGLE_STRATEGY,
        HYBRID_STRATEGY
    }
    
    struct StrategyConfig {
        address implementation;
        string namePrefix;
        bool enabled;
        address defaultAdapter;
    }
    
    struct Deployment {
        address vault;
        address strategy;
        address asset;
        StrategyType strategyType;
        DeploymentType deploymentType;
        uint256 deploymentBlock;
        uint256 donationBps;
        address adapter;
    }
    
    struct HybridConfig {
        address[] strategies;
        uint256[] weights;
        string name;
    }

    // ===========================================
    // STRATEGY DEPLOYMENT FUNCTIONS
    // ===========================================
    
    function deploySingleStrategy(
        address asset,
        address adapter,
        bytes memory initData
    ) external returns (address vault, address strategy);

    function deployHybridStrategy(
        address asset,
        address[] calldata adapters,
        uint256[] calldata weights,
        bytes[] calldata initDatas
    ) external returns (address vault, address router);

    function deployAdapter(
        AdapterType adapterType,
        bytes memory params
    ) external returns (address);

    function setGlobalPolicy(address policy) external;

    // ===========================================
    // DEPLOYMENT REGISTRY & VIEW FUNCTIONS
    // ===========================================
    
    function registry(uint256 id) external view returns (Deployment memory);
    
    function deployments(uint256 deploymentId) external view returns (Deployment memory);
    
    function getDeploymentByStrategy(address strategy) external view returns (Deployment memory);
    
    function isDeployedStrategy(address strategy) external view returns (bool);
    
    function getAssetDeployments(address asset) external view returns (Deployment[] memory);
    
    function getTotalDonated() external view returns (uint256);

    // ===========================================
    // STRATEGY MANAGEMENT FUNCTIONS
    // ===========================================
    
    function setStrategyImplementation(
        StrategyType strategyType,
        address implementation,
        string calldata namePrefix,
        bool enabled,
        address defaultAdapter
    ) external;
    
    function registerStrategy(
        address strategy,
        address asset
    ) external;
    
    function setAddresses(
        address management,
        address performanceFeeRecipient,
        address keeper
    ) external;
    
    function setDonationAddress(address donationAddress) external;
    
    function setDonationRouter(address donationRouter) external;
    
    function setEmergencyAdmin(address emergencyAdmin) external;

    // ===========================================
    // VIEW FUNCTIONS FOR CONFIGURATION
    // ===========================================
    
    function management() external view returns (address);
    
    function performanceFeeRecipient() external view returns (address);
    
    function keeper() external view returns (address);
    
    function emergencyAdmin() external view returns (address);
    
    function donationAddress() external view returns (address);
    
    function donationRouter() external view returns (address);
    
    function deploymentCount() external view returns (uint256);
    
    function strategyImplementations(StrategyType strategyType) external view returns (
        address implementation,
        string memory namePrefix,
        bool enabled,
        address defaultAdapter
    );

    // ===========================================
    // EVENTS
    // ===========================================
    
    event NewStrategy(
        uint256 indexed deploymentId,
        address indexed strategy, 
        address indexed asset,
        StrategyType strategyType,
        uint256 donationBps
    );
    
    event VaultDeployed(
        uint256 indexed deploymentId,
        address indexed vault,
        address indexed strategy,
        address asset,
        StrategyType strategyType,
        DeploymentType deploymentType,
        uint256 donationBps
    );
    
    event HybridVaultDeployed(
        uint256 indexed deploymentId,
        address indexed vault,
        address indexed router,
        address asset,
        address[] strategies,
        uint256[] weights,
        uint256 donationBps
    );
    
    event StrategyImplementationUpdated(
        StrategyType strategyType,
        address oldImplementation,
        address newImplementation
    );
    
    event DonationRouterUpdated(address oldRouter, address newRouter);
    event ManagementUpdated(address newManagement);
    event KeeperUpdated(address newKeeper);
    event PerformanceFeeRecipientUpdated(address newRecipient);
}