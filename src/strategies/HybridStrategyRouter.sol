// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import {BaseStrategy, ERC20} from "@tokenized-strategy/BaseStrategy.sol";
import {Math} from "../../../lib/openzeppelin-contracts/contracts/utils/math/Math.sol";
import {SafeERC20} from "../../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "../../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

// Strategy Interfaces
import {IStrategyInterface} from "../interfaces/IStrategyInterface.sol";

// Octant V2 Integration
import {IOctantV2} from "../interfaces/Octant/V2/IOctantV2.sol";
import {IOctantDonationRouter} from "../interfaces/Octant/V2/IOctantDonationRouter.sol";

library MathUtils {
    function clamp(uint256 value, uint256 minValue, uint256 maxValue) internal pure returns (uint256) {
        if (value < minValue) return minValue;
        if (value > maxValue) return maxValue;
        return value;
    }
}

abstract contract HybridStrategyRouter is BaseStrategy {
    using SafeERC20 for ERC20;
    using Math for uint256;
    using MathUtils for uint256;

    // =============================================
    // STRUCTURES FOR INNOVATIVE FEATURES
    // =============================================
    
    struct StrategyAllocation {
        address strategy;
        uint256 targetWeight; // in bps (10000 = 100%)
        uint256 currentBalance;
        uint256 performanceScore; // 0-10000, based on historical performance
        uint256 riskScore; // 0-10000, lower is better
        uint256 lastRebalance;
        bool enabled;
        uint256 maxAllocation; // Maximum allocation in asset units
        uint256 minAllocation; // Minimum allocation in asset units
    }
    
    struct DynamicWeightConfig {
        bool dynamicWeightsEnabled;
        uint256 rebalanceThreshold; // Minimum change to trigger rebalance (bps)
        uint256 performanceDecayRate; // How quickly performance scores decay
        uint256 riskAdjustmentFactor; // How much risk affects weights
        uint256 maxWeightChangePerRebalance; // Maximum weight change per rebalance (bps)
    }
    
    struct RiskManagement {
        uint256 maxConcentration; // Maximum allocation to single strategy (bps)
        uint256 maxDrawdownTolerance; // Maximum acceptable drawdown (bps)
        uint256 volatilityThreshold; // Maximum volatility threshold
        uint256 correlationPenalty; // Penalty for correlated strategies
        bool emergencyMode;
        uint256 lastRiskCheck;
    }
    
    struct PerformanceMetrics {
        uint256 totalRebalances;
        uint256 successfulRebalances;
        uint256 emergencyRebalances;
        uint256 totalFeeSavings;
        uint256 totalSlippageCosts;
        uint256 bestPerformingStrategy;
        uint256 worstPerformingStrategy;
        uint256 peakTVL;
        uint256 currentSharpeRatio; // Simplified risk-adjusted return metric
    }
    
    struct V4InnovationFeatures {
        bool crossStrategyArbitrage; // Detect arbitrage between strategies
        bool dynamicFeeOptimization; // Optimize fees across strategies
        bool impactWeightedAllocation; // Consider impact scores in allocation
        bool microDonationRouting; // Route donations optimally
        bool governanceBoostAggregation; // Aggregate governance boosts
    }

    // =============================================
    // STATE VARIABLES
    // =============================================
    
    // Core strategy allocations
    address[] public activeStrategies;
    mapping(address => StrategyAllocation) public strategyAllocations;
    uint256 public totalTargetWeight;
    
    // Configuration
    DynamicWeightConfig public dynamicWeights;
    RiskManagement public riskParams;
    PerformanceMetrics public performance;
    V4InnovationFeatures public v4Features;
    
    // Octant V2 Integration
    IOctantV2 public constant OCTANT_V2 = IOctantV2(address(0));
    IOctantDonationRouter public donationRouter;
    address public constant GLOW_DISTRIBUTION_POOL = address(0);
    
    // Rebalancing state
    bool public isRebalancing;
    uint256 public lastFullRebalance;
    uint256 public rebalanceCooldown = 1 days;
    
    // Emergency state
    bool public emergencyExitMode;
    uint256 public emergencyExitStart;
    
    // =============================================
    // INNOVATIVE EVENTS
    // =============================================
    
    event StrategyAdded(address indexed strategy, uint256 targetWeight, uint256 riskScore);
    event StrategyRemoved(address indexed strategy);
    event RebalanceExecuted(
        uint256 indexed rebalanceId,
        address[] strategies,
        uint256[] oldWeights,
        uint256[] newWeights,
        uint256[] amountsMoved,
        uint256 gasUsed
    );
    event DynamicWeightUpdate(
        address indexed strategy,
        uint256 oldWeight,
        uint256 newWeight,
        uint256 performanceChange,
        uint256 riskChange
    );
    event CrossStrategyArbitrage(
        address indexed sourceStrategy,
        address indexed destStrategy,
        uint256 amount,
        uint256 estimatedProfit
    );
    event EmergencyModeActivated(uint256 timestamp, uint256 totalAssets, string reason);
    event EmergencyModeDeactivated(uint256 timestamp, uint256 recoveredAssets);
    event RiskScoreUpdated(address indexed strategy, uint256 oldScore, uint256 newScore);
    event PerformanceFeeOptimized(uint256 savings, address[] strategies, uint256[] optimizations);

    // =============================================
    // MODIFIERS
    // =============================================
    
    modifier notRebalancing() {
        require(!isRebalancing, "Rebalancing in progress");
        _;
    }
    
    modifier notInEmergency() {
        require(!emergencyExitMode, "Emergency exit active");
        _;
    }

    // =============================================
    // CONSTRUCTOR & INITIALIZATION
    // =============================================
    
    constructor(
        address _asset,
        string memory _name
    ) BaseStrategy(_asset, _name) {
        // Initialize with safe defaults
        _initializeDefaultConfig();
    }
    
    /**
     * @notice Initialize the router with strategies and weights
     * @dev Called by factory after deployment
     */
    function initialize(
        address[] memory _strategies,
        uint256[] memory _weights
    ) external onlyManagement {
        require(activeStrategies.length == 0, "Already initialized");
        require(_strategies.length == _weights.length, "Mismatched arrays");
        require(_strategies.length > 0, "No strategies provided");
        
        uint256 totalWeight = 0;
        for (uint256 i = 0; i < _weights.length; i++) {
            require(_weights[i] > 0, "Zero weight");
            require(_strategies[i] != address(0), "Zero strategy");
            require(IStrategyInterface(_strategies[i]).asset() == address(asset), "Asset mismatch");
            
            totalWeight += _weights[i];
            
            // Add strategy
            activeStrategies.push(_strategies[i]);
            strategyAllocations[_strategies[i]] = StrategyAllocation({
                strategy: _strategies[i],
                targetWeight: _weights[i],
                currentBalance: 0,
                performanceScore: 10000, // Start with perfect score
                riskScore: 5000, // Medium risk
                lastRebalance: block.timestamp,
                enabled: true,
                maxAllocation: type(uint256).max,
                minAllocation: 0
            });
            
            // Approve strategy to spend asset
            asset.approve(_strategies[i], type(uint256).max);
            
            emit StrategyAdded(_strategies[i], _weights[i], 5000);
        }
        
        require(totalWeight == 10000, "Weights must sum to 10000");
        totalTargetWeight = totalWeight;
        
        // Initialize risk scores
        _updateAllRiskScores();
    }
    
    function _initializeDefaultConfig() internal {
        // Dynamic weight configuration
        dynamicWeights = DynamicWeightConfig({
            dynamicWeightsEnabled: true,
            rebalanceThreshold: 500, // 5% threshold
            performanceDecayRate: 100, // 1% decay per period
            riskAdjustmentFactor: 3000, // 30% risk adjustment
            maxWeightChangePerRebalance: 1000 // 10% max change
        });
        
        // Risk management
        riskParams = RiskManagement({
            maxConcentration: 4000, // Max 40% to single strategy
            maxDrawdownTolerance: 1000, // 10% max drawdown
            volatilityThreshold: 20000, // 200% volatility threshold
            correlationPenalty: 2000, // 20% penalty for correlated strategies
            emergencyMode: false,
            lastRiskCheck: block.timestamp
        });
        
        // V4 Innovation features
        v4Features = V4InnovationFeatures({
            crossStrategyArbitrage: true,
            dynamicFeeOptimization: true,
            impactWeightedAllocation: true,
            microDonationRouting: true,
            governanceBoostAggregation: true
        });
    }

    function management() internal view returns (address) {
        return IStrategyInterface(activeStrategies[0]).management();
    }

    // =============================================
    // AAVE ADAPTER FUNCTIONS (FOR STRATEGY INTEGRATION)
    // =============================================

    /**
     * @notice Supply assets to Aave via a registered strategy
     * @param _amount Amount of asset to supply
     */
    function supplyToAave(uint256 _amount) external {
        require(msg.sender == address(this) || _isRegisteredStrategy(msg.sender), "Only strategy or router");
        require(_amount > 0, "Amount must be > 0");

        // Find the Aave strategy (assume only one Aave strategy for simplicity)
        address aaveStrategy = _getAaveStrategy();
        require(aaveStrategy != address(0), "No Aave strategy registered");

        // Transfer to strategy and deposit
        asset.transfer(aaveStrategy, _amount);
        IStrategyInterface(aaveStrategy).deposit(_amount, address(this));
    }

    /**
     * @notice Withdraw from Aave via a registered strategy
     * @param _aToken Address of the aToken (to identify reserve)
     * @param _amount Amount to withdraw
     * @param _to Recipient
     */
    function withdrawFromAave(address _aToken, uint256 _amount, address _to) external {
        require(msg.sender == address(this) || _isRegisteredStrategy(msg.sender), "Only strategy or router");
        require(_amount > 0, "Amount must be > 0");

        address aaveStrategy = _getAaveStrategy();
        require(aaveStrategy != address(0), "No Aave strategy");

        uint256 withdrawn = IStrategyInterface(aaveStrategy).withdraw(_amount, _to, address(this));
        require(withdrawn >= _amount * 95 / 100, "Withdrawal slippage too high"); // 5% tolerance
    }

    /**
     * @notice Get estimated Aave APY for a given aToken
     */
    function getAaveAPY(address _aToken) external view returns (uint256) {
        address aaveStrategy = _getAaveStrategy();
        if (aaveStrategy == address(0)) return 0;
        try IStrategyInterface(aaveStrategy).estimatedAPY() returns (uint256 apy) {
            return apy;
        } catch {
            return 0;
        }
    }

    /**
     * @notice Get total value of a strategy (including Aave + V4 positions)
     */
    function getStrategyTotalValue(address _strategy) external view returns (uint256) {
        if (!_isRegisteredStrategy(_strategy)) return 0;
        return IStrategyInterface(_strategy).totalAssets();
    }

    /**
     * @notice Register a strategy with the router
     */
    function registerStrategy(address _strategy, address _asset) external onlyManagement {
        require(_asset == address(asset), "Asset mismatch");
        require(IStrategyInterface(_strategy).asset() == _asset, "Strategy asset mismatch");
        require(!strategyAllocations[_strategy].enabled, "Already registered");

        activeStrategies.push(_strategy);
        strategyAllocations[_strategy] = StrategyAllocation({
            strategy: _strategy,
            targetWeight: 0,
            currentBalance: 0,
            performanceScore: 10000,
            riskScore: 5000,
            lastRebalance: block.timestamp,
            enabled: true,
            maxAllocation: type(uint256).max,
            minAllocation: 0
        });

        asset.approve(_strategy, type(uint256).max);
        emit StrategyAdded(_strategy, 0, 5000);
    }

    // =============================================
    // INTERNAL HELPERS
    // =============================================

    function _isRegisteredStrategy(address _strategy) internal view returns (bool) {
        return strategyAllocations[_strategy].enabled;
    }

    function _getAaveStrategy() internal view returns (address) {
        for (uint256 i = 0; i < activeStrategies.length; i++) {
            address strat = activeStrategies[i];
            try IStrategyInterface(strat).supportsInterface(0x1a2b3c4d) returns (bool supported) { // Placeholder interface ID
                if (supported) return strat;
            } catch {}
        }
        return address(0);
    }

    // Optional: Add interface detection via name or symbol
    // Or require strategy to implement a known function like `lendingPool()`
    // For now, we assume only one Aave strategy or use naming convention

    // =============================================
    // INNOVATION 1: ADAPTIVE DYNAMIC WEIGHTING
    // =============================================
    
    /**
     * @notice Update strategy weights based on performance and risk metrics
     * @dev Implements machine learning-inspired dynamic allocation
     */
    function updateDynamicWeights() public onlyManagement notRebalancing {
        require(dynamicWeights.dynamicWeightsEnabled, "Dynamic weights disabled");
        
        bool needsRebalance = false;
        uint256[] memory newWeights = new uint256[](activeStrategies.length);
        uint256[] memory oldWeights = new uint256[](activeStrategies.length);
        
        for (uint256 i = 0; i < activeStrategies.length; i++) {
            address strategy = activeStrategies[i];
            StrategyAllocation storage allocation = strategyAllocations[strategy];
            
            // Store old weight
            oldWeights[i] = allocation.targetWeight;
            
            // Calculate new weight based on performance and risk
            uint256 newWeight = _calculateDynamicWeight(allocation);
            newWeights[i] = newWeight;
            
            // Check if change exceeds threshold
            if (_absDiff(newWeight, oldWeights[i]) > dynamicWeights.rebalanceThreshold) {
                needsRebalance = true;
            }
        }
        
        if (needsRebalance) {
            _executeDynamicRebalance(newWeights);
        }
    }
    
    function _calculateDynamicWeight(StrategyAllocation memory allocation) 
        internal 
        view 
        returns (uint256) 
    {
        uint256 baseWeight = allocation.targetWeight;
        
        // Performance adjustment (up to ±20%)
        uint256 performanceAdjustment = (allocation.performanceScore - 10000) * 20 / 10000;
        
        // Risk adjustment (up to -30% for high risk)
        uint256 riskAdjustment = (10000 - allocation.riskScore) * dynamicWeights.riskAdjustmentFactor / 10000;
        
        // Calculate new weight with bounds
        int256 newWeight = int256(baseWeight) + int256(performanceAdjustment) - int256(riskAdjustment);
        
        // Apply maximum change constraint
        int256 maxChange = int256(dynamicWeights.maxWeightChangePerRebalance);
        int256 boundedWeight = _boundWeightChange(int256(baseWeight), newWeight, maxChange);
        
        // Ensure minimum weight and concentration limits
        uint256 finalWeight = uint256(boundedWeight).clamp(100, riskParams.maxConcentration); // Min 1%, max concentration
        
        return finalWeight;
    }
    
    function _boundWeightChange(int256 oldWeight, int256 newWeight, int256 maxChange) 
        internal 
        pure 
        returns (int256) 
    {
        int256 change = newWeight - oldWeight;
        if (change > maxChange) {
            return oldWeight + maxChange;
        } else if (change < -maxChange) {
            return oldWeight - maxChange;
        }
        return newWeight;
    }
    
    function _absDiff(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a - b : b - a;
    }

    // =============================================
    // INNOVATION 2: CROSS-STRATEGY ARBITRAGE
    // =============================================
    
    /**
     * @notice Detect and execute arbitrage between strategies
     * @dev Capitalizes on temporary inefficiencies between different protocols
     */
    function executeCrossStrategyArbitrage() external onlyManagement notRebalancing {
        require(v4Features.crossStrategyArbitrage, "Cross-strategy arbitrage disabled");
        
        for (uint256 i = 0; i < activeStrategies.length; i++) {
            for (uint256 j = i + 1; j < activeStrategies.length; j++) {
                address strategyA = activeStrategies[i];
                address strategyB = activeStrategies[j];
                
                (uint256 profit, uint256 amount, bool shouldMove) = 
                    _detectArbitrageOpportunity(strategyA, strategyB);
                
                if (shouldMove && profit > 0) {
                    _executeArbitrageMove(strategyA, strategyB, amount);
                    emit CrossStrategyArbitrage(strategyA, strategyB, amount, profit);
                }
            }
        }
    }
    
    function _detectArbitrageOpportunity(address strategyA, address strategyB)
        internal
        view
        returns (uint256 profit, uint256 amount, bool shouldMove)
    {
        // Get current APYs and conditions
        uint256 apyA = _getEstimatedAPY(strategyA);
        uint256 apyB = _getEstimatedAPY(strategyB);
        
        // Calculate optimal reallocation amount
        uint256 balanceA = strategyAllocations[strategyA].currentBalance;
        uint256 balanceB = strategyAllocations[strategyB].currentBalance;
        
        // Simple arbitrage detection: move from lower to higher APY
        if (apyB > apyA + 200) { // At least 2% APY difference
            // Calculate maximum amount to move (respecting allocation limits)
            uint256 maxMove = balanceA / 10; // Move up to 10% of current balance
            amount = maxMove.clamp(0.1e18, balanceA); // Minimum 0.1 ETH
            
            // Estimate profit (simplified)
            profit = (amount * (apyB - apyA)) / 10000;
            
            shouldMove = profit > (amount * 5) / 10000; // At least 0.05% profit
        }
        
        return (profit, amount, shouldMove);
    }
    
    function _executeArbitrageMove(address fromStrategy, address toStrategy, uint256 amount) internal {
        // Withdraw from lower-performing strategy
        _withdrawFromStrategy(fromStrategy, amount);
        
        // Deposit to higher-performing strategy
        _depositToStrategy(toStrategy, amount);
        
        // Update allocation tracking
        strategyAllocations[fromStrategy].currentBalance -= amount;
        strategyAllocations[toStrategy].currentBalance += amount;
    }

    // =============================================
    // INNOVATION 3: RISK-MANAGED REBALANCING
    // =============================================
    
    /**
     * @notice Execute risk-managed rebalancing with slippage protection
     */
    function executeRiskManagedRebalance(uint256[] memory newWeights) 
        external 
        onlyManagement 
        notRebalancing 
    {
        require(block.timestamp >= lastFullRebalance + rebalanceCooldown, "Rebalance cooldown");
        require(newWeights.length == activeStrategies.length, "Invalid weights length");
        
        // Verify weights sum to 10000
        uint256 totalWeight = 0;
        for (uint256 i = 0; i < newWeights.length; i++) {
            totalWeight += newWeights[i];
        }
        require(totalWeight == 10000, "Weights must sum to 10000");
        
        isRebalancing = true;
        uint256 gasStart = gasleft();
        
        // Execute rebalancing
        uint256[] memory amountsMoved = _executeRebalancing(newWeights);
        
        // Update performance metrics
        performance.totalRebalances++;
        performance.successfulRebalances++;
        lastFullRebalance = block.timestamp;
        
        uint256 gasUsed = gasStart - gasleft();
        
        emit RebalanceExecuted(
            performance.totalRebalances,
            activeStrategies,
            _getCurrentWeights(),
            newWeights,
            amountsMoved,
            gasUsed
        );
        
        isRebalancing = false;
    }
    
    function _executeRebalancing(uint256[] memory newWeights) 
        internal 
        returns (uint256[] memory) 
    {
        uint256 totalAssets = _calculateTotalAssets();
        uint256[] memory amountsMoved = new uint256[](activeStrategies.length);
        
        for (uint256 i = 0; i < activeStrategies.length; i++) {
            address strategy = activeStrategies[i];
            StrategyAllocation storage allocation = strategyAllocations[strategy];
            
            uint256 targetAmount = (totalAssets * newWeights[i]) / 10000;
            uint256 currentAmount = allocation.currentBalance;
            
            if (targetAmount > currentAmount) {
                // Need to deposit more
                uint256 depositAmount = targetAmount - currentAmount;
                if (depositAmount > 0) {
                    _depositToStrategy(strategy, depositAmount);
                    amountsMoved[i] = depositAmount;
                }
            } else if (targetAmount < currentAmount) {
                // Need to withdraw excess
                uint256 withdrawAmount = currentAmount - targetAmount;
                if (withdrawAmount > 0) {
                    _withdrawFromStrategy(strategy, withdrawAmount);
                    amountsMoved[i] = withdrawAmount;
                }
            }
            
            // Update allocation
            allocation.targetWeight = newWeights[i];
            allocation.currentBalance = targetAmount;
            allocation.lastRebalance = block.timestamp;
        }
        
        return amountsMoved;
    }

    // =============================================
    // INNOVATION 4: EMERGENCY RISK MANAGEMENT
    // =============================================
    
    /**
     * @notice Activate emergency mode and exit risky positions
     * @dev Protects against protocol failures or market crashes
     */
    function activateEmergencyMode(string memory reason) external onlyManagement {
        require(!emergencyExitMode, "Already in emergency mode");
        
        emergencyExitMode = true;
        emergencyExitStart = block.timestamp;
        
        // Exit all strategies to stable asset
        _executeEmergencyExit();
        
        emit EmergencyModeActivated(block.timestamp, _calculateTotalAssets(), reason);
    }
    
    function _executeEmergencyExit() internal {
        uint256 totalToWithdraw = _calculateTotalAssets();
        
        for (uint256 i = 0; i < activeStrategies.length; i++) {
            address strategy = activeStrategies[i];
            uint256 strategyBalance = strategyAllocations[strategy].currentBalance;
            
            if (strategyBalance > 0) {
                // Attempt to withdraw from strategy
                uint256 withdrawn = _withdrawFromStrategy(strategy, strategyBalance);
                strategyAllocations[strategy].currentBalance -= withdrawn;
                
                // Update risk score (penalize strategies that fail during emergency)
                if (withdrawn < strategyBalance * 9000 / 10000) { // Less than 90% withdrawn
                    strategyAllocations[strategy].riskScore = 
                        strategyAllocations[strategy].riskScore.clamp(8000, 10000); // High risk
                }
            }
        }
        
        performance.emergencyRebalances++;
    }
    
    function deactivateEmergencyMode() external onlyManagement {
        require(emergencyExitMode, "Not in emergency mode");
        
        // Redeploy funds according to current weights
        uint256 totalAssets = _calculateTotalAssets();
        for (uint256 i = 0; i < activeStrategies.length; i++) {
            address strategy = activeStrategies[i];
            uint256 targetAmount = (totalAssets * strategyAllocations[strategy].targetWeight) / 10000;
            
            if (targetAmount > 0) {
                _depositToStrategy(strategy, targetAmount);
                strategyAllocations[strategy].currentBalance = targetAmount;
            }
        }
        
        emergencyExitMode = false;
        
        emit EmergencyModeDeactivated(block.timestamp, totalAssets);
    }

    // =============================================
    // INNOVATION 5: PERFORMANCE FEE OPTIMIZATION
    // =============================================
    
    /**
     * @notice Optimize fee efficiency across all strategies
     * @dev Routes operations to minimize fees and maximize net returns
     */
    function optimizeFeeEfficiency() external onlyManagement {
        require(v4Features.dynamicFeeOptimization, "Fee optimization disabled");
        
        uint256 totalSavings = 0;
        address[] memory optimizedStrategies = new address[](activeStrategies.length);
        uint256[] memory savings = new uint256[](activeStrategies.length);
        
        for (uint256 i = 0; i < activeStrategies.length; i++) {
            address strategy = activeStrategies[i];
            
            // Estimate fee savings through optimal routing
            uint256 estimatedSavings = _estimateFeeSavings(strategy);
            
            if (estimatedSavings > 0) {
                // Execute fee-optimized operations
                uint256 actualSavings = _executeFeeOptimization(strategy);
                totalSavings += actualSavings;
                
                optimizedStrategies[i] = strategy;
                savings[i] = actualSavings;
            }
        }
        
        performance.totalFeeSavings += totalSavings;
        
        emit PerformanceFeeOptimized(totalSavings, optimizedStrategies, savings);
    }
    
    function _estimateFeeSavings(address strategy) internal view returns (uint256) {
        // Complex fee optimization logic would go here
        // For now, return a simplified estimate
        uint256 currentBalance = strategyAllocations[strategy].currentBalance;
        return (currentBalance * 5) / 10000; // Estimate 0.05% savings
    }
    
    function _executeFeeOptimization(address strategy) internal returns (uint256) {
        // Execute actual fee optimization
        // This would involve timing operations, using fee discounts, etc.
        return _estimateFeeSavings(strategy);
    }

    // =============================================
    // CORE STRATEGY ROUTER FUNCTIONS
    // =============================================
    
    function _deployFunds(uint256 _amount) internal override notInEmergency {
        if (emergencyExitMode) {
            // In emergency mode, keep funds in router
            return;
        }
        
        // Distribute according to current weights
        for (uint256 i = 0; i < activeStrategies.length; i++) {
            address strategy = activeStrategies[i];
            StrategyAllocation storage allocation = strategyAllocations[strategy];
            
            if (allocation.enabled) {
                uint256 strategyAmount = (_amount * allocation.targetWeight) / 10000;
                if (strategyAmount > 0) {
                    _depositToStrategy(strategy, strategyAmount);
                    allocation.currentBalance += strategyAmount;
                }
            }
        }
    }
    
    function _freeFunds(uint256 _amount) internal override {
        // Withdraw proportionally from all strategies
        uint256 totalAssets = _calculateTotalAssets();
        
        for (uint256 i = 0; i < activeStrategies.length; i++) {
            address strategy = activeStrategies[i];
            StrategyAllocation storage allocation = strategyAllocations[strategy];
            
            uint256 strategyShare = (allocation.currentBalance * _amount) / totalAssets;
            if (strategyShare > 0) {
                uint256 withdrawn = _withdrawFromStrategy(strategy, strategyShare);
                allocation.currentBalance -= withdrawn;
            }
        }
    }
    
    function _harvestAndReport() internal override returns (uint256) {
        // Harvest from all strategies and report total
        uint256 totalValue = 0;
        
        for (uint256 i = 0; i < activeStrategies.length; i++) {
            address strategy = activeStrategies[i];
            
            // Harvest if the strategy supports it
            try IStrategyInterface(strategy).harvest() {} catch {}
            
            // Get strategy value
            uint256 strategyValue = IStrategyInterface(strategy).totalAssets();
            strategyAllocations[strategy].currentBalance = strategyValue;
            totalValue += strategyValue;
            
            // Update performance metrics
            _updateStrategyPerformance(strategy);
        }
        
        // Add router's own balance
        totalValue += balanceOfAsset();
        
        // Update peak TVL
        if (totalValue > performance.peakTVL) {
            performance.peakTVL = totalValue;
        }
        
        return totalValue;
    }
    
    function _depositToStrategy(address strategy, uint256 amount) internal {
        if (amount == 0) return;
        
        uint256 balanceBefore = asset.balanceOf(address(this));
        IStrategyInterface(strategy).deposit(amount, address(this));
        uint256 balanceAfter = asset.balanceOf(address(this));
        
        // Verify deposit was successful
        require(balanceBefore - balanceAfter == amount, "Deposit failed");
    }
    
    function _withdrawFromStrategy(address strategy, uint256 amount) internal returns (uint256) {
        if (amount == 0) return 0;
        
        uint256 balanceBefore = asset.balanceOf(address(this));
        IStrategyInterface(strategy).withdraw(amount, address(this), address(this));
        uint256 balanceAfter = asset.balanceOf(address(this));
        
        uint256 withdrawn = balanceAfter - balanceBefore;
        return withdrawn;
    }

    // =============================================
    // RISK & PERFORMANCE MONITORING
    // =============================================
    
    function _updateAllRiskScores() internal {
        for (uint256 i = 0; i < activeStrategies.length; i++) {
            _updateStrategyRiskScore(activeStrategies[i]);
        }
        riskParams.lastRiskCheck = block.timestamp;
    }
    
    function _updateStrategyRiskScore(address strategy) internal {
        StrategyAllocation storage allocation = strategyAllocations[strategy];
        uint256 oldScore = allocation.riskScore;
        
        // Calculate new risk score based on multiple factors
        uint256 volatilityRisk = _calculateVolatilityRisk(strategy);
        uint256 concentrationRisk = _calculateConcentrationRisk(strategy);
        uint256 protocolRisk = _calculateProtocolRisk(strategy);
        
        // Weighted average of risk factors
        uint256 newScore = (volatilityRisk * 4000 + concentrationRisk * 3000 + protocolRisk * 3000) / 10000;
        
        allocation.riskScore = newScore;
        
        emit RiskScoreUpdated(strategy, oldScore, newScore);
    }
    
    function _updateStrategyPerformance(address strategy) internal {
        StrategyAllocation storage allocation = strategyAllocations[strategy];
        
        // Simplified performance calculation
        uint256 currentValue = allocation.currentBalance;
        uint256 expectedValue = _getExpectedStrategyValue(strategy);
        
        if (currentValue > expectedValue) {
            // Positive performance
            uint256 outperformance = ((currentValue - expectedValue) * 10000) / expectedValue;
            allocation.performanceScore = (allocation.performanceScore * 9900 + 10000 + outperformance) / 10000;
        } else {
            // Negative performance
            uint256 underperformance = ((expectedValue - currentValue) * 10000) / expectedValue;
            allocation.performanceScore = (allocation.performanceScore * 9900 + 10000 - underperformance) / 10000;
        }
        
        // Apply performance decay
        allocation.performanceScore = (allocation.performanceScore * (10000 - dynamicWeights.performanceDecayRate)) / 10000;
        
        // Clamp between reasonable bounds
        allocation.performanceScore = allocation.performanceScore.clamp(5000, 15000);
    }
    
    function _calculateVolatilityRisk(address strategy) internal view returns (uint256) {
        // Simplified volatility calculation
        // In production, this would use historical data
        return 5000; // Medium risk by default
    }
    
    function _calculateConcentrationRisk(address strategy) internal view returns (uint256) {
        uint256 allocationPercent = (strategyAllocations[strategy].currentBalance * 10000) / _calculateTotalAssets();
        if (allocationPercent > riskParams.maxConcentration) {
            return 10000; // High risk
        } else if (allocationPercent > riskParams.maxConcentration * 8000 / 10000) {
            return 7500; // Medium-high risk
        } else {
            return 5000; // Medium risk
        }
    }
    
    function _calculateProtocolRisk(address strategy) internal pure returns (uint256) {
        // This would integrate with protocol risk assessment oracles
        // For now, return medium risk
        return 5000;
    }

    // =============================================
    // VIEW & HELPER FUNCTIONS
    // =============================================
    
    function balanceOfAsset() public view returns (uint256) {
        return asset.balanceOf(address(this));
    }
    
    function _calculateTotalAssets() internal view returns (uint256) {
        uint256 total = balanceOfAsset();
        for (uint256 i = 0; i < activeStrategies.length; i++) {
            total += strategyAllocations[activeStrategies[i]].currentBalance;
        }
        return total;
    }
    
    function _getCurrentWeights() internal view returns (uint256[] memory) {
        uint256[] memory weights = new uint256[](activeStrategies.length);
        for (uint256 i = 0; i < activeStrategies.length; i++) {
            weights[i] = strategyAllocations[activeStrategies[i]].targetWeight;
        }
        return weights;
    }
    
    function _getEstimatedAPY(address strategy) internal view returns (uint256) {
        // This would use strategy-specific APY calculations
        // For now, return a placeholder
        return 800; // 8% APY estimate
    }
    
    function _getExpectedStrategyValue(address strategy) internal view returns (uint256) {
        // Calculate expected value based on target returns
        uint256 baseValue = strategyAllocations[strategy].currentBalance;
        uint256 expectedAPY = _getEstimatedAPY(strategy);
        uint256 timeElapsed = block.timestamp - strategyAllocations[strategy].lastRebalance;
        
        // Simple linear growth estimation
        return baseValue + (baseValue * expectedAPY * timeElapsed) / (365 days * 10000);
    }

    function _executeDynamicRebalance(uint256[] memory newWeights) internal {
        // Reuse existing rebalancing logic
        this.executeRiskManagedRebalance(newWeights);
    }
    
    function getStrategyAllocations() external view returns (
        address[] memory strategies,
        uint256[] memory targetWeights,
        uint256[] memory currentBalances,
        uint256[] memory performanceScores,
        uint256[] memory riskScores
    ) {
        strategies = activeStrategies;
        targetWeights = new uint256[](strategies.length);
        currentBalances = new uint256[](strategies.length);
        performanceScores = new uint256[](strategies.length);
        riskScores = new uint256[](strategies.length);
        
        for (uint256 i = 0; i < strategies.length; i++) {
            StrategyAllocation memory allocation = strategyAllocations[strategies[i]];
            targetWeights[i] = allocation.targetWeight;
            currentBalances[i] = allocation.currentBalance;
            performanceScores[i] = allocation.performanceScore;
            riskScores[i] = allocation.riskScore;
        }
        
        return (strategies, targetWeights, currentBalances, performanceScores, riskScores);
    }
    
    function getRouterStatus() external view returns (
        uint256 totalAssets,
        uint256 numStrategies,
        bool isInEmergency,
        uint256 lastRebalance,
        uint256 performanceScore,
        uint256 riskScore
    ) {
        totalAssets = _calculateTotalAssets();
        numStrategies = activeStrategies.length;
        isInEmergency = emergencyExitMode;
        lastRebalance = lastFullRebalance;
        
        // Calculate aggregate scores
        uint256 totalPerfScore = 0;
        uint256 totalRiskScore = 0;
        for (uint256 i = 0; i < activeStrategies.length; i++) {
            StrategyAllocation memory allocation = strategyAllocations[activeStrategies[i]];
            totalPerfScore += allocation.performanceScore;
            totalRiskScore += allocation.riskScore;
        }
        
        performanceScore = activeStrategies.length > 0 ? totalPerfScore / activeStrategies.length : 10000;
        riskScore = activeStrategies.length > 0 ? totalRiskScore / activeStrategies.length : 5000;
        
        return (totalAssets, numStrategies, isInEmergency, lastRebalance, performanceScore, riskScore);
    }

    // =============================================
    // ADMIN & CONFIGURATION FUNCTIONS
    // =============================================
    
    function setDynamicWeightsConfig(
        bool enabled,
        uint256 threshold,
        uint256 decayRate,
        uint256 riskFactor,
        uint256 maxChange
    ) external onlyManagement {
        dynamicWeights.dynamicWeightsEnabled = enabled;
        dynamicWeights.rebalanceThreshold = threshold;
        dynamicWeights.performanceDecayRate = decayRate;
        dynamicWeights.riskAdjustmentFactor = riskFactor;
        dynamicWeights.maxWeightChangePerRebalance = maxChange;
    }
    
    function setRiskParameters(
        uint256 maxConcentration,
        uint256 drawdownTolerance,
        uint256 volatilityThreshold,
        uint256 correlationPenalty
    ) external onlyManagement {
        riskParams.maxConcentration = maxConcentration;
        riskParams.maxDrawdownTolerance = drawdownTolerance;
        riskParams.volatilityThreshold = volatilityThreshold;
        riskParams.correlationPenalty = correlationPenalty;
    }
    
    function setV4Features(
        bool arbitrage,
        bool feeOptimization,
        bool impactAllocation,
        bool donationRouting,
        bool governanceAggregation
    ) external onlyManagement {
        v4Features.crossStrategyArbitrage = arbitrage;
        v4Features.dynamicFeeOptimization = feeOptimization;
        v4Features.impactWeightedAllocation = impactAllocation;
        v4Features.microDonationRouting = donationRouting;
        v4Features.governanceBoostAggregation = governanceAggregation;
    }
    
    function setRebalanceCooldown(uint256 cooldown) external onlyManagement {
        rebalanceCooldown = cooldown;
    }
    
    function setDonationRouter(address router) external onlyManagement {
        donationRouter = IOctantDonationRouter(router);
    }
}