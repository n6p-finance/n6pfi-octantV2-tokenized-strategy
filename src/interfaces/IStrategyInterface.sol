// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.24;

import {IStrategy} from "@tokenized-strategy/interfaces/IStrategy.sol";

interface IStrategyInterface is IStrategy {
    // Core Strategy Functions
    function deposit(uint256 assets, address receiver) external returns (uint256);
    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256);
    function harvest() external;
    function totalAssets() external view returns (uint256);
    function asset() external view returns (address);
    
    // V4 Innovation Functions
    function executeDonationVerifiedSwap(
        address _fromToken,
        address _toToken,
        uint256 _amount,
        uint256 _minAmountOut,
        uint256 _donationAmount
    ) external returns (uint256);
    
    function registerGovernanceParticipation(uint256 _voteCount, uint256 _donationAmount) external;
    function triggerMicroDonation(uint256 _operationAmount, bytes32 _operationHash) external;
    function updateAdaptiveFees() external;
    
    // Configuration Functions
    function setV4InnovationConfig(
        bool _donationVerifiedSwaps,
        bool _adaptiveFeeOptimization,
        bool _impactTokenPriority,
        bool _microDonationAutomation,
        uint256 _microDonationBps
    ) external;
    
    function updateDonationRecipients(
        address[] memory _newRecipients,
        uint256[] memory _newWeights
    ) external;
    
    function registerImpactToken(address _token, uint256 _impactScore) external;
    function setMEVProtectionConfig(
        bool _enabled,
        uint256 _maxSlippageBps,
        uint256 _minSwapAmount,
        uint256 _maxSwapAmount,
        uint256 _timeLockWindow
    ) external;
    
    function setLiquidityMiningConfig(
        bool _autoCompoundFees,
        uint256 _minFeeClaimThreshold,
        uint256 _feeReinvestmentBps
    ) external;
    
    // View Functions for V4 Innovations
    function getV4InnovationStatus() external view returns (
        uint256 adaptiveFeeRate,
        uint256 totalFeeSavings,
        uint256 governanceScore,
        uint256 publicGoodsDonations,
        uint256 verifiedSwapsCount,
        uint256 microDonationsCount,
        bool donationVerifiedSwapsEnabled,
        bool governanceParticipant
    );
    
    function getImpactTokenInfo(address _token) external view returns (
        uint256 impactScore,
        uint256 feeDiscount,
        uint256 lastUpdate,
        bool isHighImpact
    );
    
    function getV4NetworkConditions() external view returns (
        uint256 currentVolatility,
        uint256 networkCongestion,
        bool safeToOperate,
        uint256 adaptiveFeeRate
    );
    
    function getPublicGoodsInfo() external view returns (
        uint256 totalDonated,
        uint256 publicGoodsScore,
        uint256 yieldBoost,
        uint256 pendingRedistribution,
        address[] memory supportedFunds,
        uint256[] memory allocationWeights
    );
    
    function getDonationMetrics(address _fund) external view returns (
        uint256 totalDonated,
        uint256 lastDonationTime,
        uint256 donationCount,
        uint256 avgDonationSize
    );
    
    function getFeeCaptureStats() external view returns (
        uint256 totalTradingFeesPaid,
        uint256 totalFeesRedirected,
        uint256 pendingRedistribution,
        uint256 lastCaptureTime
    );
    
    // Simulation functions for testing
    function simulateV4Swap(uint256 _amount) external;
    function simulateV4LiquidityAdd(uint256 _amount) external;
}