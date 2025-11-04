// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Strategy Interfaces
import {IStrategyInterface} from "./interfaces/IStrategyInterface.sol";
import {IOctantDonationRouter} from "./interfaces/IOctantDonationRouter.sol";

// Strategy Implementations
import {AaveV3Lender} from "./strategies/AaveV3Lender.sol";
import {MorphoV2Lender} from "./strategies/MorphoV2Lender.sol";
import {SparkLender} from "./strategies/SparkLender.sol";
import {HybridStrategyRouter} from "./strategies/HybridStrategyRouter.sol";

/**
 * @title YieldDonatingStrategyFactory
 * @notice Factory for deploying yield strategies with built-in Octant V2 public goods funding
 * @dev Implements NapFi modular architecture with fixed strategy types and adapter pattern
 */
contract YieldDonatingStrategyFactory is Ownable {
    using Clones for address;
    
    // ===========================================
    // ENUMS & STRUCTS
    // ===========================================
    
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
    
    // ===========================================
    // STORAGE
    // ===========================================
    
    // Core addresses from original YieldDonatingStrategyFactory
    address public management;
    address public performanceFeeRecipient;
    address public keeper;
    address public emergencyAdmin; // Previously called sms
    
    // Octant V2 Integration
    address public donationAddress;
    IOctantDonationRouter public donationRouter;
    
    // Strategy implementations
    mapping(StrategyType => StrategyConfig) public strategyImplementations;
    
    // Deployment tracking
    uint256 public deploymentCount;
    mapping(uint256 => Deployment) public deployments;
    mapping(address => uint256) public deploymentIds; // strategy/vault -> deploymentId
    
    // Asset deployment tracking (one strategy per asset for single strategies)
    mapping(address => mapping(StrategyType => address)) public assetDeployments;
    
    // ===========================================
    // MODIFIERS
    // ===========================================
    
    modifier onlyManagement() {
        require(msg.sender == management, "!management");
        _;
    }
    
    // ===========================================
    // CONSTRUCTOR - Enhanced with original parameters
    // ===========================================
    
    constructor(
        address _management,
        address _performanceFeeRecipient,
        address _keeper,
        address _emergencyAdmin,
        address _donationAddress
    ) {
        management = _management;
        performanceFeeRecipient = _performanceFeeRecipient;
        keeper = _keeper;
        emergencyAdmin = _emergencyAdmin;
        donationAddress = _donationAddress;
        
        _initializeStrategyImplementations();
    }
    
    // ===========================================
    // CORE STRATEGY DEPLOYMENT - Single Strategy
    // ===========================================
    
    /**
     * @notice Deploy a new single strategy vault (main entry point)
     * @param _strategyType Type of strategy to deploy
     * @param _asset The underlying asset for the strategy
     * @param _donationBps Donation percentage in basis points (10000 = 100%)
     * @param _strategyParams Additional strategy-specific parameters
     * @return strategy The deployed strategy address
     */
    function newStrategy(
        StrategyType _strategyType,
        address _asset,
        uint256 _donationBps,
        bytes calldata _strategyParams
    ) external onlyManagement returns (address strategy) {
        require(_asset != address(0), "Invalid asset");
        require(_donationBps <= 5000, "Max 50% donation");
        require(strategyImplementations[_strategyType].enabled, "Strategy type disabled");
        require(assetDeployments[_asset][_strategyType] == address(0), "Strategy already deployed for asset");
        
        // Deploy and configure strategy
        strategy = _deployStrategy(_strategyType, _asset, _strategyParams);
        _configureStrategy(strategy, _donationBps);
        
        // Track deployment
        uint256 deploymentId = _recordDeployment(
            strategy, // vault = strategy in TokenizedStrategy
            strategy,
            _asset,
            _strategyType,
            DeploymentType.SINGLE_STRATEGY,
            _donationBps,
            strategyImplementations[_strategyType].defaultAdapter
        );
        
        // Update asset deployments
        assetDeployments[_asset][_strategyType] = strategy;
        
        // Emit both original and enhanced events
        emit NewStrategy(deploymentId, strategy, _asset, _strategyType, _donationBps);
        emit VaultDeployed(
            deploymentId,
            strategy,
            strategy,
            _asset,
            _strategyType,
            DeploymentType.SINGLE_STRATEGY,
            _donationBps
        );
        
        return strategy;
    }
    
    /**
     * @notice Legacy deployment function for compatibility
     * @dev Uses Aave V3 as default strategy type
     */
    function newStrategy(
        address _compounderVault, // Used as lendingPool for Aave V3
        address _asset,
        string calldata _name
    ) external onlyManagement returns (address) {
        bytes memory strategyParams = abi.encode(_compounderVault, address(0), address(0));
        return newStrategy(StrategyType.AAVE_V3, _asset, 1000, strategyParams); // Default 10% donation
    }
    
    // ===========================================
    // HYBRID STRATEGY DEPLOYMENT
    // ===========================================
    
    /**
     * @notice Deploy a hybrid strategy vault that routes to multiple strategies
     * @param _asset The underlying asset
     * @param _strategies Array of strategy addresses to include
     * @param _weights Array of weights for each strategy (in basis points, must sum to 10000)
     * @param _donationBps Donation percentage in basis points
     * @param _name Name for the hybrid vault
     * @return vault The deployed vault address
     * @return router The hybrid strategy router address
     */
    function deployHybridStrategy(
        address _asset,
        address[] calldata _strategies,
        uint256[] calldata _weights,
        uint256 _donationBps,
        string calldata _name
    ) external onlyManagement returns (address vault, address router) {
        require(_asset != address(0), "Invalid asset");
        require(_strategies.length > 0, "No strategies provided");
        require(_strategies.length == _weights.length, "Mismatched arrays");
        require(_donationBps <= 5000, "Max 50% donation");
        
        // Verify all strategies use the same asset and are deployed by this factory
        for (uint256 i = 0; i < _strategies.length; i++) {
            address strategy = _strategies[i];
            require(deploymentIds[strategy] != 0, "Strategy not deployed by factory");
            require(IStrategyInterface(strategy).asset() == _asset, "Strategy asset mismatch");
        }
        
        // Verify weights sum to 10000 (100%)
        uint256 totalWeight;
        for (uint256 i = 0; i < _weights.length; i++) {
            totalWeight += _weights[i];
        }
        require(totalWeight == 10000, "Weights must sum to 10000");
        
        // Deploy hybrid router
        router = address(new HybridStrategyRouter(_asset, _name));
        
        // Initialize router with strategies and weights
        HybridStrategyRouter(router).initialize(_strategies, _weights);
        
        // Configure router as strategy
        _configureStrategy(router, _donationBps);
        
        // Set vault (router is the vault in this case)
        vault = router;
        
        // Track deployment
        uint256 deploymentId = _recordDeployment(
            vault,
            router,
            _asset,
            StrategyType.HYBRID,
            DeploymentType.HYBRID_STRATEGY,
            _donationBps,
            address(0) // No single adapter for hybrid
        );
        
        emit HybridVaultDeployed(
            deploymentId,
            vault,
            router,
            _asset,
            _strategies,
            _weights,
            _donationBps
        );
        
        return (vault, router);
    }
    
    // ===========================================
    // STRATEGY MANAGEMENT & CONFIGURATION
    // ===========================================
    
    /**
     * @notice Configure a strategy with factory settings and Octant donation
     * @param _strategy The strategy to configure
     * @param _donationBps Donation percentage in basis points
     */
    function _configureStrategy(address _strategy, uint256 _donationBps) internal {
        IStrategyInterface strategy = IStrategyInterface(_strategy);
        
        // Set core addresses
        strategy.setPerformanceFeeRecipient(performanceFeeRecipient);
        strategy.setKeeper(keeper);
        strategy.setPendingManagement(management);
        strategy.setEmergencyAdmin(emergencyAdmin);
        
        // Set performance fee and unlock time
        strategy.setPerformanceFee(500); // 5% performance fee
        strategy.setProfitMaxUnlockTime(60 * 60 * 24 * 3); // 3 days
        
        // Configure Octant donation if enabled
        if (_donationBps > 0 && donationAddress != address(0)) {
            strategy.setDonationPercentage(_donationBps);
            // If donation router is set, use it
            if (address(donationRouter) != address(0)) {
                strategy.setDonationRouter(address(donationRouter));
            }
        }
    }
    
    /**
     * @notice Deploy a strategy implementation
     */
    function _deployStrategy(
        StrategyType _strategyType,
        address _asset,
        bytes calldata _params
    ) internal returns (address) {
        StrategyConfig memory config = strategyImplementations[_strategyType];
        require(config.implementation != address(0), "Implementation not set");
        
        string memory name = string(
            abi.encodePacked(config.namePrefix, " ", IERC20(_asset).symbol(), " Vault")
        );
        
        if (_strategyType == StrategyType.AAVE_V3) {
            (address lendingPool, address router, address base) = abi.decode(_params, (address, address, address));
            return address(new AaveV3Lender(_asset, name, lendingPool, router, base));
        } else if (_strategyType == StrategyType.MORPHO_V2) {
            (address morpho, address router, address base) = abi.decode(_params, (address, address, address));
            return address(new MorphoV2Lender(_asset, name, morpho, router, base));
        } else if (_strategyType == StrategyType.SPARK) {
            (address sparkPool, address router, address base) = abi.decode(_params, (address, address, address));
            return address(new SparkLender(_asset, name, sparkPool, router, base));
        } else {
            revert("Unsupported strategy type");
        }
    }
    
    // ===========================================
    // DEPLOYMENT TRACKING
    // ===========================================
    
    /**
     * @notice Record a deployment in the registry
     */
    function _recordDeployment(
        address _vault,
        address _strategy,
        address _asset,
        StrategyType _strategyType,
        DeploymentType _deploymentType,
        uint256 _donationBps,
        address _adapter
    ) internal returns (uint256 deploymentId) {
        deploymentId = ++deploymentCount;
        
        deployments[deploymentId] = Deployment({
            vault: _vault,
            strategy: _strategy,
            asset: _asset,
            strategyType: _strategyType,
            deploymentType: _deploymentType,
            deploymentBlock: block.number,
            donationBps: _donationBps,
            adapter: _adapter
        });
        
        deploymentIds[_vault] = deploymentId;
        deploymentIds[_strategy] = deploymentId;
        
        return deploymentId;
    }
    
    // ===========================================
    // VIEW FUNCTIONS - Enhanced with original interface
    // ===========================================
    
    /**
     * @notice Check if a strategy was deployed by this factory (original interface)
     */
    function isDeployedStrategy(address _strategy) external view returns (bool) {
        return deploymentIds[_strategy] != 0;
    }
    
    /**
     * @notice Get deployment info by strategy address
     */
    function getDeploymentByStrategy(address _strategy) external view returns (Deployment memory) {
        uint256 deploymentId = deploymentIds[_strategy];
        require(deploymentId != 0, "Strategy not deployed by factory");
        return deployments[deploymentId];
    }
    
    /**
     * @notice Get all deployments for an asset
     */
    function getAssetDeployments(address _asset) external view returns (Deployment[] memory) {
        uint256 count = 0;
        
        // Count deployments for this asset
        for (uint256 i = 1; i <= deploymentCount; i++) {
            if (deployments[i].asset == _asset) {
                count++;
            }
        }
        
        // Populate array
        Deployment[] memory assetDeployments = new Deployment[](count);
        uint256 index = 0;
        
        for (uint256 i = 1; i <= deploymentCount; i++) {
            if (deployments[i].asset == _asset) {
                assetDeployments[index] = deployments[i];
                index++;
            }
        }
        
        return assetDeployments;
    }
    
    /**
     * @notice Get total donated amount across all strategies
     */
    function getTotalDonated() external view returns (uint256 totalDonated) {
        for (uint256 i = 1; i <= deploymentCount; i++) {
            Deployment memory deployment = deployments[i];
            if (deployment.donationBps > 0) {
                IStrategyInterface strategy = IStrategyInterface(deployment.strategy);
                totalDonated += strategy.totalDonated();
            }
        }
        return totalDonated;
    }
    
    // ===========================================
    // ADMIN FUNCTIONS - Enhanced with original interface
    // ===========================================
    
    /**
     * @notice Update factory addresses (original interface)
     */
    function setAddresses(
        address _management,
        address _performanceFeeRecipient,
        address _keeper
    ) external onlyManagement {
        management = _management;
        performanceFeeRecipient = _performanceFeeRecipient;
        keeper = _keeper;
        
        emit ManagementUpdated(_management);
        emit PerformanceFeeRecipientUpdated(_performanceFeeRecipient);
        emit KeeperUpdated(_keeper);
    }
    
    /**
     * @notice Update donation address (original interface)
     */
    function setDonationAddress(address _donationAddress) external onlyManagement {
        donationAddress = _donationAddress;
    }
    
    /**
     * @notice Update strategy implementation
     */
    function setStrategyImplementation(
        StrategyType _strategyType,
        address _implementation,
        string calldata _namePrefix,
        bool _enabled,
        address _defaultAdapter
    ) external onlyManagement {
        address oldImplementation = strategyImplementations[_strategyType].implementation;
        
        strategyImplementations[_strategyType] = StrategyConfig({
            implementation: _implementation,
            namePrefix: _namePrefix,
            enabled: _enabled,
            defaultAdapter: _defaultAdapter
        });
        
        emit StrategyImplementationUpdated(_strategyType, oldImplementation, _implementation);
    }
    
    /**
     * @notice Update Octant donation router
     */
    function setDonationRouter(address _donationRouter) external onlyManagement {
        address oldRouter = address(donationRouter);
        donationRouter = IOctantDonationRouter(_donationRouter);
        
        emit DonationRouterUpdated(oldRouter, _donationRouter);
    }
    
    /**
     * @notice Set emergency admin address
     */
    function setEmergencyAdmin(address _emergencyAdmin) external onlyManagement {
        emergencyAdmin = _emergencyAdmin;
    }
    
    // ===========================================
    // INITIALIZATION
    // ===========================================
    
    /**
     * @notice Initialize strategy implementations
     */
    function _initializeStrategyImplementations() internal {
        // These are placeholder addresses - will be set by management
        strategyImplementations[StrategyType.AAVE_V3] = StrategyConfig({
            implementation: address(0),
            namePrefix: "Aave V3",
            enabled: true,
            defaultAdapter: address(0)
        });
        
        strategyImplementations[StrategyType.MORPHO_V2] = StrategyConfig({
            implementation: address(0),
            namePrefix: "Morpho V2",
            enabled: true,
            defaultAdapter: address(0)
        });
        
        strategyImplementations[StrategyType.SPARK] = StrategyConfig({
            implementation: address(0),
            namePrefix: "Spark",
            enabled: true,
            defaultAdapter: address(0)
        });
        
        strategyImplementations[StrategyType.HYBRID] = StrategyConfig({
            implementation: address(0), // Hybrid uses custom deployment
            namePrefix: "Hybrid",
            enabled: true,
            defaultAdapter: address(0)
        });
    }
    
    // ===========================================
    // COMPATIBILITY FUNCTIONS
    // ===========================================
    
    /**
     * @notice Get deployment for asset (compatibility with original mapping)
     */
    function deployments(address _asset) external view returns (address) {
        // Return the first deployed strategy for this asset (Aave V3 by default)
        return assetDeployments[_asset][StrategyType.AAVE_V3];
    }
}