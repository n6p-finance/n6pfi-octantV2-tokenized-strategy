// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import "forge-std/console2.sol";
import {YieldSkimmingSetup, ERC20} from "./YieldSkimmingSetup.sol";
import {YieldSkimmingStrategy} from "../../strategies/yieldSkimming/YieldSkimmingStrategy.sol";
import {ITokenizedStrategy} from "@octant-core/interfaces/ITokenizedStrategy.sol";

contract YieldSkimmingOperationTest is YieldSkimmingSetup {
    ITokenizedStrategy public tokenizedStrategy;
    
    function setUp() public virtual override {
        super.setUp();
        tokenizedStrategy = ITokenizedStrategy(address(skimmingStrategy));
    }

    function testSetupStrategyOK() public {
        console2.log("address of strategy", address(skimmingStrategy));
        assertTrue(address(0) != address(skimmingStrategy));
        assertEq(address(skimmingStrategy.asset()), address(asset));
        // Check basic strategy setup
        assertEq(skimmingStrategy.getCurrentExchangeRate(), 1e18); // Should start at 1:1
        assertEq(skimmingStrategy.decimalsOfExchangeRate(), 18);
    }

    function testBasicDeposit(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        // Deposit into strategy
        mintAndDepositIntoStrategy(skimmingStrategy, user, _amount);

        assertEq(skimmingStrategy.totalAssets(), _amount, "!totalAssets");
        
        // Check basic share accounting
        uint256 expectedShares = _amount; // 1:1 rate means amount = shares
        assertEq(tokenizedStrategy.balanceOf(user), expectedShares, "!user shares");

        uint256 balanceBefore = asset.balanceOf(user);

        // Withdraw all funds
        vm.prank(user);
        skimmingStrategy.redeem(expectedShares, user, user);

        assertEq(
            asset.balanceOf(user),
            balanceBefore + _amount,
            "!final balance"
        );
    }

    function testExchangeRateTracking(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        // Deposit into strategy
        mintAndDepositIntoStrategy(skimmingStrategy, user, _amount);
        uint256 initialShares = tokenizedStrategy.balanceOf(user);
        
        assertEq(skimmingStrategy.totalAssets(), _amount, "!totalAssets");
        assertEq(skimmingStrategy.lastExchangeRate(), 1e18, "!initial rate should be 1:1");

        // Calculate initial ETH value: amount * initial_rate = _amount * 1e18 / 1e18 = _amount
        uint256 initialEthValue = (_amount * 1e18) / 1e18; // ETH equivalent value
        
        // Simulate yield appreciation by mocking an increased exchange rate
        uint256 newExchangeRate = 1.1e18; // 10% appreciation (1.1:1 ratio)
        simulateYieldAppreciation(newExchangeRate);
        
        // Report should detect the appreciation and calculate yield
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = skimmingStrategy.report();

        // Check that the exchange rate was updated
        assertEq(skimmingStrategy.lastExchangeRate(), newExchangeRate, "!exchange rate updated");
        assertEq(loss, 0, "!loss should be 0");
        
        // Check that donation address received shares representing the yield
        uint256 donationShares = strategy.balanceOf(donationAddress);
        assertGt(donationShares, 0, "!donation address should have received shares");

        uint256 balanceBefore = asset.balanceOf(user);

        // User withdraws their shares
        vm.prank(user);
        skimmingStrategy.redeem(initialShares, user, user);

        uint256 userReceived = asset.balanceOf(user) - balanceBefore;
        
        // Key assertion: User gets same ETH value (fewer wstETH tokens due to appreciation)
        // At new exchange rate 1.1, to get 100 ETH worth, user should get ~90.9 wstETH
        uint256 expectedTokensForSameEthValue = (initialEthValue * 1e18) / newExchangeRate;
        
        // User should get back fewer tokens but same ETH value
        assertLt(userReceived, _amount, "!user should get fewer tokens due to appreciation");
        assertApproxEqAbs(userReceived, expectedTokensForSameEthValue, 2, "!user should get same ETH value in fewer tokens");
        
        // Verify the ETH value is preserved
        uint256 userEthValue = (userReceived * newExchangeRate) / 1e18;
        assertApproxEqAbs(userEthValue, initialEthValue, 2, "!user ETH value should be preserved");
    }

    function testYieldDistribution(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);
        
        // Deposit into strategy
        mintAndDepositIntoStrategy(skimmingStrategy, user, _amount);
        uint256 initialShares = strategy.balanceOf(user);
        
        // Calculate initial ETH value
        uint256 initialEthValue = (_amount * 1e18) / 1e18; // At 1:1 rate
        
        // Simulate 20% appreciation
        uint256 appreciationRate = 1.2e18; // 20% appreciation
        simulateYieldAppreciation(appreciationRate);
        
        // Report to capture yield
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = skimmingStrategy.report();
        
        assertEq(loss, 0, "!no loss");
        assertGt(profit, 0, "!should have profit from appreciation");
        
        // Check donation address received shares for the yield
        uint256 donationShares = strategy.balanceOf(donationAddress);
        assertGt(donationShares, 0, "!donation address should have yield shares");
        
        // The user should still have their original shares
        assertEq(strategy.balanceOf(user), initialShares, "!user shares unchanged");
        
        // Total shares should have increased (new shares minted to donation address)
        uint256 totalShares = strategy.totalSupply();
        assertGt(totalShares, initialShares, "!total shares increased");
        
        // When user withdraws, they should get same ETH value in fewer tokens
        uint256 balanceBefore = asset.balanceOf(user);
        vm.prank(user);
        skimmingStrategy.redeem(initialShares, user, user);
        
        uint256 userReceived = asset.balanceOf(user) - balanceBefore;
        
        // User gets fewer tokens but same ETH value
        assertLt(userReceived, _amount, "!user gets fewer tokens");
        
        // Expected tokens for same ETH value at new rate
        uint256 expectedTokensForSameEthValue = (initialEthValue * 1e18) / appreciationRate;
        assertApproxEqAbs(userReceived, expectedTokensForSameEthValue, 2, "!user gets same ETH value");
        
        // Verify ETH value is preserved
        uint256 userEthValue = (userReceived * appreciationRate) / 1e18;
        assertApproxEqAbs(userEthValue, initialEthValue, 2, "!user ETH value preserved");
        
        // The donation address should be able to redeem their yield shares
        uint256 donationBalanceBefore = asset.balanceOf(donationAddress);
        vm.prank(donationAddress);
        strategy.redeem(donationShares, donationAddress, donationAddress);
        
        uint256 donationReceived = asset.balanceOf(donationAddress) - donationBalanceBefore;
        assertGt(donationReceived, 0, "!donation address should receive yield");
    }

    function testExchangeRateFunctionality(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        // Test exchange rate functions
        assertEq(skimmingStrategy.getCurrentExchangeRate(), 1e18, "!rate should be 1:1");
        assertEq(skimmingStrategy.decimalsOfExchangeRate(), 18, "!decimals should be 18");
        
        // Deposit and check that rate tracking works
        mintAndDepositIntoStrategy(skimmingStrategy, user, _amount);
        assertEq(skimmingStrategy.lastExchangeRate(), 1e18, "!tracked rate");
    }

    function testLossDetection(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount / 2);

        // Deposit into strategy
        mintAndDepositIntoStrategy(skimmingStrategy, user, _amount);
        
        // Simulate a loss by removing assets
        uint256 lossAmount = _amount / 10; // 10% loss
        vm.prank(address(skimmingStrategy));
        asset.transfer(address(0xdead), lossAmount);
        
        // Report should detect the loss
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = skimmingStrategy.report();
        
        assertEq(profit, 0, "!profit should be 0");
        assertGt(loss, 0, "!loss should be > 0");
        
        // Total assets should reflect the loss
        assertEq(skimmingStrategy.totalAssets(), _amount - lossAmount, "!total assets after loss");
    }

    function testAvailableLimits(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        // Test available limits
        assertEq(skimmingStrategy.availableDepositLimit(user), type(uint256).max, "!unlimited deposit");
        assertEq(skimmingStrategy.availableWithdrawLimit(user), 0, "!no assets to withdraw initially");
        
        // After depositing, withdrawal limit should update
        mintAndDepositIntoStrategy(skimmingStrategy, user, _amount);
        assertEq(skimmingStrategy.availableWithdrawLimit(user), _amount, "!withdrawal limit after deposit");
    }
    
    function testTendTrigger(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        // Yield skimming strategies typically don't need tending
        (bool trigger, ) = skimmingStrategy.tendTrigger();
        assertTrue(!trigger);

        // Deposit into strategy
        mintAndDepositIntoStrategy(skimmingStrategy, user, _amount);

        (trigger, ) = skimmingStrategy.tendTrigger();
        assertTrue(!trigger);

        // Skip some time
        skip(1 days);

        (trigger, ) = skimmingStrategy.tendTrigger();
        assertTrue(!trigger);

        vm.prank(keeper);
        skimmingStrategy.report();

        (trigger, ) = skimmingStrategy.tendTrigger();
        assertTrue(!trigger);

        uint256 userShares = tokenizedStrategy.balanceOf(user);
        if (userShares > 0) {
            vm.prank(user);
            skimmingStrategy.redeem(userShares, user, user);
        }

        (trigger, ) = skimmingStrategy.tendTrigger();
        assertTrue(!trigger);
    }
}