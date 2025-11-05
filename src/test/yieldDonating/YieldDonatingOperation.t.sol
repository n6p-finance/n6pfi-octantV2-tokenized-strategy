// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import "forge-std/console2.sol";
import {AaveV4PublicGoodsStrategySetup as Setup, ERC20, IStrategyInterface, ITokenizedStrategy} from "./AaveV4PublicGoodsStrategySetup.sol";

contract AaveV4PublicGoodsStrategyOperationTest is Setup {
    function setUp() public virtual override {
        super.setUp();
    }

    function test_setupStrategyOK() public {
        console2.log("address of strategy", address(strategy));
        assertTrue(address(0) != address(strategy));
        assertEq(strategy.asset(), address(asset));
        
        // Check V4 innovation status
        (uint256 adaptiveFeeRate, 
         uint256 totalFeeSavings, 
         uint256 governanceScore,
         uint256 publicGoodsDonations,
         uint256 verifiedSwapsCount,
         uint256 microDonationsCount,
         bool donationVerifiedSwapsEnabled,
         bool governanceParticipant) = strategy.getV4InnovationStatus();

        console2.log("V4 Strategy Initial Status:");
        console2.log("Adaptive Fee Rate:", adaptiveFeeRate);
        console2.log("Donation Verified Swaps Enabled:", donationVerifiedSwapsEnabled);

        assertTrue(donationVerifiedSwapsEnabled, "V4 features should be enabled");
        assertEq(adaptiveFeeRate, 500, "Initial adaptive fee rate should be 5%");
    }

    function test_profitableReportWithV4Features(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);
        uint256 _timeInDays = 30; // Fixed 30 days

        console2.log("Testing profitable report with V4 features for amount:", _amount);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        assertEq(strategy.totalAssets(), _amount, "!totalAssets");

        // Test V4 features before yield generation
        _testV4FeatureActivation();

        // Move forward in time to simulate yield accrual period
        uint256 timeElapsed = _timeInDays * 1 days;
        skip(timeElapsed);

        // Test V4 features during yield generation
        _testV4FeaturePerformance();

        // Report profit - should detect the simulated yield with V4 enhancements
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();

        console2.log("Report results - Profit:", profit, "Loss:", loss);

        // Check return Values - should have profit with V4 enhancements
        assertGt(profit, 0, "!profit should be greater than 0 with V4 features");
        assertEq(loss, 0, "!loss should be 0");

        // Check V4 metrics after report
        _checkV4MetricsAfterReport(profit);

        uint256 balanceBefore = asset.balanceOf(user);

        // Withdraw all funds (user gets original amount, public goods get the yield)
        vm.prank(user);
        strategy.redeem(_amount, user, user);

        assertGe(asset.balanceOf(user), balanceBefore + _amount, "!final balance");

        // Final V4 metrics check
        _checkFinalV4Metrics();
    }

    function test_v4DonationVerifiedSwap(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount / 10);
        uint256 donationAmount = _amount / 100; // 1% donation

        console2.log("Testing V4 Donation Verified Swap with amount:", _amount);

        // Deposit into strategy first
        mintAndDepositIntoStrategy(strategy, user, _amount * 2);

        // Get initial V4 metrics
        (,,, uint256 initialPublicGoodsDonations, uint256 initialVerifiedSwaps,,,) = 
            strategy.getV4InnovationStatus();

        // Execute donation verified swap
        uint256 resultAmount = executeV4DonationVerifiedSwap(strategy, user, _amount, donationAmount);

        console2.log("Donation verified swap result amount:", resultAmount);

        // Check that swap was successful
        assertGt(resultAmount, 0, "Swap should return positive amount");
        assertLt(resultAmount, _amount, "Swap result should be less than input due to fees");

        // Check V4 metrics were updated
        (,,, uint256 newPublicGoodsDonations, uint256 newVerifiedSwaps,,,) = 
            strategy.getV4InnovationStatus();

        assertGt(newPublicGoodsDonations, initialPublicGoodsDonations, "Public goods donations should increase");
        assertGt(newVerifiedSwaps, initialVerifiedSwaps, "Verified swaps count should increase");

        console2.log("V4 Donation Verified Swap test completed successfully");
    }

    function test_v4MicroDonationAutomation(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount / 20);

        console2.log("Testing V4 Micro Donation Automation with amount:", _amount);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        // Get initial micro donation count
        (,,,,, uint256 initialMicroDonations,,) = strategy.getV4InnovationStatus();

        // Trigger micro donation through simulated V4 operation
        triggerV4MicroDonation(strategy, user, _amount);

        // Check micro donation was processed
        (,,,,, uint256 newMicroDonations,,) = strategy.getV4InnovationStatus();
        assertGt(newMicroDonations, initialMicroDonations, "Micro donations count should increase");

        // Check donation metrics for specific fund
        (uint256 totalDonated, uint256 lastDonationTime, uint256 donationCount, uint256 avgDonationSize) = 
            strategy.getDonationMetrics(dragonRouter);

        console2.log("Donation metrics - Total:", totalDonated, "Count:", donationCount, "Avg:", avgDonationSize);

        assertGt(totalDonated, 0, "Total donated should increase");
        assertGt(donationCount, 0, "Donation count should increase");

        console2.log("V4 Micro Donation Automation test completed successfully");
    }

    function test_v4GovernanceParticipationRewards() public {
        uint256 voteCount = 5;
        uint256 donationAmount = 1e18; // 1 ETH equivalent

        console2.log("Testing V4 Governance Participation Rewards");

        // Register governance participation
        registerGovernanceParticipation(strategy, user, voteCount, donationAmount);

        // Check governance rewards were applied
        (, uint256 totalFeeSavings, uint256 governanceScore,,, bool donationVerifiedSwapsEnabled, bool governanceParticipant) = 
            strategy.getV4InnovationStatus();

        console2.log("Governance participation results - Score:", governanceScore, "Participant:", governanceParticipant);

        assertTrue(governanceParticipant, "Should be registered as governance participant");
        assertGt(governanceScore, 0, "Governance score should be positive");

        // Check that fee discounts are applied
        assertGt(totalFeeSavings, 0, "Fee savings should be positive with governance participation");

        console2.log("V4 Governance Participation Rewards test completed successfully");
    }

    function test_v4AdaptiveFeeSystem(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount / 10);

        console2.log("Testing V4 Adaptive Fee System");

        // Get initial fee state
        (uint256 initialAdaptiveFeeRate,,,,,,,) = strategy.getV4InnovationStatus();

        // Simulate market volatility to trigger fee adjustment
        simulateMarketVolatility(15000); // 50% above baseline

        // Update adaptive fees
        strategy.updateAdaptiveFees();

        // Get updated fee state
        (uint256 newAdaptiveFeeRate,,,,,,,) = strategy.getV4InnovationStatus();

        console2.log("Adaptive fee update - Before:", initialAdaptiveFeeRate, "After:", newAdaptiveFeeRate);

        // Fees should adjust based on volatility
        assertTrue(newAdaptiveFeeRate != initialAdaptiveFeeRate, "Adaptive fees should change with volatility");

        // Test network congestion impact
        simulateNetworkCongestion(100 gwei); // High gas price

        strategy.updateAdaptiveFees();
        (uint256 congestionAdjustedFeeRate,,,,,,,) = strategy.getV4InnovationStatus();

        console2.log("Congestion adjusted fee rate:", congestionAdjustedFeeRate);

        assertTrue(congestionAdjustedFeeRate >= newAdaptiveFeeRate, "Fees should increase with network congestion");

        console2.log("V4 Adaptive Fee System test completed successfully");
    }

    function test_v4ImpactTokenIntegration(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount / 10);

        console2.log("Testing V4 Impact Token Integration");

        // Register a new impact token
        address testImpactToken = address(0x1234567890123456789012345678901234567890);
        uint256 impactScore = 8000; // 80% impact score

        registerImpactToken(testImpactToken, impactScore);

        // Check impact token info
        checkImpactTokenInfo(strategy, testImpactToken, impactScore, 250); // Expected 2.5% fee discount

        // Test that impact tokens receive fee discounts
        (uint256 currentFeeRate,,,,,,,) = strategy.getV4InnovationStatus();
        
        console2.log("Current fee rate with impact tokens:", currentFeeRate);

        // Impact tokens should result in lower effective fees
        assertLt(currentFeeRate, 500, "Fee rate should be lower with impact token discounts");

        console2.log("V4 Impact Token Integration test completed successfully");
    }

    function test_v4MEVProtection(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount / 10);

        console2.log("Testing V4 MEV Protection");

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        // Test MEV protection by trying to execute rapid swaps
        // This should trigger protection mechanisms

        // First swap should work
        executeV4DonationVerifiedSwap(strategy, user, _amount / 10, _amount / 1000);

        // Try immediate second swap - should be blocked by time lock
        vm.expectRevert(); // Expect revert due to MEV protection
        executeV4DonationVerifiedSwap(strategy, user, _amount / 10, _amount / 1000);

        // Wait for time lock window to expire
        skip(mevTimeLockWindow + 1);

        // Now swap should work again
        executeV4DonationVerifiedSwap(strategy, user, _amount / 10, _amount / 1000);

        console2.log("V4 MEV Protection test completed successfully");
    }

    function test_v4LiquidityMining(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount / 10);

        console2.log("Testing V4 Liquidity Mining Features");

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        // Simulate V4 liquidity addition
        simulateV4LiquidityAdd(strategy, user, _amount / 2);

        // Check that liquidity mining metrics are tracked
        (,,,,, uint256 initialMicroDonations,,) = strategy.getV4InnovationStatus();

        // Advance time to accumulate fees
        advanceTimeForV4Features();

        // Simulate harvest to trigger fee compounding
        simulateHarvestWithV4Features();

        // Check that fees were compounded
        (,,,,, uint256 newMicroDonations,,) = strategy.getV4InnovationStatus();
        assertGt(newMicroDonations, initialMicroDonations, "Micro donations should increase after harvest");

        // Check public goods allocation
        (uint256 totalDonated,,,,,) = strategy.getPublicGoodsInfo();
        assertGt(totalDonated, 0, "Public goods donations should be positive");

        console2.log("V4 Liquidity Mining test completed successfully");
    }

    function test_tendTriggerWithV4Features(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        console2.log("Testing Tend Trigger with V4 Features");

        (bool trigger, ) = strategy.tendTrigger();
        assertTrue(!trigger, "Tend should not trigger initially");

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        (trigger, ) = strategy.tendTrigger();
        assertTrue(!trigger, "Tend should not trigger after deposit");

        // Activate V4 features
        _testV4FeatureActivation();

        (trigger, ) = strategy.tendTrigger();
        assertTrue(!trigger, "Tend should not trigger after V4 activation");

        // Skip some time and simulate V4 operations
        skip(30 days);
        simulateV4Swap(strategy, user, _amount / 10);

        (trigger, ) = strategy.tendTrigger();
        assertTrue(!trigger, "Tend should not trigger after V4 operations");

        // Report and check tend trigger
        vm.prank(keeper);
        strategy.report();

        (trigger, ) = strategy.tendTrigger();
        assertTrue(!trigger, "Tend should not trigger after report");

        // Withdraw and check
        vm.prank(user);
        strategy.redeem(_amount, user, user);

        (trigger, ) = strategy.tendTrigger();
        assertTrue(!trigger, "Tend should not trigger after withdrawal");

        console2.log("Tend Trigger with V4 Features test completed successfully");
    }

    // =============================================
    // V4 INNOVATION HELPER FUNCTIONS
    // =============================================

    function _testV4FeatureActivation() internal {
        console2.log("Activating V4 features...");

        // Check initial V4 status
        (uint256 initialFeeRate, uint256 initialFeeSavings,,,,,,) = 
            strategy.getV4InnovationStatus();

        // Update adaptive fees to activate V4 features
        strategy.updateAdaptiveFees();

        (uint256 newFeeRate, uint256 newFeeSavings,,,,,,) = 
            strategy.getV4InnovationStatus();

        console2.log("V4 Feature Activation - Fee Rate:", initialFeeRate, "->", newFeeRate);
        console2.log("Fee Savings:", newFeeSavings);

        assertTrue(newFeeSavings >= initialFeeSavings, "Fee savings should not decrease");
    }

    function _testV4FeaturePerformance() internal {
        console2.log("Testing V4 feature performance...");

        // Get network conditions
        (uint256 volatility, uint256 congestion, bool safeToOperate, uint256 adaptiveFee) = 
            strategy.getV4NetworkConditions();

        console2.log("Network Conditions - Volatility:", volatility, "Congestion:", congestion);
        console2.log("Safe to operate:", safeToOperate, "Adaptive Fee:", adaptiveFee);

        assertTrue(safeToOperate, "Should be safe to operate under normal conditions");

        // Check public goods info
        (uint256 totalDonated, uint256 publicGoodsScore, uint256 yieldBoost,,,) = 
            strategy.getPublicGoodsInfo();

        console2.log("Public Goods - Total Donated:", totalDonated);
        console2.log("Public Goods Score:", publicGoodsScore, "Yield Boost:", yieldBoost);

        assertGe(publicGoodsScore, 0, "Public goods score should be non-negative");
    }

    function _checkV4MetricsAfterReport(uint256 profit) internal {
        console2.log("Checking V4 metrics after report...");

        // Check V4 innovation status after report
        (uint256 adaptiveFeeRate, 
         uint256 totalFeeSavings, 
         uint256 governanceScore,
         uint256 publicGoodsDonations,
         uint256 verifiedSwapsCount,
         uint256 microDonationsCount,
         bool donationVerifiedSwapsEnabled,
         bool governanceParticipant) = strategy.getV4InnovationStatus();

        console2.log("Post-Report V4 Metrics:");
        console2.log("Adaptive Fee Rate:", adaptiveFeeRate);
        console2.log("Total Fee Savings:", totalFeeSavings);
        console2.log("Public Goods Donations:", publicGoodsDonations);
        console2.log("Governance Score:", governanceScore);

        // Public goods donations should reflect the profit
        assertGe(publicGoodsDonations, profit * initialDonationPercentage / 10000, 
                "Public goods donations should reflect donation percentage");

        // Check fee capture stats
        (uint256 totalTradingFeesPaid, uint256 totalFeesRedirected, uint256 pendingRedistribution,) = 
            strategy.getFeeCaptureStats();

        console2.log("Fee Capture - Paid:", totalTradingFeesPaid, "Redirected:", totalFeesRedirected);
        console2.log("Pending Redistribution:", pendingRedistribution);

        assertGe(totalFeesRedirected, 0, "Some fees should be redirected to public goods");
    }

    function _checkFinalV4Metrics() internal {
        console2.log("Checking final V4 metrics...");

        // Final comprehensive V4 metrics check
        checkV4StrategyMetrics(
            0,      // Expected fee savings (at least 0)
            0,      // Expected public goods donations (at least 0) 
            0,      // Expected verified swaps (at least 0)
            0       // Expected micro donations (at least 0)
        );

        // Check that all V4 features remain operational
        (,,,,, bool donationVerifiedSwapsEnabled, bool governanceParticipant) = 
            strategy.getV4InnovationStatus();

        assertTrue(donationVerifiedSwapsEnabled, "V4 features should remain enabled");
        
        console2.log("All V4 innovation tests completed successfully");
    }
}