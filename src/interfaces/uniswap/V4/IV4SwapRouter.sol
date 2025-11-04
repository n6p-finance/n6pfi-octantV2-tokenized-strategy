// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

// Uniswap V4 Core Imports
import {PoolKey} from "@uniswap/v4-core/contracts/types/PoolKey.sol";
import {BalanceDelta} from "@uniswap/v4-core/contracts/types/BalanceDelta.sol";
import {Currency} from "@uniswap/v4-core/contracts/types/Currency.sol";
import {IPoolManager} from "@uniswap/v4-core/contracts/interfaces/IPoolManager.sol";

/**
 * @title IV4SwapRouter
 * @notice Interface for Uniswap V4 Swap Router with advanced features
 * @dev Provides optimized swap routing, MEV protection, and fee optimization
 */
interface IV4SwapRouter {
    
    // =============================================
    // STRUCTS & ENUMS
    // =============================================
    
    struct SwapParams {
        Currency currencyIn;
        Currency currencyOut;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
        address recipient;
        bytes hookData;
        uint256 deadline;
    }
    
    struct MultiHopSwap {
        bytes path;
        uint256 amountIn;
        uint256 amountOutMinimum;
        address recipient;
        uint256 deadline;
    }
    
    struct SwapResult {
        uint256 amountIn;
        uint256 amountOut;
        uint256 feeAmount;
        uint256 priceImpact;
        BalanceDelta delta;
        bool success;
    }
    
    struct FeeOptimization {
        uint256 baseFee;
        uint256 dynamicFee;
        uint256 gasCost;
        uint256 optimizedFee;
        bool useOptimalRoute;
    }
    
    struct MEVProtectionConfig {
        bool enabled;
        uint256 maxSlippageBps;
        uint256 timeLockWindow;
        uint256 minSwapAmount;
        uint256 maxSwapAmount;
    }
    
    // =============================================
    // EVENTS
    // =============================================
    
    event SwapExecuted(
        address indexed user,
        Currency indexed currencyIn,
        Currency indexed currencyOut,
        uint256 amountIn,
        uint256 amountOut,
        uint256 fee,
        bytes32 poolId
    );
    
    event MultiHopSwapExecuted(
        address indexed user,
        bytes path,
        uint256 totalAmountIn,
        uint256 totalAmountOut,
        uint256 totalFee
    );
    
    event FeeOptimized(
        address indexed user,
        uint256 originalFee,
        uint256 optimizedFee,
        uint256 savings
    );
    
    event MEVProtectionTriggered(
        address indexed user,
        bytes32 swapHash,
        uint256 timestamp,
        uint256 protectedAmount
    );
    
    event SwapRouted(
        address indexed user,
        PoolKey[] route,
        uint256 amountIn,
        uint256 amountOut,
        uint256 routeEfficiency
    );
    
    event ArbitrageExecuted(
        address indexed executor,
        PoolKey[] route,
        uint256 profit,
        uint256 timestamp
    );

    // =============================================
    // CORE SWAP FUNCTIONS
    // =============================================
    
    /**
     * @notice Execute a single swap with optimal routing
     * @param params Swap parameters including currencies and amounts
     * @return result Swap result with amounts and fees
     */
    function swapExactInputSingle(SwapParams calldata params)
        external
        payable
        returns (SwapResult memory result);
    
    /**
     * @notice Execute a swap with exact output amount
     * @param params Swap parameters with exact output requirement
     * @return result Swap result with actual input amount
     */
    function swapExactOutputSingle(SwapParams calldata params)
        external
        payable
        returns (SwapResult memory result);
    
    /**
     * @notice Execute a multi-hop swap through multiple pools
     * @param multiHop Multi-hop swap parameters
     * @return result Swap result with total amounts
     */
    function swapExactInputMultihop(MultiHopSwap calldata multiHop)
        external
        payable
        returns (SwapResult memory result);
    
    /**
     * @notice Execute multi-hop swap with exact output
     * @param multiHop Multi-hop swap parameters
     * @return result Swap result with total amounts
     */
    function swapExactOutputMultihop(MultiHopSwap calldata multiHop)
        external
        payable
        returns (SwapResult memory result);

    // =============================================
    // ADVANCED SWAP FEATURES
    // =============================================
    
    /**
     * @notice Execute swap with MEV protection
     * @param params Swap parameters
     * @param mevConfig MEV protection configuration
     * @return result Protected swap result
     */
    function swapWithMEVProtection(
        SwapParams calldata params,
        MEVProtectionConfig calldata mevConfig
    ) external payable returns (SwapResult memory result);
    
    /**
     * @notice Execute flash swap (borrow without collateral)
     * @param params Swap parameters
     * @param callbackData Data for callback function
     * @return result Flash swap result
     */
    function flashSwap(
        SwapParams calldata params,
        bytes calldata callbackData
    ) external returns (SwapResult memory result);
    
    /**
     * @notice Execute arbitrage between multiple pools
     * @param routes Array of potential arbitrage routes
     * @param maxAmount Maximum amount to use for arbitrage
     * @return profit Actual profit from arbitrage
     */
    function executeArbitrage(
        PoolKey[] calldata routes,
        uint256 maxAmount
    ) external returns (uint256 profit);
    
    /**
     * @notice Batch execute multiple swaps in single transaction
     * @param swaps Array of swap parameters
     * @return results Array of swap results
     */
    function batchSwap(SwapParams[] calldata swaps)
        external
        payable
        returns (SwapResult[] memory results);

    // =============================================
    // FEE OPTIMIZATION & ROUTING
    // =============================================
    
    /**
     * @notice Find optimal swap route with fee optimization
     * @param currencyIn Input currency
     * @param currencyOut Output currency
     * @param amountIn Input amount
     * @return optimalRoute Optimal pool route
     * @return feeOptimization Fee optimization details
     */
    function findOptimalRoute(
        Currency currencyIn,
        Currency currencyOut,
        uint256 amountIn
    ) external view returns (PoolKey[] memory optimalRoute, FeeOptimization memory feeOptimization);
    
    /**
     * @notice Calculate optimal fee for a swap
     * @param poolKey Pool key for swap
     * @param amountIn Input amount
     * @param isExactInput Whether swap is exact input or output
     * @return optimizedFee Optimized fee amount
     */
    function calculateOptimizedFee(
        PoolKey calldata poolKey,
        uint256 amountIn,
        bool isExactInput
    ) external view returns (uint256 optimizedFee);
    
    /**
     * @notice Get current fee efficiency for a pool
     * @param poolKey Pool key to check
     * @return efficiency Fee efficiency score (0-10000)
     */
    function getFeeEfficiency(PoolKey calldata poolKey) external view returns (uint256 efficiency);
    
    /**
     * @notice Update fee optimization parameters
     * @param poolKey Pool key to update
     * @param newBaseFee New base fee for optimization
     */
    function updateFeeOptimization(PoolKey calldata poolKey, uint256 newBaseFee) external;

    // =============================================
    // MEV PROTECTION FUNCTIONS
    // =============================================
    
    /**
     * @notice Set MEV protection configuration
     * @param config New MEV protection configuration
     */
    function setMEVProtectionConfig(MEVProtectionConfig calldata config) external;
    
    /**
     * @notice Get current MEV protection status for a user
     * @param user User address to check
     * @return enabled Whether MEV protection is enabled
     * @return lastSwapTime Timestamp of last swap
     */
    function getMEVProtectionStatus(address user)
        external
        view
        returns (bool enabled, uint256 lastSwapTime);
    
    /**
     * @notice Check if swap would trigger MEV protection
     * @param user User address
     * @param amount Swap amount
     * @return wouldTrigger Whether swap would trigger protection
     */
    function wouldTriggerMEVProtection(address user, uint256 amount)
        external
        view
        returns (bool wouldTrigger);

    // =============================================
    // ARBITRAGE & PRICE DISCOVERY
    // =============================================
    
    /**
     * @notice Detect arbitrage opportunities between pools
     * @param baseCurrency Base currency for arbitrage
     * @param quoteCurrency Quote currency for arbitrage
     * @param maxRoutes Maximum routes to check
     * @return opportunities Array of arbitrage opportunities
     */
    function detectArbitrageOpportunities(
        Currency baseCurrency,
        Currency quoteCurrency,
        uint256 maxRoutes
    ) external view returns (PoolKey[] memory opportunities);
    
    /**
     * @notice Get best price across all pools for a pair
     * @param currencyIn Input currency
     * @param currencyOut Output currency
     * @param amountIn Input amount
     * @return bestPrice Best available price
     * @return bestPool Pool offering best price
     */
    function getBestPrice(
        Currency currencyIn,
        Currency currencyOut,
        uint256 amountIn
    ) external view returns (uint256 bestPrice, PoolKey memory bestPool);
    
    /**
     * @notice Calculate price impact for a swap
     * @param poolKey Pool key
     * @param amountIn Input amount
     * @param isExactInput Whether swap is exact input
     * @return priceImpact Price impact in basis points
     */
    function calculatePriceImpact(
        PoolKey calldata poolKey,
        uint256 amountIn,
        bool isExactInput
    ) external view returns (uint256 priceImpact);

    // =============================================
    // VIEW & UTILITY FUNCTIONS
    // =============================================
    
    /**
     * @notice Get expected output amount for a swap
     * @param params Swap parameters
     * @return expectedAmount Expected output amount
     * @return fee Expected fee amount
     */
    function getAmountOut(SwapParams calldata params)
        external
        view
        returns (uint256 expectedAmount, uint256 fee);
    
    /**
     * @notice Get required input amount for exact output
     * @param params Swap parameters
     * @return requiredAmount Required input amount
     * @return fee Expected fee amount
     */
    function getAmountIn(SwapParams calldata params)
        external
        view
        returns (uint256 requiredAmount, uint256 fee);
    
    /**
     * @notice Check if a pool is available for swapping
     * @param poolKey Pool key to check
     * @return available Whether pool is available
     */
    function isPoolAvailable(PoolKey calldata poolKey) external view returns (bool available);
    
    /**
     * @notice Get all available pools for a currency pair
     * @param currency0 First currency
     * @param currency1 Second currency
     * @return availablePools Array of available pools
     */
    function getAvailablePools(Currency currency0, Currency currency1)
        external
        view
        returns (PoolKey[] memory availablePools);
    
    /**
     * @notice Get swap history for a user
     * @param user User address
     * @param page Page number for pagination
     * @return swaps Array of recent swaps
     */
    function getUserSwapHistory(address user, uint256 page)
        external
        view
        returns (SwapResult[] memory swaps);
}

/**
 * @title IV4LiquidityManager
 * @notice Interface for Uniswap V4 Liquidity Management with advanced features
 * @dev Provides liquidity position management, fee optimization, and auto-compounding
 */
interface IV4LiquidityManager {
    
    // =============================================
    // STRUCTS & ENUMS
    // =============================================
    
    struct LiquidityPosition {
        PoolKey poolKey;
        int24 tickLower;
        int24 tickUpper;
        uint128 liquidity;
        uint256 depositedAmount0;
        uint256 depositedAmount1;
        uint256 feesEarned0;
        uint256 feesEarned1;
        uint256 lastFeeCollection;
        uint256 createdAt;
        bool active;
    }
    
    struct AddLiquidityParams {
        PoolKey poolKey;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        address recipient;
        uint256 deadline;
    }
    
    struct RemoveLiquidityParams {
        bytes32 positionId;
        uint128 liquidity;
        uint256 amount0Min;
        uint256 amount1Min;
        address recipient;
        uint256 deadline;
    }
    
    struct LiquidityResult {
        uint128 liquidity;
        uint256 amount0;
        uint256 amount1;
        uint256 fee0;
        uint256 fee1;
    }
    
    struct FeeCompoundingConfig {
        bool autoCompound;
        uint256 compoundThreshold0;
        uint256 compoundThreshold1;
        uint256 compoundInterval;
        uint256 lastCompoundTime;
    }
    
    struct RebalanceParams {
        bytes32 positionId;
        int24 newTickLower;
        int24 newTickUpper;
        uint256 priceChangeThreshold;
        uint256 minLiquidity;
    }
    
    // =============================================
    // EVENTS
    // =============================================
    
    event LiquidityAdded(
        address indexed provider,
        bytes32 indexed positionId,
        PoolKey poolKey,
        uint128 liquidity,
        uint256 amount0,
        uint256 amount1
    );
    
    event LiquidityRemoved(
        address indexed provider,
        bytes32 indexed positionId,
        uint128 liquidity,
        uint256 amount0,
        uint256 amount1,
        uint256 fee0,
        uint256 fee1
    );
    
    event FeesCollected(
        address indexed provider,
        bytes32 indexed positionId,
        uint256 fee0,
        uint256 fee1,
        uint256 timestamp
    );
    
    event FeesCompounded(
        address indexed provider,
        bytes32 indexed positionId,
        uint256 compounded0,
        uint256 compounded1,
        uint256 newLiquidity
    );
    
    event PositionRebalanced(
        address indexed provider,
        bytes32 indexed positionId,
        int24 oldTickLower,
        int24 oldTickUpper,
        int24 newTickLower,
        int24 newTickUpper,
        uint128 oldLiquidity,
        uint128 newLiquidity
    );
    
    event LiquidityOptimized(
        address indexed provider,
        PoolKey poolKey,
        uint256 efficiencyGain,
        uint256 feeSavings
    );

    // =============================================
    // CORE LIQUIDITY MANAGEMENT
    // =============================================
    
    /**
     * @notice Add liquidity to a pool with specified range
     * @param params Liquidity addition parameters
     * @return result Liquidity addition result
     */
    function addLiquidity(AddLiquidityParams calldata params)
        external
        payable
        returns (LiquidityResult memory result);
    
    /**
     * @notice Remove liquidity from a position
     * @param params Liquidity removal parameters
     * @return result Liquidity removal result
     */
    function removeLiquidity(RemoveLiquidityParams calldata params)
        external
        returns (LiquidityResult memory result);
    
    /**
     * @notice Increase liquidity in an existing position
     * @param positionId Position ID to increase liquidity for
     * @param amount0 Amount of token0 to add
     * @param amount1 Amount of token1 to add
     * @return liquidityAdded Amount of liquidity added
     */
    function increaseLiquidity(
        bytes32 positionId,
        uint256 amount0,
        uint256 amount1
    ) external returns (uint128 liquidityAdded);
    
    /**
     * @notice Decrease liquidity in an existing position
     * @param positionId Position ID to decrease liquidity for
     * @param liquidity Amount of liquidity to remove
     * @return amount0 Amount of token0 received
     * @return amount1 Amount of token1 received
     */
    function decreaseLiquidity(bytes32 positionId, uint128 liquidity)
        external
        returns (uint256 amount0, uint256 amount1);

    // =============================================
    // FEE MANAGEMENT & COMPOUNDING
    // =============================================
    
    /**
     * @notice Collect fees from a liquidity position
     * @param positionId Position ID to collect fees from
     * @return collected0 Amount of token0 collected
     * @return collected1 Amount of token1 collected
     */
    function collectFees(bytes32 positionId)
        external
        returns (uint256 collected0, uint256 collected1);
    
    /**
     * @notice Collect fees from multiple positions
     * @param positionIds Array of position IDs
     * @return totalCollected0 Total token0 collected
     * @return totalCollected1 Total token1 collected
     */
    function collectFeesBatch(bytes32[] calldata positionIds)
        external
        returns (uint256 totalCollected0, uint256 totalCollected1);
    
    /**
     * @notice Auto-compound fees back into liquidity position
     * @param positionId Position ID to compound fees for
     * @return compounded0 Amount of token0 compounded
     * @return compounded1 Amount of token1 compounded
     */
    function compoundFees(bytes32 positionId)
        external
        returns (uint256 compounded0, uint256 compounded1);
    
    /**
     * @notice Set fee compounding configuration for a position
     * @param positionId Position ID
     * @param config Compounding configuration
     */
    function setFeeCompoundingConfig(bytes32 positionId, FeeCompoundingConfig calldata config) external;
    
    /**
     * @notice Execute auto-compounding for all eligible positions
     * @return totalCompounded0 Total token0 compounded
     * @return totalCompounded1 Total token1 compounded
     */
    function autoCompoundAll() external returns (uint256 totalCompounded0, uint256 totalCompounded1);

    // =============================================
    // POSITION REBALANCING & OPTIMIZATION
    // =============================================
    
    /**
     * @notice Rebalance a liquidity position to new tick range
     * @param params Rebalancing parameters
     * @return newPositionId New position ID after rebalancing
     */
    function rebalancePosition(RebalanceParams calldata params)
        external
        returns (bytes32 newPositionId);
    
    /**
     * @notice Optimize liquidity position based on current market conditions
     * @param positionId Position ID to optimize
     * @return optimized Whether position was optimized
     */
    function optimizePosition(bytes32 positionId) external returns (bool optimized);
    
    /**
     * @notice Find optimal tick range for liquidity provision
     * @param poolKey Pool key
     * @param amount0 Amount of token0 available
     * @param amount1 Amount of token1 available
     * @return tickLower Optimal lower tick
     * @return tickUpper Optimal upper tick
     * @return expectedFee Expected fee earnings
     */
    function findOptimalTickRange(
        PoolKey calldata poolKey,
        uint256 amount0,
        uint256 amount1
    ) external view returns (int24 tickLower, int24 tickUpper, uint256 expectedFee);
    
    /**
     * @notice Calculate position efficiency score
     * @param positionId Position ID to check
     * @return efficiency Efficiency score (0-10000)
     */
    function calculatePositionEfficiency(bytes32 positionId) external view returns (uint256 efficiency);

    // =============================================
    // POSITION MANAGEMENT & TRACKING
    // =============================================
    
    /**
     * @notice Get all active positions for a user
     * @param user User address
     * @return positions Array of active positions
     */
    function getUserPositions(address user) external view returns (LiquidityPosition[] memory positions);
    
    /**
     * @notice Get position details by ID
     * @param positionId Position ID
     * @return position Position details
     */
    function getPosition(bytes32 positionId) external view returns (LiquidityPosition memory position);
    
    /**
     * @notice Check if a position needs rebalancing
     * @param positionId Position ID to check
     * @return needsRebalance Whether position needs rebalancing
     * @return reason Reason for rebalancing
     */
    function needsRebalancing(bytes32 positionId) external view returns (bool needsRebalance, string memory reason);
    
    /**
     * @notice Get total value locked for a user
     * @param user User address
     * @return totalValue Total value in USD
     */
    function getUserTVL(address user) external view returns (uint256 totalValue);
    
    /**
     * @notice Get total fees earned by a user
     * @param user User address
     * @return totalFees0 Total token0 fees earned
     * @return totalFees1 Total token1 fees earned
     */
    function getUserTotalFees(address user) external view returns (uint256 totalFees0, uint256 totalFees1);

    // =============================================
    // ADVANCED LIQUIDITY FEATURES
    // =============================================
    
    /**
     * @notice Create multiple positions in single transaction
     * @param paramsArray Array of add liquidity parameters
     * @return results Array of liquidity results
     */
    function batchAddLiquidity(AddLiquidityParams[] calldata paramsArray)
        external
        payable
        returns (LiquidityResult[] memory results);
    
    /**
     * @notice Remove liquidity from multiple positions
     * @param paramsArray Array of remove liquidity parameters
     * @return results Array of removal results
     */
    function batchRemoveLiquidity(RemoveLiquidityParams[] calldata paramsArray)
        external
        returns (LiquidityResult[] memory results);
    
    /**
     * @notice Execute limit order using concentrated liquidity
     * @param poolKey Pool key
     * @param tickLimit Limit tick for the order
     * @param amount Amount to use for order
     * @param isToken0 Whether amount is in token0
     * @param recipient Order recipient
     * @return orderId Limit order ID
     */
    function createLimitOrder(
        PoolKey calldata poolKey,
        int24 tickLimit,
        uint256 amount,
        bool isToken0,
        address recipient
    ) external returns (bytes32 orderId);
    
    /**
     * @notice Cancel a limit order
     * @param orderId Order ID to cancel
     * @return amountReturned Amount returned from cancelled order
     */
    function cancelLimitOrder(bytes32 orderId) external returns (uint256 amountReturned);

    // =============================================
    // RISK MANAGEMENT & SAFETY
    // =============================================
    
    /**
     * @notice Set maximum position size for a user
     * @param maxPositionSize Maximum position size in USD
     */
    function setMaxPositionSize(uint256 maxPositionSize) external;
    
    /**
     * @notice Set maximum leverage for positions
     * @param maxLeverage Maximum leverage (in basis points)
     */
    function setMaxLeverage(uint256 maxLeverage) external;
    
    /**
     * @notice Emergency withdraw from all positions
     * @return totalWithdrawn0 Total token0 withdrawn
     * @return totalWithdrawn1 Total token1 withdrawn
     */
    function emergencyWithdraw() external returns (uint256 totalWithdrawn0, uint256 totalWithdrawn1);
    
    /**
     * @notice Get position risk metrics
     * @param positionId Position ID
     * @return impermanentLoss Impermanent loss estimate
     * @return priceRisk Price risk score
     * @return liquidityRisk Liquidity risk score
     */
    function getPositionRisk(bytes32 positionId)
        external
        view
        returns (uint256 impermanentLoss, uint256 priceRisk, uint256 liquidityRisk);
}

/**
 * @title IV4HookBase
 * @notice Base interface for V4 hooks integration
 */
interface IV4HookBase {
    function beforeInitialize(address sender, PoolKey calldata key, uint160 sqrtPriceX96, bytes calldata hookData)
        external
        returns (bytes4);
    
    function afterInitialize(address sender, PoolKey calldata key, uint160 sqrtPriceX96, uint128 liquidity, bytes calldata hookData)
        external
        returns (bytes4);
    
    function beforeModifyPosition(address sender, PoolKey calldata key, IPoolManager.ModifyPositionParams calldata params, bytes calldata hookData)
        external
        returns (bytes4);
    
    function afterModifyPosition(address sender, PoolKey calldata key, IPoolManager.ModifyPositionParams calldata params, BalanceDelta delta, bytes calldata hookData)
        external
        returns (bytes4);
    
    function beforeSwap(address sender, PoolKey calldata key, IPoolManager.SwapParams calldata params, bytes calldata hookData)
        external
        returns (bytes4);
    
    function afterSwap(address sender, PoolKey calldata key, IPoolManager.SwapParams calldata params, BalanceDelta delta, bytes calldata hookData)
        external
        returns (bytes4);
    
    function beforeDonate(address sender, PoolKey calldata key, uint256 amount0, uint256 amount1, bytes calldata hookData)
        external
        returns (bytes4);
    
    function afterDonate(address sender, PoolKey calldata key, uint256 amount0, uint256 amount1, bytes calldata hookData)
        external
        returns (bytes4);
}

/**
 * @title IV4PoolManager
 * @notice Extended interface for V4 Pool Manager
 */
interface IV4PoolManager is IPoolManager {
    function getPool(PoolKey calldata key) external view returns (address pool);
    function getLiquidity(PoolKey calldata key) external view returns (uint128 liquidity);
    function getFee(PoolKey calldata key) external view returns (uint24 fee);
}