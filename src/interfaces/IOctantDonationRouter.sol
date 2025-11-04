// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

/**
 * @title IOctantDonationRouter
 * @notice Interface for Octant V2 donation routing system
 * @dev Handles yield donation distribution to Octant V2's GLOW distribution pool
 */
interface IOctantDonationRouter {
    // ===========================================
    // EVENTS
    // ===========================================
    
    /// @notice Emitted when a donation is processed
    event DonationProcessed(
        address indexed strategy,
        address indexed asset,
        uint256 amount,
        uint256 timestamp,
        uint256 impactPoints
    );
    
    /// @notice Emitted when donation percentage is updated for a strategy
    event DonationPercentageUpdated(
        address indexed strategy,
        uint256 oldPercentage,
        uint256 newPercentage
    );
    
    /// @notice Emitted when GLOW distribution pool is updated
    event GlowPoolUpdated(address oldPool, address newPool);
    
    /// @notice Emitted when impact scoring parameters are updated
    event ImpactScoringUpdated(uint256 multiplier, uint256 decayRate);
    
    // ===========================================
    // STRUCTS
    // ===========================================
    
    /// @notice Donation configuration for a strategy
    struct DonationConfig {
        uint256 donationBps; // Basis points (10000 = 100%)
        uint256 totalDonated;
        uint256 lastDonation;
        uint256 impactScore;
        bool enabled;
    }
    
    /// @notice Impact metrics for tracking public goods contributions
    struct ImpactMetrics {
        uint256 totalDonated;
        uint256 donationCount;
        uint256 avgDonationSize;
        uint256 lastDonationTimestamp;
        uint256 impactScore;
        uint256 supporterCount;
    }
    
    /// @notice User impact tracking
    struct UserImpact {
        uint256 totalInfluence; // User's influence on donations
        uint256 lastActivity;
        uint256 boostMultiplier;
        bool isActiveSupporter;
    }
    
    // ===========================================
    // DONATION MANAGEMENT FUNCTIONS
    // ===========================================
    
    /**
     * @notice Process a donation from a strategy
     * @param strategy Address of the strategy making the donation
     * @param asset Address of the asset being donated
     * @param amount Amount of asset to donate
     * @return impactPoints Impact points earned from this donation
     */
    function processDonation(
        address strategy,
        address asset,
        uint256 amount
    ) external returns (uint256 impactPoints);
    
    /**
     * @notice Process donation with custom impact multiplier
     * @param strategy Address of the strategy making the donation
     * @param asset Address of the asset being donated
     * @param amount Amount of asset to donate
     * @param impactMultiplier Custom impact multiplier (in basis points)
     * @return impactPoints Impact points earned from this donation
     */
    function processDonationWithMultiplier(
        address strategy,
        address asset,
        uint256 amount,
        uint256 impactMultiplier
    ) external returns (uint256 impactPoints);
    
    /**
     * @notice Batch process multiple donations
     * @param strategies Array of strategy addresses
     * @param assets Array of asset addresses
     * @param amounts Array of donation amounts
     * @return totalImpact Total impact points earned
     */
    function processDonationBatch(
        address[] calldata strategies,
        address[] calldata assets,
        uint256[] calldata amounts
    ) external returns (uint256 totalImpact);
    
    // ===========================================
    // STRATEGY CONFIGURATION FUNCTIONS
    // ===========================================
    
    /**
     * @notice Set donation percentage for a strategy
     * @param strategy Address of the strategy
     * @param donationBps Donation percentage in basis points (10000 = 100%)
     */
    function setDonationPercentage(
        address strategy,
        uint256 donationBps
    ) external;
    
    /**
     * @notice Enable or disable donations for a strategy
     * @param strategy Address of the strategy
     * @param enabled Whether donations are enabled
     */
    function setDonationEnabled(
        address strategy,
        bool enabled
    ) external;
    
    /**
     * @notice Register a new strategy with the donation router
     * @param strategy Address of the strategy
     * @param asset Underlying asset address
     * @param donationBps Initial donation percentage
     */
    function registerStrategy(
        address strategy,
        address asset,
        uint256 donationBps
    ) external;
    
    // ===========================================
    // IMPACT & REWARDS SYSTEM
    // ===========================================
    
    /**
     * @notice Update user impact score based on activity
     * @param user Address of the user
     * @param activityType Type of activity (0: deposit, 1: withdraw, 2: harvest, 3: donation influence)
     * @param amount Relevant amount for the activity
     */
    function updateUserImpact(
        address user,
        uint8 activityType,
        uint256 amount
    ) external;
    
    /**
     * @notice Claim impact rewards for a user
     * @param user Address of the user claiming rewards
     * @return rewardAmount Amount of rewards claimed
     */
    function claimImpactRewards(address user) external returns (uint256 rewardAmount);
    
    /**
     * @notice Get user's boost multiplier based on impact score
     * @param user Address of the user
     * @return boostMultiplier Boost multiplier in basis points
     */
    function getUserBoostMultiplier(address user) external view returns (uint256 boostMultiplier);
    
    /**
     * @notice Become an active supporter of public goods
     * @dev Users can opt-in to become supporters and receive boosts
     */
    function becomeSupporter() external;
    
    // ===========================================
    // VIEW FUNCTIONS
    // ===========================================
    
    /**
     * @notice Get donation configuration for a strategy
     * @param strategy Address of the strategy
     * @return config Donation configuration
     */
    function getDonationConfig(address strategy) external view returns (DonationConfig memory config);
    
    /**
     * @notice Get impact metrics for a strategy
     * @param strategy Address of the strategy
     * @return metrics Impact metrics
     */
    function getStrategyImpactMetrics(address strategy) external view returns (ImpactMetrics memory metrics);
    
    /**
     * @notice Get user impact data
     * @param user Address of the user
     * @return userImpact User impact data
     */
    function getUserImpact(address user) external view returns (UserImpact memory userImpact);
    
    /**
     * @notice Get total donations across all strategies
     * @return totalDonated Total amount donated
     * @return totalImpact Total impact score
     * @return activeStrategies Number of active strategies
     */
    function getGlobalDonationStats() external view returns (
        uint256 totalDonated,
        uint256 totalImpact,
        uint256 activeStrategies
    );
    
    /**
     * @notice Get estimated impact points for a donation amount
     * @param amount Donation amount
     * @param strategy Strategy making the donation
     * @return estimatedImpact Estimated impact points
     */
    function getEstimatedImpact(
        uint256 amount,
        address strategy
    ) external view returns (uint256 estimatedImpact);
    
    /**
     * @notice Check if a strategy is registered
     * @param strategy Address of the strategy
     * @return isRegistered Whether the strategy is registered
     */
    function isRegisteredStrategy(address strategy) external view returns (bool isRegistered);
    
    /**
     * @notice Get GLOW distribution pool address
     * @return glowPool Address of the GLOW distribution pool
     */
    function glowDistributionPool() external view returns (address glowPool);
    
    /**
     * @notice Get total number of supporters
     * @return supporterCount Number of active supporters
     */
    function getSupporterCount() external view returns (uint256 supporterCount);
    
    // ===========================================
    // ADMIN FUNCTIONS
    // ===========================================
    
    /**
     * @notice Update GLOW distribution pool address
     * @param newGlowPool New GLOW distribution pool address
     */
    function setGlowDistributionPool(address newGlowPool) external;
    
    /**
     * @notice Update impact scoring parameters
     * @param newMultiplier New impact multiplier
     * @param newDecayRate New decay rate for impact scores
     */
    function setImpactScoringParameters(
        uint256 newMultiplier,
        uint256 newDecayRate
    ) external;
    
    /**
     * @notice Withdraw accidentally sent tokens (emergency only)
     * @param token Address of the token to withdraw
     * @param to Address to send the tokens to
     * @param amount Amount to withdraw
     */
    function emergencyWithdraw(
        address token,
        address to,
        uint256 amount
    ) external;
    
    /**
     * @notice Pause all donation operations (emergency only)
     */
    function pauseDonations() external;
    
    /**
     * @notice Resume donation operations
     */
    function resumeDonations() external;
    
    // ===========================================
    // POLICY & COMPLIANCE
    // ===========================================
    
    /**
     * @notice Get the policy statement for this donation router
     * @return policyStatement The policy statement string
     */
    function policyStatement() external pure returns (string memory policyStatement);
    
    /**
     * @notice Get dynamic policy statement with current stats
     * @return dynamicPolicy Policy statement with current statistics
     */
    function getDynamicPolicyStatement() external view returns (string memory dynamicPolicy);
    
    /**
     * @notice Verify donation compliance for a strategy
     * @param strategy Address of the strategy to verify
     * @return isCompliant Whether the strategy is compliant
     * @return complianceDetails Details about compliance status
     */
    function verifyCompliance(address strategy) external view returns (
        bool isCompliant,
        string memory complianceDetails
    );
}