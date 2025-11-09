// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import {BaseStrategy, ERC20} from "@tokenized-strategy/BaseStrategy.sol";
import {Math} from "../../../lib/openzeppelin-contracts/contracts/utils/math/Math.sol";
import {SafeERC20} from "../../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "../../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

// Aave V3 Interfaces
import {IAToken} from "../../interfaces/aaveV3/V3/IAtoken.sol";
import {IStakedAave} from "../../interfaces/aaveV3/V3/IStakedAave.sol";
import {IPool} from "../../interfaces/aaveV3/V3/IPool.sol";
import {IRewardsController} from "../../interfaces/aaveV3/V3/IRewardsController.sol";

// Adapter Integration
import {HybridStrategyRouter} from "../HybridStrategyRouter.sol";

// Core
import {Hooks} from "../../../lib/v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "../../../lib/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "../../../lib/v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "../../../lib/v4-core/src/types/BalanceDelta.sol";
import {Currency, CurrencyLibrary} from "../../../lib/v4-core/src/types/Currency.sol";
import {PoolId, PoolIdLibrary} from "../../../lib/v4-core/src/types/PoolId.sol";

// Periphery (Hooks)
import {BaseHook} from "../../../lib/v4-periphery/src/utils/BaseHook.sol";

// Octant V2 Integration
import {IOctantV2} from "../../interfaces/Octant/V2/IOctantV2.sol";

abstract contract AaveV4Leveraged is BaseStrategy {
    using SafeERC20 for ERC20;
    using Math for uint256;
    using CurrencyLibrary for Currency;

    // Aave Constants
    IStakedAave internal constant stkAave = IStakedAave(0x4da27a545c0c5B758a6BA100e3a049001de870f5);
    address internal constant AAVE = address(0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9);
    
    // Octant V2 Integration
    IOctantV2 public constant OCTANT_V2 = IOctantV2(address(0));
    address public constant GLOW_DISTRIBUTION_POOL = address(address(0));

    // Adapter Integration with V4 Features
    HybridStrategyRouter public immutable aaveAdapter;

    // Core Aave contracts
    IPool public immutable lendingPool;
    IRewardsController public immutable rewardsController;
    IAToken public immutable aToken;

    // =============================================
    // V4 INNOVATION: DONATION-VERIFIED SWAP SYSTEM
    // =============================================
    
    struct DonationVerifiedSwap {
        bool enabled;
        uint256 minDonationAmount;
        uint256 donationVerificationWindow;
        uint256 lastDonationTime;
        uint256 totalVerifiedSwaps;
        mapping(bytes32 => bool) verifiedSwapHashes;
    }
    
    DonationVerifiedSwap public donationVerifiedSwap;
    
    // =============================================
    // V4 INNOVATION: ADAPTIVE IMPACT-BASED FEE ENGINE
    // =============================================
    
    struct AdaptiveFeeEngine {
        uint256 baseFeeBps;
        uint256 currentVolatilityMultiplier;
        uint256 currentCongestionMultiplier;
        uint256 impactTokenDiscount;
        uint256 governanceParticipantDiscount;
        uint256 publicGoodsContributorDiscount;
        uint256 lastFeeUpdate;
        uint256 totalFeeSavings;
    }
    
    AdaptiveFeeEngine public feeEngine;
    
    // =============================================
    // V4 INNOVATION: PUBLIC GOODS IMPACT ORACLE
    // =============================================
    
    struct ImpactOracle {
        mapping(address => uint256) tokenImpactScores; // 0-10000, higher = more positive impact
        mapping(address => uint256) lastImpactUpdate;
        address[] highImpactTokens;
        uint256 minimumImpactScore;
        uint256 impactScoreDecayRate; // How quickly impact scores decay
    }
    
    ImpactOracle public impactOracle;
    
    // =============================================
    // V4 INNOVATION: MICRO-DONATION AUTOMATION ENGINE
    // =============================================
    
    struct MicroDonationEngine {
        bool autoDonateEnabled;
        uint256 microDonationBps;
        uint256 minMicroDonation;
        uint256 maxMicroDonation;
        uint256 donationCooldown;
        uint256 lastMicroDonation;
        uint256 totalMicroDonations;
        address[] donationRecipients;
        mapping(address => uint256) recipientWeights;
    }
    
    MicroDonationEngine public microDonationEngine;
    
    // =============================================
    // V4 INNOVATION: GOVERNANCE PARTICIPATION REWARDS
    // =============================================
    
    struct GovernanceRewards {
        bool isVerifiedParticipant;
        uint256 lastGovernanceAction;
        uint256 totalVotes;
        uint256 governanceScore;
        uint256 feeDiscountEarned;
        uint256 yieldBoostEarned;
    }
    
    GovernanceRewards public governanceRewards;
    
    // =============================================
    // V4 INNOVATION: ANTI-FLASH LP PROTECTION
    // =============================================
    
    struct FlashLPProtection {
        uint256 minLPDuration;
        uint256 earlyExitPenaltyBps;
        uint256 lastLPDeposit;
        uint256 totalLPPenalties;
        bool flashLPDetectionEnabled;
    }
    
    FlashLPProtection public flashLPProtection;

    // =============================================
    // RISK PARAMETERS STRUCT (ADDED MISSING)
    // =============================================
    
    struct RiskParams {
        uint256 slippageTolerance;
        uint256 maxBorrowAmount;
        uint256 minHealthFactor;
        uint256 volatilityThreshold;
    }
    
    RiskParams public riskParams;
    
    // =============================================
    // ENHANCED LEVERAGE CONFIGURATION WITH V4 INNOVATIONS
    // =============================================
    
    struct LeverageConfig {
        uint256 targetLeverage;
        uint256 maxLeverage;
        uint256 minLeverage;
        uint256 healthFactorTarget;
        uint256 healthFactorEmergency;
        uint256 leverageTolerance;
        uint256 maxIterations;
        bool autoLeverageEnabled;
        bool donationVerifiedSwaps; // Require donation verification for swaps
        bool adaptiveFeeOptimization; // Use V4 adaptive fees
        bool impactTokenPriority; // Prefer high-impact tokens
        bool microDonationAutomation; // Auto-micro-donate on operations
    }
    
    LeverageConfig public leverageConfig;
    
    struct LeveragePosition {
        uint256 totalSupplied;
        uint256 totalBorrowed;
        uint256 currentLeverage;
        uint256 healthFactor;
        uint256 lastRebalance;
        bool isLeveraged;
        uint256 impactMultiplier;
        uint256 totalDonations;
        uint256 publicGoodsScore;
        uint256 governanceBoost; // Additional boost from governance participation
    }
    
    LeveragePosition public position;
    
    // Enhanced borrow asset tracking with impact scoring
    address public borrowAsset;
    uint256 public borrowAssetImpactScore;
    
    // =============================================
    // V4 PERFORMANCE METRICS WITH INNOVATION TRACKING
    // =============================================
    
    struct PerformanceMetrics {
        uint256 totalLoopsExecuted;
        uint256 totalDeleverages;
        uint256 maxLeverageAchieved;
        uint256 minHealthFactorRecorded;
        uint256 totalInterestPaid;
        uint256 totalInterestEarned;
        uint256 totalFeeSavings;
        uint256 totalImpactRewards;
        uint256 totalPublicGoodsDonations;
        uint256 governanceRewardsEarned;
        uint256 publicGoodsYieldBoost;
        uint256 verifiedSwapsExecuted;
        uint256 microDonationsCount;
        uint256 flashLPPenaltiesApplied;
    }
    
    PerformanceMetrics public performance;

    // =============================================
    // V4 INNOVATION EVENTS
    // =============================================
    
    event DonationVerifiedSwapExecuted(address indexed user, uint256 donationAmount, bytes32 swapHash, uint256 feeDiscount);
    event AdaptiveFeeUpdated(uint256 volatilityMultiplier, uint256 congestionMultiplier, uint256 newFee, uint256 savings);
    event ImpactTokenRegistered(address indexed token, uint256 impactScore, uint256 feeDiscount);
    event MicroDonationTriggered(uint256 amount, address indexed recipient, bytes32 operationHash);
    event GovernanceRewardEarned(uint256 discount, uint256 yieldBoost, uint256 governanceScore);
    event FlashLPPenalized(address indexed lp, uint256 penaltyAmount, uint256 lockupDuration);
    event PublicGoodsAllocation(uint256 totalAmount, address[] recipients, uint256[] amounts);

    // =============================================
    // CONSTRUCTOR & V4 INNOVATION INITIALIZATION
    // =============================================
    
    constructor(
        address _asset,
        string memory _name,
        address _lendingPool,
        address _aaveAdapter,
        uint256 _initialTargetLeverage,
        address _borrowAsset,
        address _v4PoolManager,
        address[] memory _initialDonationRecipients
    ) BaseStrategy(_asset, _name) {
        lendingPool = IPool(_lendingPool);
        aToken = IAToken(lendingPool.getReserveData(_asset).aTokenAddress);
        require(address(aToken) != address(0), "!aToken");

        aaveAdapter = HybridStrategyRouter(_aaveAdapter);
        rewardsController = aToken.getIncentivesController();
        borrowAsset = _borrowAsset;

        // Initialize all V4 innovations
        _initializeV4Innovations(_initialDonationRecipients);
        _initializeLeverageConfig(_initialTargetLeverage);
        _initializeV4RiskParameters();
        
        // Enhanced approvals for V4 operations
        asset.approve(address(lendingPool), type(uint256).max);
        asset.approve(address(OCTANT_V2), type(uint256).max);
        asset.approve(address(_aaveAdapter), type(uint256).max);
        
        // Register with adapter and initialize V4 features
        _registerWithAdapter();
        _initializeV4Pools();
    }

    // =============================================
    // ADDED MISSING INITIALIZATION FUNCTIONS
    // =============================================

    function _initializeV4RiskParameters() internal {
        riskParams = RiskParams({
            slippageTolerance: 50, // 0.5%
            maxBorrowAmount: 1000000e18,
            minHealthFactor: 11000, // 1.1
            volatilityThreshold: 20000 // 200% volatility threshold
        });
    }

    function _registerWithAdapter() internal {
        // Register this strategy with the Aave adapter
        aaveAdapter.registerStrategy(address(this), address(asset));
    }

    function _initializeV4Pools() internal {
        // Initialize V4 pools - this would set up any necessary pool configurations
        // For now, this is a placeholder implementation
    }

    function _calculateTotalAssets() internal view returns (uint256) {
        // Calculate total assets including supplied and borrowed amounts
        uint256 supplied = aToken.balanceOf(address(this));
        uint256 borrowed = _getCurrentBorrowBalance();
        return supplied > borrowed ? supplied - borrowed : 0;
    }

    function _getCurrentBorrowBalance() internal view returns (uint256) {
        // Get current borrow balance from Aave
        // This is a simplified implementation
        (, uint256 totalDebtBase, , , , ) = lendingPool.getUserAccountData(address(this));
        return totalDebtBase;
    }
    
    function _initializeV4Innovations(address[] memory _donationRecipients) internal {
        // Initialize Donation-Verified Swap System
        donationVerifiedSwap.enabled = true;
        donationVerifiedSwap.minDonationAmount = 1e16; // 0.01 ETH
        donationVerifiedSwap.donationVerificationWindow = 24 hours;
        
        // Initialize Adaptive Fee Engine
        feeEngine.baseFeeBps = 500; // 5% base
        feeEngine.currentVolatilityMultiplier = 10000;
        feeEngine.currentCongestionMultiplier = 10000;
        feeEngine.impactTokenDiscount = 0;
        feeEngine.governanceParticipantDiscount = 0;
        feeEngine.publicGoodsContributorDiscount = 0;
        
        // Initialize Impact Oracle
        impactOracle.minimumImpactScore = 5000;
        impactOracle.impactScoreDecayRate = 100; // 1% decay per period
        
        // Initialize Micro-Donation Engine
        microDonationEngine.autoDonateEnabled = true;
        microDonationEngine.microDonationBps = 10; // 0.1%
        microDonationEngine.minMicroDonation = 1e15; // 0.001 ETH
        microDonationEngine.maxMicroDonation = 1e18; // 1 ETH
        microDonationEngine.donationCooldown = 1 hours;
        microDonationEngine.donationRecipients = _donationRecipients;
        
        // Set equal weights for recipients
        uint256 equalWeight = 10000 / _donationRecipients.length;
        for (uint256 i = 0; i < _donationRecipients.length; i++) {
            microDonationEngine.recipientWeights[_donationRecipients[i]] = equalWeight;
        }
        
        // Initialize Flash LP Protection
        flashLPProtection.minLPDuration = 7 days;
        flashLPProtection.earlyExitPenaltyBps = 500; // 5%
        flashLPProtection.flashLPDetectionEnabled = true;
    }
    
    function _initializeLeverageConfig(uint256 _initialTargetLeverage) internal {
        require(_initialTargetLeverage >= 10000 && _initialTargetLeverage <= 50000, "Invalid leverage");
        
        leverageConfig = LeverageConfig({
            targetLeverage: _initialTargetLeverage,
            maxLeverage: 50000,
            minLeverage: 10000,
            healthFactorTarget: 15000,
            healthFactorEmergency: 11000,
            leverageTolerance: 500,
            maxIterations: 10,
            autoLeverageEnabled: true,
            donationVerifiedSwaps: true,
            adaptiveFeeOptimization: true,
            impactTokenPriority: true,
            microDonationAutomation: true
        });
    }

    // =============================================
    // V4 INNOVATION 1: DONATION-VERIFIED SWAP ENGINE
    // =============================================
    
    /**
     * @notice Execute a swap only after donation verification
     * @dev Implements "Execute a swap only after a donation transaction is verified on-chain"
     */
    function executeDonationVerifiedSwap(
        address _fromToken,
        address _toToken,
        uint256 _amount,
        uint256 _minAmountOut,
        uint256 _donationAmount
    ) internal returns (uint256) {
        require(leverageConfig.donationVerifiedSwaps, "Donation verified swaps disabled");
        require(_donationAmount >= donationVerifiedSwap.minDonationAmount, "Donation too small");
        
        // Verify donation eligibility
        _verifyDonationEligibility(_donationAmount);
        
        // Execute donation
        _executeVerifiedDonation(_donationAmount);
        
        // Generate swap hash for verification
        bytes32 swapHash = keccak256(abi.encodePacked(_fromToken, _toToken, _amount, block.timestamp));
        donationVerifiedSwap.verifiedSwapHashes[swapHash] = true;
        
        // Execute swap with enhanced fee discounts
        uint256 resultAmount = _executeVerifiedSwap(_fromToken, _toToken, _amount, _minAmountOut, swapHash);
        
        donationVerifiedSwap.totalVerifiedSwaps++;
        performance.verifiedSwapsExecuted++;
        
        emit DonationVerifiedSwapExecuted(address(this), _donationAmount, swapHash, feeEngine.impactTokenDiscount);
        
        return resultAmount;
    }
    
    function _verifyDonationEligibility(uint256 _donationAmount) internal view {
        require(_donationAmount >= donationVerifiedSwap.minDonationAmount, "Donation below minimum");
        
        // Check if within donation verification window
        if (donationVerifiedSwap.lastDonationTime > 0) {
            require(
                block.timestamp <= donationVerifiedSwap.lastDonationTime + donationVerifiedSwap.donationVerificationWindow,
                "Donation verification expired"
            );
        }
    }
    
    function _executeVerifiedDonation(uint256 _donationAmount) internal {
        require(_donationAmount <= asset.balanceOf(address(this)), "Insufficient balance for donation");
        
        // Distribute donation according to recipient weights
        address[] memory recipients = microDonationEngine.donationRecipients;
        uint256[] memory amounts = new uint256[](recipients.length);
        uint256 totalDistributed = 0;
        
        for (uint256 i = 0; i < recipients.length; i++) {
            uint256 weight = microDonationEngine.recipientWeights[recipients[i]];
            uint256 allocation = (_donationAmount * weight) / 10000;
            amounts[i] = allocation;
            totalDistributed += allocation;
            
            if (allocation > 0) {
                asset.transfer(recipients[i], allocation);
            }
        }
        
        // Update donation tracking
        donationVerifiedSwap.lastDonationTime = block.timestamp;
        performance.totalPublicGoodsDonations += totalDistributed;
        
        emit PublicGoodsAllocation(totalDistributed, recipients, amounts);
    }

    // =============================================
    // V4 INNOVATION 2: ADAPTIVE FEE ENGINE
    // =============================================
    
    /**
     * @notice Dynamic fee adjustment based on volatility and network conditions
     * @dev Implements "Implement adaptive fees based on volatility or network congestion"
     */
    function updateAdaptiveFees() public {
        uint256 volatility = _calculateCurrentVolatility();
        uint256 congestion = _calculateNetworkCongestion();
        
        // Update multipliers
        feeEngine.currentVolatilityMultiplier = _calculateVolatilityMultiplier(volatility);
        feeEngine.currentCongestionMultiplier = _calculateCongestionMultiplier(congestion);
        
        // Calculate discounts
        feeEngine.impactTokenDiscount = _calculateImpactTokenDiscount();
        feeEngine.governanceParticipantDiscount = _calculateGovernanceDiscount();
        feeEngine.publicGoodsContributorDiscount = _calculatePublicGoodsDiscount();
        
        // Calculate new fee
        uint256 newFee = _calculateAdaptiveFee();
        uint256 oldFee = feeEngine.baseFeeBps;
        uint256 savings = oldFee > newFee ? oldFee - newFee : 0;
        
        feeEngine.baseFeeBps = uint16(newFee);
        feeEngine.lastFeeUpdate = block.timestamp;
        feeEngine.totalFeeSavings += savings;
        performance.totalFeeSavings += savings;
        
        emit AdaptiveFeeUpdated(
            feeEngine.currentVolatilityMultiplier,
            feeEngine.currentCongestionMultiplier,
            newFee,
            savings
        );
    }
    
    function _calculateAdaptiveFee() internal view returns (uint256) {
        uint256 baseFee = feeEngine.baseFeeBps;
        
        // Apply volatility multiplier
        baseFee = (baseFee * feeEngine.currentVolatilityMultiplier) / 10000;
        
        // Apply congestion multiplier  
        baseFee = (baseFee * feeEngine.currentCongestionMultiplier) / 10000;
        
        // Apply discounts
        uint256 totalDiscount = feeEngine.impactTokenDiscount + 
                              feeEngine.governanceParticipantDiscount + 
                              feeEngine.publicGoodsContributorDiscount;
        
        if (totalDiscount > 0) {
            baseFee = baseFee * (10000 - totalDiscount) / 10000;
        }
        
        // Clamp to reasonable bounds
        return baseFee.clamp(100, 2000); // 1% to 20% range
    }
    
    function _calculateImpactTokenDiscount() internal view returns (uint256) {
        uint256 impactScore = impactOracle.tokenImpactScores[address(asset)];
        if (impactScore < impactOracle.minimumImpactScore) return 0;
        
        // 1% discount per 1000 impact score above minimum
        return ((impactScore - impactOracle.minimumImpactScore) * 10) / 10000;
    }
    
    function _calculateGovernanceDiscount() internal view returns (uint256) {
        if (!governanceRewards.isVerifiedParticipant) return 0;
        
        // Up to 3% discount for governance participation
        uint256 timeSinceLastAction = block.timestamp - governanceRewards.lastGovernanceAction;
        if (timeSinceLastAction > 30 days) return 0;
        
        return governanceRewards.governanceScore * 30 / 10000; // 0-3%
    }
    
    function _calculatePublicGoodsDiscount() internal view returns (uint256) {
        // Up to 2% discount for public goods contributions
        uint256 totalAssets = _calculateTotalAssets();
        if (totalAssets == 0) return 0;
        
        uint256 donationRatio = (performance.totalPublicGoodsDonations * 10000) / totalAssets;
        return donationRatio.clamp(0, 200); // 0-2%
    }

    // =============================================
    // V4 INNOVATION 3: IMPACT TOKEN OPTIMIZATION
    // =============================================
    
    /**
     * @notice Prefer tokens with high social/environmental impact scores
     * @dev Implements "Lower swap fees for tokens tied to social or environmental impact"
     */
    function registerImpactToken(address _token, uint256 _impactScore) external onlyManagement {
        require(_impactScore <= 10000, "Impact score too high");
        
        impactOracle.tokenImpactScores[_token] = _impactScore;
        impactOracle.lastImpactUpdate[_token] = block.timestamp;
        
        // Add to high impact tokens list if meets minimum
        if (_impactScore >= impactOracle.minimumImpactScore) {
            impactOracle.highImpactTokens.push(_token);
        }
        
        emit ImpactTokenRegistered(_token, _impactScore, _calculateImpactTokenDiscount());
    }
    
    function getOptimalImpactToken(uint256 _amount) public view returns (address, uint256, uint256) {
        address[] memory highImpactTokens = impactOracle.highImpactTokens;
        address bestToken = address(asset);
        uint256 bestScore = 0;
        uint256 bestDiscount = 0;
        
        for (uint256 i = 0; i < highImpactTokens.length; i++) {
            address token = highImpactTokens[i];
            uint256 score = impactOracle.tokenImpactScores[token];
            uint256 discount = _calculateTokenDiscount(score);
            
            if (score > bestScore && _isTokenSafeForOperation(token, _amount)) {
                bestToken = token;
                bestScore = score;
                bestDiscount = discount;
            }
        }
        
        return (bestToken, bestScore, bestDiscount);
    }

    // =============================================
    // V4 INNOVATION 4: MICRO-DONATION AUTOMATION
    // =============================================
    
    /**
     * @notice Automated micro-donations on every operation
     * @dev Implements "Every swap or liquidity add could trigger a micro-donation"
     */
    function triggerMicroDonation(uint256 _operationAmount, bytes32 _operationHash) internal {
        if (!microDonationEngine.autoDonateEnabled) return;
        if (block.timestamp < microDonationEngine.lastMicroDonation + microDonationEngine.donationCooldown) return;
        
        uint256 microDonation = (_operationAmount * microDonationEngine.microDonationBps) / 10000;
        microDonation = microDonation.clamp(microDonationEngine.minMicroDonation, microDonationEngine.maxMicroDonation);
        
        if (microDonation > 0 && microDonation <= asset.balanceOf(address(this))) {
            // Select recipient based on weights
            address recipient = _selectMicroDonationRecipient();
            
            asset.transfer(recipient, microDonation);
            
            microDonationEngine.lastMicroDonation = block.timestamp;
            microDonationEngine.totalMicroDonations += microDonation;
            performance.totalPublicGoodsDonations += microDonation;
            performance.microDonationsCount++;
            
            emit MicroDonationTriggered(microDonation, recipient, _operationHash);
        }
    }
    
    function _selectMicroDonationRecipient() internal view returns (address) {
        address[] memory recipients = microDonationEngine.donationRecipients;
        if (recipients.length == 0) return GLOW_DISTRIBUTION_POOL;
        
        // Weighted random selection based on block hash
        uint256 totalWeight = 0;
        for (uint256 i = 0; i < recipients.length; i++) {
            totalWeight += microDonationEngine.recipientWeights[recipients[i]];
        }
        
        uint256 randomValue = uint256(keccak256(abi.encodePacked(blockhash(block.number - 1), block.timestamp))) % totalWeight;
        uint256 cumulativeWeight = 0;
        
        for (uint256 i = 0; i < recipients.length; i++) {
            cumulativeWeight += microDonationEngine.recipientWeights[recipients[i]];
            if (randomValue < cumulativeWeight) {
                return recipients[i];
            }
        }
        
        return recipients[recipients.length - 1];
    }

    // =============================================
    // V4 INNOVATION 5: GOVERNANCE PARTICIPATION REWARDS
    // =============================================
    
    /**
     * @notice Reward governance participation with fee discounts and yield boosts
     * @dev Implements "Lower fees for verified wallets that donate or vote in governance"
     */
    function registerGovernanceParticipation(uint256 _voteCount, uint256 _donationAmount) external onlyManagement {
        governanceRewards.isVerifiedParticipant = true;
        governanceRewards.lastGovernanceAction = block.timestamp;
        governanceRewards.totalVotes += _voteCount;
        
        // Calculate governance score (0-10000)
        uint256 voteScore = _voteCount * 100; // 100 points per vote
        uint256 donationScore = (_donationAmount * 10000) / (1 ether); // Scale with donation size
        governanceRewards.governanceScore = (voteScore + donationScore).clamp(0, 10000);
        
        // Calculate rewards
        governanceRewards.feeDiscountEarned = _calculateGovernanceDiscount();
        governanceRewards.yieldBoostEarned = governanceRewards.governanceScore * 50 / 10000; // 0-5% yield boost
        
        position.governanceBoost = governanceRewards.yieldBoostEarned;
        
        emit GovernanceRewardEarned(
            governanceRewards.feeDiscountEarned,
            governanceRewards.yieldBoostEarned,
            governanceRewards.governanceScore
        );
    }

    // =============================================
    // V4 INNOVATION 6: ANTI-FLASH LP PROTECTION
    // =============================================
    
    /**
     * @notice Protect against flash LP attacks and reward consistent participants
     * @dev Implements "Ensure yield farming rewards go to consistent participants, not flash LPs"
     */
    function checkLPDuration(uint256 _depositAmount) external {
        require(flashLPProtection.flashLPDetectionEnabled, "Flash LP protection disabled");
        
        if (flashLPProtection.lastLPDeposit > 0) {
            uint256 timeSinceDeposit = block.timestamp - flashLPProtection.lastLPDeposit;
            
            if (timeSinceDeposit < flashLPProtection.minLPDuration) {
                // Apply early exit penalty
                uint256 penaltyAmount = (_depositAmount * flashLPProtection.earlyExitPenaltyBps) / 10000;
                
                if (penaltyAmount > 0) {
                    // Redirect penalty to public goods and loyal LPs
                    _distributeFlashLPPenalty(penaltyAmount);
                    flashLPProtection.totalLPPenalties += penaltyAmount;
                    performance.flashLPPenaltiesApplied++;
                    
                    emit FlashLPPenalized(msg.sender, penaltyAmount, flashLPProtection.minLPDuration);
                }
            }
        }
        
        flashLPProtection.lastLPDeposit = block.timestamp;
    }

    // =============================================
    // V4-ENHANCED LEVERAGE ENGINE WITH INNOVATIONS
    // =============================================
    
    function _executeV4LeverageLoop(uint256 _borrowAmount) 
        internal
        returns (uint256 feeSavings, uint256 impactMultiplier) 
    {
        // Update adaptive fees before operation
        if (leverageConfig.adaptiveFeeOptimization) {
            updateAdaptiveFees();
        }
        
        // Generate operation hash for micro-donation tracking
        bytes32 operationHash = keccak256(abi.encodePacked(_borrowAmount, block.timestamp, "leverage"));
        
        // Execute micro-donation if enabled
        if (leverageConfig.microDonationAutomation) {
            triggerMicroDonation(_borrowAmount, operationHash);
        }
        
        // Use impact tokens if priority enabled
        if (leverageConfig.impactTokenPriority) {
            (address optimalToken,,) = getOptimalImpactToken(_borrowAmount);
            if (optimalToken != address(asset)) {
                // Enhanced swap with donation verification if required
                if (leverageConfig.donationVerifiedSwaps) {
                    _borrowAmount = executeDonationVerifiedSwap(
                        address(asset),
                        optimalToken,
                        _borrowAmount,
                        _borrowAmount * (10000 - riskParams.slippageTolerance) / 10000,
                        donationVerifiedSwap.minDonationAmount
                    );
                } else {
                    _borrowAmount = _swapToImpactToken(_borrowAmount, optimalToken);
                }
                impactMultiplier = impactOracle.tokenImpactScores[optimalToken];
            }
        }
        
        // Execute core leverage operations with V4 optimizations
        uint256 borrowCostBefore = _calculateBorrowCost(_borrowAmount);
        _borrowFromAaveWithV4Optimization(_borrowAmount);
        uint256 borrowCostAfter = _calculateBorrowCost(_borrowAmount);
        
        feeSavings = borrowCostBefore > borrowCostAfter ? borrowCostBefore - borrowCostAfter : 0;
        
        // Apply governance boost to supplied amount
        uint256 boostedAmount = _applyGovernanceBoost(_borrowAmount);
        _supplyToAave(boostedAmount);
        
        performance.totalInterestPaid += _calculateBorrowCost(_borrowAmount);
        
        return (feeSavings, impactMultiplier);
    }
    
    function _applyGovernanceBoost(uint256 _amount) internal view returns (uint256) {
        if (governanceRewards.governanceScore == 0) return _amount;
        
        uint256 boost = (_amount * governanceRewards.yieldBoostEarned) / 10000;
        return _amount + boost;
    }

    // =============================================
    // ADDED MISSING CORE FUNCTIONS
    // =============================================

    function _swapToImpactToken(uint256 _amount, address _impactToken) internal returns (uint256) {
        // Swap to impact token using the adapter
        uint256 minAmountOut = _amount * (10000 - riskParams.slippageTolerance) / 10000;
        return aaveAdapter.executeSwap(
            address(asset),
            _impactToken,
            _amount,
            minAmountOut
        );
    }

    function _calculateBorrowCost(uint256 _borrowAmount) internal view returns (uint256) {
        // Calculate estimated borrow cost based on current rates
        uint256 borrowRate = lendingPool.getReserveData(borrowAsset).currentVariableBorrowRate;
        return (_borrowAmount * borrowRate) / 1e27; // Aave rates are in ray (1e27)
    }

    function _borrowFromAaveWithV4Optimization(uint256 _borrowAmount) internal {
        // Borrow from Aave with V4 optimizations
        lendingPool.borrow(
            borrowAsset,
            _borrowAmount,
            2, // variable rate
            0, // referral code
            address(this)
        );
    }

    function _supplyToAave(uint256 _amount) internal {
        // Supply to Aave
        lendingPool.supply(
            address(asset),
            _amount,
            address(this),
            0 // referral code
        );
    }

    // =============================================
    // V4 ENHANCED VIEW FUNCTIONS
    // =============================================
    
    function getV4InnovationStatus() external view returns (
        uint256 adaptiveFeeRate,
        uint256 totalFeeSavings,
        uint256 governanceScore,
        uint256 publicGoodsDonations,
        uint256 verifiedSwapsCount,
        uint256 microDonationsCount,
        bool donationVerifiedSwapsEnabled,
        bool governanceParticipant
    ) {
        return (
            feeEngine.baseFeeBps,
            feeEngine.totalFeeSavings,
            governanceRewards.governanceScore,
            performance.totalPublicGoodsDonations,
            performance.verifiedSwapsExecuted,
            performance.microDonationsCount,
            leverageConfig.donationVerifiedSwaps,
            governanceRewards.isVerifiedParticipant
        );
    }
    
    function getImpactTokenInfo(address _token) external view returns (
        uint256 impactScore,
        uint256 feeDiscount,
        uint256 lastUpdate,
        bool isHighImpact
    ) {
        return (
            impactOracle.tokenImpactScores[_token],
            _calculateTokenDiscount(impactOracle.tokenImpactScores[_token]),
            impactOracle.lastImpactUpdate[_token],
            impactOracle.tokenImpactScores[_token] >= impactOracle.minimumImpactScore
        );
    }

    // =============================================
    // V4 HELPER FUNCTIONS
    // =============================================
    
    function _calculateCurrentVolatility() internal view returns (uint256) {
        // Simplified volatility calculation - would integrate with oracle in production
        return aaveAdapter.getMarketVolatility(address(asset));
    }
    
    function _calculateNetworkCongestion() internal view returns (uint256) {
        return block.basefee;
    }
    
    function _calculateVolatilityMultiplier(uint256 _volatility) internal pure returns (uint256) {
        // Higher volatility = higher fees (capped at 2x)
        if (_volatility <= 10000) return 10000;
        return (10000 + (_volatility - 10000) / 2).clamp(10000, 20000);
    }
    
    function _calculateCongestionMultiplier(uint256 _congestion) internal pure returns (uint256) {
        // Higher congestion = higher fees (capped at 1.5x)
        if (_congestion <= 20 gwei) return 10000;
        if (_congestion <= 100 gwei) return 12000;
        return 15000;
    }
    
    function _calculateTokenDiscount(uint256 _impactScore) internal view returns (uint256) {
        if (_impactScore < impactOracle.minimumImpactScore) return 0;
        return ((_impactScore - impactOracle.minimumImpactScore) * 10) / 10000;
    }
    
    function _isTokenSafeForOperation(address _token, uint256 _amount) internal view returns (bool) {
        // Check token safety for operations (liquidity, volatility, etc.)
        return aaveAdapter.getMarketVolatility(_token) < 20000 && 
               IERC20(_token).balanceOf(address(aaveAdapter)) >= _amount;
    }
    
    function _distributeFlashLPPenalty(uint256 _penaltyAmount) internal {
        // 60% to public goods, 40% to loyal LPs as rewards
        uint256 publicGoodsShare = (_penaltyAmount * 6000) / 10000;
        uint256 lpRewardsShare = _penaltyAmount - publicGoodsShare;
        
        // Distribute to public goods
        asset.transfer(GLOW_DISTRIBUTION_POOL, publicGoodsShare);
        
        // LP rewards distribution would be implemented based on loyalty metrics
        performance.totalPublicGoodsDonations += publicGoodsShare;
    }
    
    function _executeVerifiedSwap(
        address _fromToken,
        address _toToken,
        uint256 _amount,
        uint256 _minAmountOut,
        bytes32 _swapHash
    ) internal returns (uint256) {
        // Execute swap through adapter with verified hash
        return aaveAdapter.executeVerifiedSwap(
            _fromToken,
            _toToken,
            _amount,
            _minAmountOut,
            _swapHash
        );
    }

    // =============================================
    // V4 CONFIGURATION FUNCTIONS
    // =============================================
    
    function setV4InnovationConfig(
        bool _donationVerifiedSwaps,
        bool _adaptiveFeeOptimization,
        bool _impactTokenPriority,
        bool _microDonationAutomation,
        uint256 _microDonationBps
    ) external onlyManagement {
        leverageConfig.donationVerifiedSwaps = _donationVerifiedSwaps;
        leverageConfig.adaptiveFeeOptimization = _adaptiveFeeOptimization;
        leverageConfig.impactTokenPriority = _impactTokenPriority;
        leverageConfig.microDonationAutomation = _microDonationAutomation;
        microDonationEngine.microDonationBps = _microDonationBps;
    }
    
    function updateDonationRecipients(
        address[] memory _newRecipients,
        uint256[] memory _newWeights
    ) external onlyManagement {
        require(_newRecipients.length == _newWeights.length, "Mismatched arrays");
        
        uint256 totalWeight = 0;
        for (uint256 i = 0; i < _newWeights.length; i++) {
            totalWeight += _newWeights[i];
            microDonationEngine.recipientWeights[_newRecipients[i]] = _newWeights[i];
        }
        
        require(totalWeight == 10000, "Weights must sum to 10000");
        microDonationEngine.donationRecipients = _newRecipients;
    }

    // Required override
    function _balanceOfAsset() public view returns (uint256) {
        return asset.balanceOf(address(this));
    }

    // =============================================
    // BASE STRATEGY OVERRIDES (PLACEHOLDERS)
    // =============================================

    function _deployFunds(uint256 _amount) internal override {
        // Deploy funds to Aave
        lendingPool.supply(address(asset), _amount, address(this), 0);
    }

    function _freeFunds(uint256 _amount) internal override {
        // Withdraw funds from Aave
        lendingPool.withdraw(address(asset), _amount, address(this));
    }

    function _harvestAndReport() internal override returns (uint256) {
        // Harvest rewards and report total assets
        return _calculateTotalAssets();
    }
}


