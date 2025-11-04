// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

import {BaseStrategy, ERC20} from "@tokenized-strategy/BaseStrategy.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// Aave V3 Interfaces
import {IAToken} from "./interfaces/Aave/V3/IAtoken.sol";
import {IStakedAave} from "./interfaces/Aave/V3/IStakedAave.sol";
import {IPool} from "./interfaces/Aave/V3/IPool.sol";
import {IRewardsController} from "./interfaces/Aave/V3/IRewardsController.sol";

// Adapter Integration
import {AaveAdapterV4Enhanced} from "./AaveAdapterV4Enhanced.sol";

// Octant V2 Integration
import {IOctantV2} from "./interfaces/OctantV2/IOctantV2.sol";

contract AaveV4LeveragedStrategy is BaseStrategy {
    using SafeERC20 for ERC20;
    using Math for uint256;

    // Aave Constants
    IStakedAave internal constant stkAave = IStakedAave(0x4da27a545c0c5B758a6BA100e3a049001de870f5);
    address internal constant AAVE = address(0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9);
    
    // Octant V2 Integration
    IOctantV2 public constant OCTANT_V2 = IOctantV2(0x...);
    address public constant GLOW_DISTRIBUTION_POOL = address(0x...);

    // Adapter Integration
    AaveAdapterV4Enhanced public immutable aaveAdapter;

    // Core Aave contracts
    IPool public immutable lendingPool;
    IRewardsController public immutable rewardsController;
    IAToken public immutable aToken;

    // =============================================
    // LEVERAGE CONFIGURATION & STATE
    // =============================================
    
    struct LeverageConfig {
        uint256 targetLeverage; // 10000 = 1x, 20000 = 2x, etc. (basis points)
        uint256 maxLeverage;    // Maximum allowed leverage (50000 = 5x)
        uint256 minLeverage;    // Minimum leverage for operations
        uint256 healthFactorTarget; // Minimum health factor (15000 = 1.5x)
        uint256 healthFactorEmergency; // Emergency threshold (11000 = 1.1x)
        uint256 leverageTolerance; // Allowed deviation from target (500 = 5%)
        uint256 maxIterations;  // Maximum loops per transaction
        bool autoLeverageEnabled; // Automatic leverage maintenance
    }
    
    LeverageConfig public leverageConfig;
    
    struct LeveragePosition {
        uint256 totalSupplied;
        uint256 totalBorrowed;
        uint256 currentLeverage;
        uint256 healthFactor;
        uint256 lastRebalance;
        bool isLeveraged;
    }
    
    LeveragePosition public position;
    
    // Borrow asset (same as deposit asset for simplicity, could be different)
    address public borrowAsset;
    
    // =============================================
    // RISK MANAGEMENT & SAFETY PARAMETERS
    // =============================================
    
    struct RiskParameters {
        uint256 maxSingleLoopAmount; // Maximum amount per loop iteration
        uint256 rebalanceCooldown; // Minimum time between rebalances
        uint256 maxGasForLoop; // Maximum gas to spend on looping
        uint256 slippageTolerance; // Slippage for swaps (if needed)
    }
    
    RiskParameters public riskParams;
    
    // Emergency state
    bool public emergencyDeleveraging;
    uint256 public lastEmergencyCheck;
    
    // =============================================
    // PERFORMANCE TRACKING
    // =============================================
    
    struct PerformanceMetrics {
        uint256 totalLoopsExecuted;
        uint256 totalDeleverages;
        uint256 maxLeverageAchieved;
        uint256 minHealthFactorRecorded;
        uint256 totalInterestPaid;
        uint256 totalInterestEarned;
    }
    
    PerformanceMetrics public performance;
    
    // =============================================
    // EVENTS
    // =============================================
    
    event LeverageIncreased(uint256 supplied, uint256 borrowed, uint256 newLeverage, uint256 healthFactor);
    event LeverageDecreased(uint256 repaid, uint256 withdrawn, uint256 newLeverage, uint256 healthFactor);
    event EmergencyDeleverage(uint256 healthFactor, uint256 leverageBefore, uint256 leverageAfter);
    event LeverageConfigUpdated(uint256 targetLeverage, uint256 maxLeverage, uint256 healthFactorTarget);
    event RebalanceExecuted(uint256 leverageBefore, uint256 leverageAfter, uint256 iterations);
    event LiquidationRisk(uint256 healthFactor, uint256 timestamp);
    
    // =============================================
    // MODIFIERS
    // =============================================
    
    modifier onlySafeLeverage() {
        require(position.healthFactor >= leverageConfig.healthFactorEmergency, "Health factor too low");
        _;
    }
    
    modifier onlyAfterCooldown() {
        require(block.timestamp >= position.lastRebalance + riskParams.rebalanceCooldown, "Rebalance cooldown");
        _;
    }
    
    // =============================================
    // CONSTRUCTOR & INITIALIZATION
    // =============================================
    
    constructor(
        address _asset,
        string memory _name,
        address _lendingPool,
        address _aaveAdapter,
        uint256 _initialTargetLeverage,
        address _borrowAsset
    ) BaseStrategy(_asset, _name) {
        lendingPool = IPool(_lendingPool);
        aToken = IAToken(lendingPool.getReserveData(_asset).aTokenAddress);
        require(address(aToken) != address(0), "!aToken");

        aaveAdapter = AaveAdapterV4Enhanced(_aaveAdapter);
        rewardsController = aToken.getIncentivesController();
        borrowAsset = _borrowAsset;

        // Initialize leverage configuration
        _initializeLeverageConfig(_initialTargetLeverage);
        
        // Initialize risk parameters
        _initializeRiskParameters();
        
        // Approvals
        asset.safeApprove(address(lendingPool), type(uint256).max);
        asset.safeApprove(address(OCTANT_V2), type(uint256).max);
        asset.safeApprove(address(_aaveAdapter), type(uint256).max);
        
        // Register with adapter
        _registerWithAdapter();
    }
    
    function _initializeLeverageConfig(uint256 _initialTargetLeverage) internal {
        require(_initialTargetLeverage >= 10000 && _initialTargetLeverage <= 50000, "Invalid leverage");
        
        leverageConfig = LeverageConfig({
            targetLeverage: _initialTargetLeverage,
            maxLeverage: 50000, // 5x maximum
            minLeverage: 10000, // 1x minimum
            healthFactorTarget: 15000, // 1.5x target
            healthFactorEmergency: 11000, // 1.1x emergency
            leverageTolerance: 500, // 5% tolerance
            maxIterations: 10,
            autoLeverageEnabled: true
        });
    }
    
    function _initializeRiskParameters() internal {
        riskParams = RiskParameters({
            maxSingleLoopAmount: 100_000 * 1e18, // $100k per loop
            rebalanceCooldown: 1 hours,
            maxGasForLoop: 1_000_000,
            slippageTolerance: 50 // 0.5%
        });
    }
    
    function _registerWithAdapter() internal {
        aaveAdapter.registerStrategy(address(this), address(asset));
    }

    // =============================================
    // LEVERAGE ENGINE CORE FUNCTIONS
    // =============================================
    
    /**
     * @notice Main function to deploy funds with leverage
     * @param _amount Amount to deploy (will be leveraged up)
     */
    function _deployFunds(uint256 _amount) internal override {
        if (_amount == 0) return;
        
        // Supply initial collateral
        _supplyToAave(_amount);
        
        // Apply leverage if enabled and conditions are safe
        if (leverageConfig.autoLeverageEnabled && _isLeverageSafe()) {
            _applyLeverage(_amount);
        }
        
        _updatePositionState();
    }
    
    /**
     * @notice Apply leverage through iterative borrowing and supplying
     * @param _initialAmount Initial collateral amount
     */
    function _applyLeverage(uint256 _initialAmount) internal {
        uint256 currentLeverage = position.currentLeverage;
        uint256 targetLeverage = leverageConfig.targetLeverage;
        
        // Only leverage up if current leverage is below target
        if (currentLeverage >= targetLeverage) return;
        
        uint256 iterations = 0;
        uint256 gasAtStart = gasleft();
        
        while (currentLeverage < targetLeverage && 
               iterations < leverageConfig.maxIterations &&
               gasleft() > riskParams.maxGasForLoop) {
            
            // Calculate how much we can borrow to reach target leverage
            uint256 borrowAmount = _calculateOptimalBorrowAmount(currentLeverage, targetLeverage);
            
            // Safety check: don't borrow more than reasonable single operation
            borrowAmount = borrowAmount.min(riskParams.maxSingleLoopAmount);
            
            if (borrowAmount == 0) break;
            
            // Execute borrow and supply loop
            _executeLeverageLoop(borrowAmount);
            
            // Update state
            _updatePositionState();
            currentLeverage = position.currentLeverage;
            
            iterations++;
            
            // Safety: check health factor after each iteration
            if (position.healthFactor < leverageConfig.healthFactorEmergency) {
                _emergencyDeleverage();
                break;
            }
        }
        
        performance.totalLoopsExecuted += iterations;
        emit RebalanceExecuted(currentLeverage, position.currentLeverage, iterations);
    }
    
    /**
     * @notice Execute single leverage loop: borrow -> supply as collateral
     * @param _borrowAmount Amount to borrow in this iteration
     */
    function _executeLeverageLoop(uint256 _borrowAmount) internal {
        // Borrow from Aave
        _borrowFromAave(_borrowAmount);
        
        // Supply borrowed amount as additional collateral
        _supplyToAave(_borrowAmount);
        
        // Update performance metrics
        performance.totalInterestPaid += _calculateBorrowCost(_borrowAmount);
    }
    
    /**
     * @notice Free funds with proper deleveraging if needed
     * @param _amount Amount to free (in underlying asset terms)
     */
    function _freeFunds(uint256 _amount) internal override {
        if (_amount == 0) return;
        
        uint256 currentLeverage = position.currentLeverage;
        
        // If we're leveraged, we need to deleverage first
        if (currentLeverage > leverageConfig.minLeverage) {
            uint256 deleverageAmount = _calculateDeleverageAmount(_amount, currentLeverage);
            _deleverage(deleverageAmount);
        }
        
        // Withdraw the requested amount
        _withdrawFromAave(_amount);
        
        _updatePositionState();
    }
    
    /**
     * @notice Systematic deleveraging to reduce exposure
     * @param _amount Amount to deleverage (in underlying asset terms)
     */
    function _deleverage(uint256 _amount) internal {
        uint256 iterations = 0;
        uint256 remainingAmount = _amount;
        
        while (remainingAmount > 0 && 
               iterations < leverageConfig.maxIterations &&
               position.currentLeverage > leverageConfig.minLeverage) {
            
            uint256 loopAmount = remainingAmount.min(riskParams.maxSingleLoopAmount);
            
            // Withdraw collateral
            _withdrawFromAave(loopAmount);
            
            // Repay debt with withdrawn amount
            _repayToAave(loopAmount);
            
            remainingAmount -= loopAmount;
            iterations++;
            
            _updatePositionState();
            
            // Safety check
            if (position.healthFactor < leverageConfig.healthFactorEmergency) {
                break;
            }
        }
        
        performance.totalDeleverages += iterations;
    }
    
    // =============================================
    // EMERGENCY & SAFETY FUNCTIONS
    // =============================================
    
    /**
     * @notice Emergency deleverage when health factor is too low
     * @dev Can be called by anyone to protect the protocol
     */
    function emergencyDeleverage() external {
        require(position.healthFactor < leverageConfig.healthFactorEmergency, "Health factor OK");
        require(!emergencyDeleveraging, "Already deleveraging");
        
        emergencyDeleveraging = true;
        uint256 leverageBefore = position.currentLeverage;
        
        // Aggressive deleverage to safe level
        uint256 targetDeleverage = leverageConfig.healthFactorTarget * 12000 / 10000; // 20% buffer
        uint256 deleverageAmount = _calculateEmergencyDeleverageAmount(targetDeleverage);
        
        _deleverage(deleverageAmount);
        
        emergencyDeleveraging = false;
        
        emit EmergencyDeleverage(position.healthFactor, leverageBefore, position.currentLeverage);
    }
    
    /**
     * @notice Check if current market conditions allow safe leveraging
     */
    function _isLeverageSafe() internal view returns (bool) {
        if (position.healthFactor < leverageConfig.healthFactorTarget) return false;
        
        // Check if borrow rates are reasonable (simplified)
        uint256 borrowRate = _getCurrentBorrowRate();
        if (borrowRate > 1500) return false; // 15% max borrow rate
        
        return true;
    }
    
    /**
     * @notice Automatic rebalancing to maintain target leverage
     */
    function rebalance() external onlyAfterCooldown onlySafeLeverage {
        uint256 currentLeverage = position.currentLeverage;
        uint256 targetLeverage = leverageConfig.targetLeverage;
        uint256 tolerance = leverageConfig.leverageTolerance;
        
        // Check if rebalance is needed
        if (currentLeverage < targetLeverage - tolerance) {
            // Leverage up
            uint256 availableCollateral = _getAvailableCollateral();
            _applyLeverage(availableCollateral);
        } else if (currentLeverage > targetLeverage + tolerance) {
            // Leverage down
            uint256 excessLeverage = currentLeverage - targetLeverage;
            uint256 deleverageAmount = _calculateDeleverageFromExcess(excessLeverage);
            _deleverage(deleverageAmount);
        }
        
        position.lastRebalance = block.timestamp;
    }
    
    // =============================================
    // HARVEST & YIELD OPTIMIZATION
    // =============================================
    
    function _harvestAndReport() internal override returns (uint256 _totalAssets) {
        uint256 preHarvestBalance = _checkBalance();
        
        // Claim and process rewards
        _claimAndProcessRewards();
        
        uint256 postHarvestBalance = _checkBalance();
        uint256 harvested = postHarvestBalance - preHarvestBalance;
        
        // Process public goods donation (inherited concept)
        if (harvested > 0) {
            _processPublicGoodsDonation(harvested);
        }
        
        // Auto-rebalance if enabled
        if (leverageConfig.autoLeverageEnabled) {
            rebalance();
        }
        
        _totalAssets = _calculateTotalAssets();
        _updatePositionState();
        
        return _totalAssets;
    }
    
    function _claimAndProcessRewards() internal {
        // Claim Aave rewards
        address[] memory assets = new address[](1);
        assets[0] = address(aToken);
        
        (address[] memory rewards, uint256[] memory amounts) = 
            rewardsController.claimAllRewards(assets, address(this));
            
        for (uint256 i = 0; i < rewards.length; i++) {
            if (amounts[i] > 0 && rewards[i] != address(asset)) {
                // Sell rewards for underlying asset
                _sellRewardForAsset(rewards[i], amounts[i]);
            }
        }
        
        // Handle stkAave rewards
        _processStkAaveRewards();
    }
    
    function _processPublicGoodsDonation(uint256 _harvested) internal {
        // Simplified donation logic - could be enhanced like previous strategy
        uint256 donationAmount = (_harvested * 500) / 10000; // 5% donation
        
        if (donationAmount > 0) {
            asset.safeTransfer(GLOW_DISTRIBUTION_POOL, donationAmount);
        }
    }
    
    // =============================================
    // MATHEMATICAL CALCULATIONS
    // =============================================
    
    /**
     * @notice Calculate optimal borrow amount for leverage iteration
     */
    function _calculateOptimalBorrowAmount(uint256 _currentLeverage, uint256 _targetLeverage) 
        internal 
        view 
        returns (uint256) 
    {
        if (_currentLeverage >= _targetLeverage) return 0;
        
        // Simplified calculation: borrow enough to move halfway to target
        uint256 leverageGap = _targetLeverage - _currentLeverage;
        uint256 totalSupplied = position.totalSupplied;
        
        // Borrow amount = (leverage_gap * total_supplied) / (2 * current_leverage)
        uint256 borrowAmount = (leverageGap * totalSupplied) / (2 * _currentLeverage);
        
        return borrowAmount.min(_getAvailableBorrow());
    }
    
    /**
     * @notice Calculate how much to deleverage for a given withdrawal
     */
    function _calculateDeleverageAmount(uint256 _withdrawAmount, uint256 _currentLeverage) 
        internal 
        pure 
        returns (uint256) 
    {
        // When leveraged, withdrawing requires repaying proportional debt
        // deleverage_amount = withdraw_amount * (current_leverage - 1x) / current_leverage
        if (_currentLeverage <= 10000) return 0;
        
        return (_withdrawAmount * (_currentLeverage - 10000)) / _currentLeverage;
    }
    
    function _calculateEmergencyDeleverageAmount(uint256 _targetHealthFactor) 
        internal 
        view 
        returns (uint256) 
    {
        uint256 currentHealthFactor = position.healthFactor;
        if (currentHealthFactor >= _targetHealthFactor) return 0;
        
        uint256 healthGap = _targetHealthFactor - currentHealthFactor;
        uint256 totalBorrowed = position.totalBorrowed;
        
        // Amount to repay = (health_gap * total_borrowed) / (2 * current_health_factor)
        return (healthGap * totalBorrowed) / (2 * currentHealthFactor);
    }
    
    function _calculateDeleverageFromExcess(uint256 _excessLeverage) 
        internal 
        view 
        returns (uint256) 
    {
        uint256 totalSupplied = position.totalSupplied;
        return (_excessLeverage * totalSupplied) / (2 * position.currentLeverage);
    }
    
    function _calculateBorrowCost(uint256 _borrowAmount) internal view returns (uint256) {
        uint256 borrowRate = _getCurrentBorrowRate();
        return (_borrowAmount * borrowRate) / 10000 / 365 days; // Daily cost approximation
    }
    
    // =============================================
    // AAVE OPERATIONS
    // =============================================
    
    function _supplyToAave(uint256 _amount) internal {
        if (_amount == 0) return;
        lendingPool.supply(address(asset), _amount, address(this), 0);
    }
    
    function _withdrawFromAave(uint256 _amount) internal {
        if (_amount == 0) return;
        lendingPool.withdraw(address(asset), _amount, address(this));
    }
    
    function _borrowFromAave(uint256 _amount) internal {
        if (_amount == 0) return;
        lendingPool.borrow(address(borrowAsset), _amount, 2, 0, address(this)); // Variable rate
    }
    
    function _repayToAave(uint256 _amount) internal {
        if (_amount == 0) return;
        lendingPool.repay(address(borrowAsset), _amount, 2, address(this));
    }
    
    // =============================================
    // STATE MANAGEMENT & VIEW FUNCTIONS
    // =============================================
    
    function _updatePositionState() internal {
        uint256 supplied = aToken.balanceOf(address(this));
        uint256 borrowed = _getCurrentBorrowBalance();
        
        position.totalSupplied = supplied;
        position.totalBorrowed = borrowed;
        position.currentLeverage = supplied > 0 ? (supplied * 10000) / (supplied - borrowed) : 10000;
        position.healthFactor = _calculateHealthFactor(supplied, borrowed);
        position.isLeveraged = position.currentLeverage > 10000;
        
        // Update performance metrics
        if (position.currentLeverage > performance.maxLeverageAchieved) {
            performance.maxLeverageAchieved = position.currentLeverage;
        }
        if (position.healthFactor < performance.minHealthFactorRecorded) {
            performance.minHealthFactorRecorded = position.healthFactor;
        }
        
        // Emit warning if health factor is low
        if (position.healthFactor < leverageConfig.healthFactorTarget) {
            emit LiquidationRisk(position.healthFactor, block.timestamp);
        }
    }
    
    function _calculateHealthFactor(uint256 _supplied, uint256 _borrowed) internal view returns (uint256) {
        if (_borrowed == 0) return type(uint256).max;
        
        // Simplified health factor calculation
        // In production, this would use Aave's oracle prices and liquidation thresholds
        uint256 liquidationThreshold = 8000; // 80% for most assets
        return (_supplied * liquidationThreshold) / _borrowed;
    }
    
    function _calculateTotalAssets() internal view returns (uint256) {
        uint256 supplied = aToken.balanceOf(address(this));
        uint256 borrowed = _getCurrentBorrowBalance();
        return supplied - borrowed;
    }
    
    function _getCurrentBorrowBalance() internal view returns (uint256) {
        // Simplified - in production, use Aave's debt token balance
        return IERC20(borrowAsset).balanceOf(address(this));
    }
    
    function _getAvailableBorrow() internal view returns (uint256) {
        // Simplified available borrow calculation
        uint256 supplied = aToken.balanceOf(address(this));
        uint256 borrowed = _getCurrentBorrowBalance();
        uint256 borrowLimit = (supplied * 8000) / 10000; // 80% LTV
        return borrowLimit > borrowed ? borrowLimit - borrowed : 0;
    }
    
    function _getAvailableCollateral() internal view returns (uint256) {
        return asset.balanceOf(address(this));
    }
    
    function _getCurrentBorrowRate() internal pure returns (uint256) {
        // Simplified - in production, query from Aave
        return 500; // 5% borrow rate
    }
    
    function _checkBalance() internal view returns (uint256) {
        return aToken.balanceOf(address(this)) + asset.balanceOf(address(this)) - _getCurrentBorrowBalance();
    }
    
    // =============================================
    // GOVERNANCE & MANAGEMENT FUNCTIONS
    // =============================================
    
    function setLeverageConfig(
        uint256 _targetLeverage,
        uint256 _maxLeverage,
        uint256 _healthFactorTarget,
        bool _autoLeverageEnabled
    ) external onlyManagement {
        require(_targetLeverage >= 10000 && _targetLeverage <= _maxLeverage, "Invalid target leverage");
        require(_maxLeverage <= 50000, "Max leverage too high");
        require(_healthFactorTarget >= 12000, "Health factor too low");
        
        leverageConfig.targetLeverage = _targetLeverage;
        leverageConfig.maxLeverage = _maxLeverage;
        leverageConfig.healthFactorTarget = _healthFactorTarget;
        leverageConfig.autoLeverageEnabled = _autoLeverageEnabled;
        
        emit LeverageConfigUpdated(_targetLeverage, _maxLeverage, _healthFactorTarget);
    }
    
    function setRiskParameters(
        uint256 _maxSingleLoopAmount,
        uint256 _rebalanceCooldown,
        uint256 _maxIterations
    ) external onlyManagement {
        riskParams.maxSingleLoopAmount = _maxSingleLoopAmount;
        riskParams.rebalanceCooldown = _rebalanceCooldown;
        leverageConfig.maxIterations = _maxIterations;
    }
    
    function getLeverageInfo() external view returns (
        uint256 currentLeverage,
        uint256 targetLeverage,
        uint256 healthFactor,
        uint256 totalSupplied,
        uint256 totalBorrowed,
        uint256 availableBorrow
    ) {
        return (
            position.currentLeverage,
            leverageConfig.targetLeverage,
            position.healthFactor,
            position.totalSupplied,
            position.totalBorrowed,
            _getAvailableBorrow()
        );
    }
    
    function getPerformanceMetrics() external view returns (
        uint256 totalLoops,
        uint256 totalDeleverages,
        uint256 maxLeverage,
        uint256 minHealthFactor,
        uint256 totalInterestPaid,
        uint256 totalInterestEarned
    ) {
        return (
            performance.totalLoopsExecuted,
            performance.totalDeleverages,
            performance.maxLeverageAchieved,
            performance.minHealthFactorRecorded,
            performance.totalInterestPaid,
            performance.totalInterestEarned
        );
    }
    
    // =============================================
    // EMERGENCY FUNCTIONS
    // =============================================
    
    function emergencyWithdraw() external onlyManagement {
        // Completely deleverage and withdraw all funds
        _deleverage(position.totalBorrowed);
        _withdrawFromAave(aToken.balanceOf(address(this)));
    }
    
    function forceDeleverage(uint256 _amount) external onlyManagement {
        _deleverage(_amount);
    }
    
    // =============================================
    // HELPER FUNCTIONS
    // =============================================
    
    function _sellRewardForAsset(address _rewardToken, uint256 _amount) internal {
        // Simplified reward selling - would integrate with DEX in production
        // This is a placeholder for actual swap logic
        if (_rewardToken == AAVE) {
            // Handle AAVE token specially if needed
        }
    }
    
    function _processStkAaveRewards() internal {
        // Handle stkAave rewards and cooldown
        if (block.chainid == 1) { // Mainnet only
            _redeemAave();
            _harvestStkAave();
        }
    }
    
    function _redeemAave() internal {
        if (!_checkCooldown()) return;
        uint256 stkAaveBalance = ERC20(address(stkAave)).balanceOf(address(this));
        if (stkAaveBalance > 0) {
            stkAave.redeem(address(this), stkAaveBalance);
        }
    }
    
    function _harvestStkAave() internal {
        if (block.chainid != 1) return;
        if (ERC20(address(stkAave)).balanceOf(address(this)) > 0) {
            stkAave.cooldown();
        }
    }
    
    function _checkCooldown() internal view returns (bool) {
        if (block.chainid != 1) return false;
        uint256 cooldownStartTimestamp = stkAave.stakersCooldowns(address(this)).timestamp;
        if (cooldownStartTimestamp == 0) return false;
        uint256 cooldownSeconds = stkAave.getCooldownSeconds();
        uint256 UNSTAKE_WINDOW = stkAave.UNSTAKE_WINDOW();
        if (block.timestamp >= cooldownStartTimestamp + cooldownSeconds) {
            return block.timestamp - (cooldownStartTimestamp + cooldownSeconds) <= UNSTAKE_WINDOW;
        }
        return false;
    }
    
    // Required by BaseStrategy
    function balanceOfAsset() public view returns (uint256) {
        return asset.balanceOf(address(this));
    }
}