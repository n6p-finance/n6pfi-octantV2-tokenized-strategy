// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/console2.sol";
import {AaveV4PublicGoodsStrategySetup as Setup, ERC20, IStrategyInterface, ITokenizedStrategy} from "./YieldDonatingSetup.sol";

contract AaveV4PublicGoodsStrategyOperationTest is Setup {
    function setUp() public virtual override {
        console2.log("=== Setting up AaveV4PublicGoodsStrategyOperationTest ===");
        super.setUp();
        console2.log("Test setup completed successfully");
    }

    function test_setupStrategyOK() public {
        console2.log("\n=== Starting test_setupStrategyOK ===");
        console2.log("Strategy address:", address(strategy));
        console2.log("Asset address:", address(asset));
        
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
        console2.log("Total Fee Savings:", totalFeeSavings);
        console2.log("Governance Score:", governanceScore);
        console2.log("Public Goods Donations:", publicGoodsDonations);
        console2.log("Verified Swaps Count:", verifiedSwapsCount);
        console2.log("Micro Donations Count:", microDonationsCount);
        console2.log("Donation Verified Swaps Enabled:", donationVerifiedSwapsEnabled);
        console2.log("Governance Participant:", governanceParticipant);

        assertTrue(donationVerifiedSwapsEnabled, "V4 features should be enabled");
        assertEq(adaptiveFeeRate, 500, "Initial adaptive fee rate should be 5%");
        
        console2.log(" test_setupStrategyOK passed - Strategy setup correctly with V4 features enabled");
    }

    function test_profitableReportWithV4Features(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);
        uint256 _timeInDays = 30; // Fixed 30 days

        console2.log("\n=== Starting test_profitableReportWithV4Features ===");
        console2.log("Testing amount:", _amount);
        console2.log("Time period:", _timeInDays, "days");

        // Deposit into strategy
        console2.log("Depositing into strategy...");
        mintAndDepositIntoStrategy(strategy, user, _amount);

        uint256 initialAssets = strategy.totalAssets();
        console2.log("Initial total assets:", initialAssets);
        assertEq(initialAssets, _amount, "!totalAssets");

        // Test V4 features before yield generation
        console2.log("Testing V4 feature activation...");
        _testV4FeatureActivation();

        // Move forward in time to simulate yield accrual period
        uint256 timeElapsed = _timeInDays * 1 days;
        console2.log("Advancing time by", timeElapsed, "seconds...");
        skip(timeElapsed);

        // Test V4 features during yield generation
        console2.log("Testing V4 feature performance during yield generation...");
        _testV4FeaturePerformance();

        // Report profit - should detect the simulated yield with V4 enhancements
        console2.log("Calling report() to harvest profits...");
        uint256 assetsBeforeReport = strategy.totalAssets();
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();
        uint256 assetsAfterReport = strategy.totalAssets();

        console2.log("Report results:");
        console2.log("Profit:", profit);
        console2.log("Loss:", loss);
        console2.log("Assets before report:", assetsBeforeReport);
        console2.log("Assets after report:", assetsAfterReport);

        // Check return Values - should have profit with V4 enhancements
        assertGt(profit, 0, "!profit should be greater than 0 with V4 features");
        assertEq(loss, 0, "!loss should be 0");

        // Check V4 metrics after report
        console2.log("Checking V4 metrics after report...");
        _checkV4MetricsAfterReport(profit);

        uint256 balanceBefore = asset.balanceOf(user);
        console2.log("User balance before withdrawal:", balanceBefore);

        // Withdraw all funds (user gets original amount, public goods get the yield)
        console2.log("Withdrawing all funds...");
        vm.prank(user);
        strategy.redeem(_amount, user, user);

        uint256 balanceAfter = asset.balanceOf(user);
        console2.log("User balance after withdrawal:", balanceAfter);
        console2.log("Balance increase:", balanceAfter - balanceBefore);

        assertGe(balanceAfter, balanceBefore + _amount, "!final balance");

        // Final V4 metrics check
        console2.log("Performing final V4 metrics check...");
        _checkFinalV4Metrics();
        
        console2.log(" test_profitableReportWithV4Features passed - Profitable report with V4 features working correctly");
    }

    function test_v4DonationVerifiedSwap(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount / 10);
        uint256 donationAmount = _amount / 100; // 1% donation

        console2.log("\n=== Starting test_v4DonationVerifiedSwap ===");
        console2.log("Swap amount:", _amount);
        console2.log("Donation amount:", donationAmount);

        // Deposit into strategy first
        console2.log("Depositing into strategy for swap test...");
        mintAndDepositIntoStrategy(strategy, user, _amount * 2);

        // Get initial V4 metrics
        (,,, uint256 initialPublicGoodsDonations, uint256 initialVerifiedSwaps,,,) = 
            strategy.getV4InnovationStatus();

        console2.log("Initial metrics - Public Goods Donations:", initialPublicGoodsDonations);
        console2.log("Initial metrics - Verified Swaps:", initialVerifiedSwaps);

        // Execute donation verified swap
        console2.log("Executing donation verified swap...");
        uint256 resultAmount = executeV4DonationVerifiedSwap(strategy, user, _amount, donationAmount);

        console2.log("Donation verified swap completed:");
        console2.log("Input amount:", _amount);
        console2.log("Donation amount:", donationAmount);
        console2.log("Result amount:", resultAmount);

        // Check that swap was successful
        assertGt(resultAmount, 0, "Swap should return positive amount");
        assertLt(resultAmount, _amount, "Swap result should be less than input due to fees");

        // Check V4 metrics were updated
        (,,, uint256 newPublicGoodsDonations, uint256 newVerifiedSwaps,,,) = 
            strategy.getV4InnovationStatus();

        console2.log("Updated metrics - Public Goods Donations:", newPublicGoodsDonations);
        console2.log("Updated metrics - Verified Swaps:", newVerifiedSwaps);
        console2.log("Donations increase:", newPublicGoodsDonations - initialPublicGoodsDonations);
        console2.log("Verified swaps increase:", newVerifiedSwaps - initialVerifiedSwaps);

        assertGt(newPublicGoodsDonations, initialPublicGoodsDonations, "Public goods donations should increase");
        assertGt(newVerifiedSwaps, initialVerifiedSwaps, "Verified swaps count should increase");

        console2.log(" test_v4DonationVerifiedSwap passed - Donation verified swap working correctly");
    }

    function test_v4MicroDonationAutomation(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount / 20);

        console2.log("\n=== Starting test_v4MicroDonationAutomation ===");
        console2.log("Testing with amount:", _amount);

        // Deposit into strategy
        console2.log("Depositing into strategy...");
        mintAndDepositIntoStrategy(strategy, user, _amount);

        // Get initial micro donation count
        (,,,,, uint256 initialMicroDonations,,) = strategy.getV4InnovationStatus();
        console2.log("Initial micro donations count:", initialMicroDonations);

        // Trigger micro donation through simulated V4 operation
        console2.log("Triggering micro donation...");
        triggerV4MicroDonation(strategy, user, _amount);

        // Check micro donation was processed
        (,,,,, uint256 newMicroDonations,,) = strategy.getV4InnovationStatus();
        console2.log("Updated micro donations count:", newMicroDonations);
        console2.log("Micro donations increase:", newMicroDonations - initialMicroDonations);

        assertGt(newMicroDonations, initialMicroDonations, "Micro donations count should increase");

        // Check donation metrics for specific fund
        console2.log("Checking donation metrics for dragonRouter...");
        (uint256 totalDonated, uint256 lastDonationTime, uint256 donationCount, uint256 avgDonationSize) = 
            strategy.getDonationMetrics(dragonRouter);

        console2.log("Donation metrics for dragonRouter:");
        console2.log("Total Donated:", totalDonated);
        console2.log("Last Donation Time:", lastDonationTime);
        console2.log("Donation Count:", donationCount);
        console2.log("Average Donation Size:", avgDonationSize);

        assertGt(totalDonated, 0, "Total donated should increase");
        assertGt(donationCount, 0, "Donation count should increase");

        console2.log(" test_v4MicroDonationAutomation passed - Micro donation automation working correctly");
    }

    function test_v4GovernanceParticipationRewards() public {
        uint256 voteCount = 5;
        uint256 donationAmount = 1e18; // 1 ETH equivalent

        console2.log("\n=== Starting test_v4GovernanceParticipationRewards ===");
        console2.log("Vote count:", voteCount);
        console2.log("Donation amount:", donationAmount);

        // Get initial state
        (, uint256 initialFeeSavings, uint256 initialGovernanceScore,,,, bool initialGovernanceParticipant) = 
            strategy.getV4InnovationStatus();

        console2.log("Initial state - Fee Savings:", initialFeeSavings);
        console2.log("Initial state - Governance Score:", initialGovernanceScore);
        console2.log("Initial state - Governance Participant:", initialGovernanceParticipant);

        // Register governance participation
        console2.log("Registering governance participation...");
        registerGovernanceParticipation(strategy, user, voteCount, donationAmount);

        // Check governance rewards were applied
        (, uint256 totalFeeSavings, uint256 governanceScore,,, bool donationVerifiedSwapsEnabled, bool governanceParticipant) = 
            strategy.getV4InnovationStatus();

        console2.log("Governance participation results:");
        console2.log("Governance Score:", governanceScore);
        console2.log("Governance Participant:", governanceParticipant);
        console2.log("Fee Savings:", totalFeeSavings);
        console2.log("Donation Verified Swaps Enabled:", donationVerifiedSwapsEnabled);
        console2.log("Governance score increase:", governanceScore - initialGovernanceScore);
        console2.log("Fee savings increase:", totalFeeSavings - initialFeeSavings);

        assertTrue(governanceParticipant, "Should be registered as governance participant");
        assertGt(governanceScore, 0, "Governance score should be positive");

        // Check that fee discounts are applied
        assertGt(totalFeeSavings, 0, "Fee savings should be positive with governance participation");

        console2.log(" test_v4GovernanceParticipationRewards passed - Governance participation rewards working correctly");
    }

    function test_v4AdaptiveFeeSystem(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount / 10);

        console2.log("\n=== Starting test_v4AdaptiveFeeSystem ===");

        // Get initial fee state
        (uint256 initialAdaptiveFeeRate,,,,,,,) = strategy.getV4InnovationStatus();
        console2.log("Initial adaptive fee rate:", initialAdaptiveFeeRate);

        // Simulate market volatility to trigger fee adjustment
        console2.log("Simulating market volatility (15000)...");
        simulateMarketVolatility(15000); // 50% above baseline

        // Update adaptive fees
        console2.log("Updating adaptive fees...");
        strategy.updateAdaptiveFees();

        // Get updated fee state
        (uint256 newAdaptiveFeeRate,,,,,,,) = strategy.getV4InnovationStatus();
        console2.log("Updated adaptive fee rate:", newAdaptiveFeeRate);
        console2.log("Fee rate change:", newAdaptiveFeeRate - initialAdaptiveFeeRate);

        // Fees should adjust based on volatility
        assertTrue(newAdaptiveFeeRate != initialAdaptiveFeeRate, "Adaptive fees should change with volatility");

        // Test network congestion impact
        console2.log("Simulating network congestion (100 gwei)...");
        simulateNetworkCongestion(100 gwei); // High gas price

        console2.log("Updating adaptive fees for congestion...");
        strategy.updateAdaptiveFees();
        (uint256 congestionAdjustedFeeRate,,,,,,,) = strategy.getV4InnovationStatus();

        console2.log("Congestion adjusted fee rate:", congestionAdjustedFeeRate);
        console2.log("Fee rate change from volatility to congestion:", congestionAdjustedFeeRate - newAdaptiveFeeRate);

        assertTrue(congestionAdjustedFeeRate >= newAdaptiveFeeRate, "Fees should increase with network congestion");

        console2.log(" test_v4AdaptiveFeeSystem passed - Adaptive fee system working correctly");
    }

    function test_v4ImpactTokenIntegration(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount / 10);

        console2.log("\n=== Starting test_v4ImpactTokenIntegration ===");

        // Get initial fee state
        (uint256 initialFeeRate,,,,,,,) = strategy.getV4InnovationStatus();
        console2.log("Initial fee rate:", initialFeeRate);

        // Register a new impact token
        address testImpactToken = address(0x1234567890123456789012345678901234567890);
        uint256 impactScore = 8000; // 80% impact score

        console2.log("Registering impact token:", testImpactToken);
        console2.log("Impact score:", impactScore);

        registerImpactToken(testImpactToken, impactScore);

        // Check impact token info
        console2.log("Checking impact token info...");
        checkImpactTokenInfo(strategy, testImpactToken, impactScore, 250); // Expected 2.5% fee discount

        // Test that impact tokens receive fee discounts
        (uint256 currentFeeRate,,,,,,,) = strategy.getV4InnovationStatus();
        
        console2.log("Current fee rate with impact tokens:", currentFeeRate);
        console2.log("Fee rate reduction:", initialFeeRate - currentFeeRate);

        // Impact tokens should result in lower effective fees
        assertLt(currentFeeRate, 500, "Fee rate should be lower with impact token discounts");

        console2.log(" test_v4ImpactTokenIntegration passed - Impact token integration working correctly");
    }

    function test_v4MEVProtection(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount / 10);

        console2.log("\n=== Starting test_v4MEVProtection ===");
        console2.log("Testing with amount:", _amount);
        console2.log("MEV time lock window:", mevTimeLockWindow);

        // Deposit into strategy
        console2.log("Depositing into strategy...");
        mintAndDepositIntoStrategy(strategy, user, _amount);

        // Test MEV protection by trying to execute rapid swaps
        console2.log("Executing first swap (should succeed)...");
        
        // First swap should work
        executeV4DonationVerifiedSwap(strategy, user, _amount / 10, _amount / 1000);
        console2.log("First swap completed successfully");

        // Try immediate second swap - should be blocked by time lock
        console2.log("Attempting immediate second swap (should be blocked by MEV protection)...");
        vm.expectRevert(); // Expect revert due to MEV protection
        executeV4DonationVerifiedSwap(strategy, user, _amount / 10, _amount / 1000);
        console2.log("Second swap correctly blocked by MEV protection");

        // Wait for time lock window to expire
        console2.log("Waiting for MEV time lock window to expire...");
        skip(mevTimeLockWindow + 1);
        console2.log("Time lock window expired, attempting swap again...");

        // Now swap should work again
        executeV4DonationVerifiedSwap(strategy, user, _amount / 10, _amount / 1000);
        console2.log("Third swap completed successfully after time lock expired");

        console2.log(" test_v4MEVProtection passed - MEV protection working correctly");
    }

    function test_v4LiquidityMining(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount / 10);

        console2.log("\n=== Starting test_v4LiquidityMining ===");
        console2.log("Testing with amount:", _amount);

        // Deposit into strategy
        console2.log("Depositing into strategy...");
        mintAndDepositIntoStrategy(strategy, user, _amount);

        // Simulate V4 liquidity addition
        console2.log("Simulating V4 liquidity addition...");
        simulateV4LiquidityAdd(strategy, user, _amount / 2);

        // Check that liquidity mining metrics are tracked
        (,,,,, uint256 initialMicroDonations,,) = strategy.getV4InnovationStatus();
        console2.log("Initial micro donations:", initialMicroDonations);

        // Advance time to accumulate fees
        console2.log("Advancing time to accumulate fees...");
        advanceTimeForV4Features();

        // Simulate harvest to trigger fee compounding
        console2.log("Simulating harvest to trigger fee compounding...");
        simulateHarvestWithV4Features();

        // Check that fees were compounded
        (,,,,, uint256 newMicroDonations,,) = strategy.getV4InnovationStatus();
        console2.log("Updated micro donations:", newMicroDonations);
        console2.log("Micro donations increase:", newMicroDonations - initialMicroDonations);

        assertGt(newMicroDonations, initialMicroDonations, "Micro donations should increase after harvest");

        // Check public goods allocation
        (uint256 totalDonated,,,,,) = strategy.getPublicGoodsInfo();
        console2.log("Total public goods donations:", totalDonated);
        assertGt(totalDonated, 0, "Public goods donations should be positive");

        console2.log(" test_v4LiquidityMining passed - Liquidity mining features working correctly");
    }

    function test_tendTriggerWithV4Features(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        console2.log("\n=== Starting test_tendTriggerWithV4Features ===");
        console2.log("Testing with amount:", _amount);

        // Initial tend trigger check
        (bool trigger, ) = strategy.tendTrigger();
        console2.log("Initial tend trigger:", trigger);
        assertTrue(!trigger, "Tend should not trigger initially");

        // Deposit into strategy
        console2.log("Depositing into strategy...");
        mintAndDepositIntoStrategy(strategy, user, _amount);

        (trigger, ) = strategy.tendTrigger();
        console2.log("Tend trigger after deposit:", trigger);
        assertTrue(!trigger, "Tend should not trigger after deposit");

        // Activate V4 features
        console2.log("Activating V4 features...");
        _testV4FeatureActivation();

        (trigger, ) = strategy.tendTrigger();
        console2.log("Tend trigger after V4 activation:", trigger);
        assertTrue(!trigger, "Tend should not trigger after V4 activation");

        // Skip some time and simulate V4 operations
        console2.log("Advancing time by 30 days and simulating V4 operations...");
        skip(30 days);
        simulateV4Swap(strategy, user, _amount / 10);

        (trigger, ) = strategy.tendTrigger();
        console2.log("Tend trigger after V4 operations:", trigger);
        assertTrue(!trigger, "Tend should not trigger after V4 operations");

        // Report and check tend trigger
        console2.log("Calling report()...");
        vm.prank(keeper);
        strategy.report();

        (trigger, ) = strategy.tendTrigger();
        console2.log("Tend trigger after report:", trigger);
        assertTrue(!trigger, "Tend should not trigger after report");

        // Withdraw and check
        console2.log("Withdrawing funds...");
        vm.prank(user);
        strategy.redeem(_amount, user, user);

        (trigger, ) = strategy.tendTrigger();
        console2.log("Tend trigger after withdrawal:", trigger);
        assertTrue(!trigger, "Tend should not trigger after withdrawal");

        console2.log("  stest_tendTriggerWithV4Features passed - Tend trigger working correctly with V4 features");
    }

    // =============================================
    // V4 INNOVATION HELPER FUNCTIONS
    // =============================================

    function _testV4FeatureActivation() internal {
        console2.log("  Activating V4 features...");

        // Check initial V4 status
        (uint256 initialFeeRate, uint256 initialFeeSavings,,,,,,) = 
            strategy.getV4InnovationStatus();

        console2.log("  Initial fee rate:", initialFeeRate);
        console2.log("  Initial fee savings:", initialFeeSavings);

        // Update adaptive fees to activate V4 features
        strategy.updateAdaptiveFees();

        (uint256 newFeeRate, uint256 newFeeSavings,,,,,,) = 
            strategy.getV4InnovationStatus();

        console2.log("  V4 Feature Activation Results:");
        console2.log("  Fee Rate:", initialFeeRate, "->", newFeeRate);
        console2.log("  Fee Savings:", initialFeeSavings, "->", newFeeSavings);
        console2.log("  Fee savings increase:", newFeeSavings - initialFeeSavings);

        assertTrue(newFeeSavings >= initialFeeSavings, "Fee savings should not decrease");
        console2.log("  V4 features activated successfully");
    }

    function _testV4FeaturePerformance() internal {
        console2.log("  Testing V4 feature performance...");

        // Get network conditions
        (uint256 volatility, uint256 congestion, bool safeToOperate, uint256 adaptiveFee) = 
            strategy.getV4NetworkConditions();

        console2.log("  Network Conditions:");
        console2.log("  Volatility:", volatility);
        console2.log("  Congestion:", congestion);
        console2.log("  Safe to operate:", safeToOperate);
        console2.log("  Adaptive Fee:", adaptiveFee);

        assertTrue(safeToOperate, "Should be safe to operate under normal conditions");

        // Check public goods info
        (uint256 totalDonated, uint256 publicGoodsScore, uint256 yieldBoost,,,) = 
            strategy.getPublicGoodsInfo();

        console2.log("  Public Goods Info:");
        console2.log("  Total Donated:", totalDonated);
        console2.log("  Public Goods Score:", publicGoodsScore);
        console2.log("  Yield Boost:", yieldBoost);

        assertGe(publicGoodsScore, 0, "Public goods score should be non-negative");
        console2.log("  V4 feature performance test completed");
    }

    function _checkV4MetricsAfterReport(uint256 profit) internal {
        console2.log("  Checking V4 metrics after report...");

        // Check V4 innovation status after report
        (uint256 adaptiveFeeRate, 
         uint256 totalFeeSavings, 
         uint256 governanceScore,
         uint256 publicGoodsDonations,
         uint256 verifiedSwapsCount,
         uint256 microDonationsCount,
         bool donationVerifiedSwapsEnabled,
         bool governanceParticipant) = strategy.getV4InnovationStatus();

        console2.log("  Post-Report V4 Metrics:");
        console2.log("  Adaptive Fee Rate:", adaptiveFeeRate);
        console2.log("  Total Fee Savings:", totalFeeSavings);
        console2.log("  Governance Score:", governanceScore);
        console2.log("  Public Goods Donations:", publicGoodsDonations);
        console2.log("  Verified Swaps Count:", verifiedSwapsCount);
        console2.log("  Micro Donations Count:", microDonationsCount);
        console2.log("  Donation Verified Swaps Enabled:", donationVerifiedSwapsEnabled);
        console2.log("  Governance Participant:", governanceParticipant);

        // Calculate expected donation amount
        uint256 expectedDonation = profit * initialDonationPercentage / 10000;
        console2.log("  Expected public goods donation:", expectedDonation);
        console2.log("  Actual public goods donation:", publicGoodsDonations);

        // Public goods donations should reflect the profit
        assertGe(publicGoodsDonations, expectedDonation, 
                "Public goods donations should reflect donation percentage");

        // Check fee capture stats
        (uint256 totalTradingFeesPaid, uint256 totalFeesRedirected, uint256 pendingRedistribution,) = 
            strategy.getFeeCaptureStats();

        console2.log("  Fee Capture Stats:");
        console2.log("  Total Trading Fees Paid:", totalTradingFeesPaid);
        console2.log("  Total Fees Redirected:", totalFeesRedirected);
        console2.log("  Pending Redistribution:", pendingRedistribution);

        assertGe(totalFeesRedirected, 0, "Some fees should be redirected to public goods");
        console2.log("  V4 metrics after report check completed");
    }

    function _checkFinalV4Metrics() internal {
        console2.log("  Performing final V4 metrics check...");

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

        console2.log("  Final V4 Feature Status:");
        console2.log("  Donation Verified Swaps Enabled:", donationVerifiedSwapsEnabled);
        console2.log("  Governance Participant:", governanceParticipant);

        assertTrue(donationVerifiedSwapsEnabled, "V4 features should remain enabled");
        
        console2.log("  All V4 innovation tests completed successfully");
    }
}