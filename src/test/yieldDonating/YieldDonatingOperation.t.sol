// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import "forge-std/console2.sol";
import {YieldDonatingSetup as Setup, ERC20, IStrategyInterface} from "./YieldDonatingSetup.sol";

contract YieldDonatingOperationTest is Setup {
    function setUp() public virtual override {
        super.setUp();
    }

    function test_setupStrategyOK() public {
        console2.log("address of strategy", address(strategy));
        assertTrue(address(0) != address(strategy));
        assertEq(strategy.asset(), address(asset));
        assertEq(strategy.management(), management);
        assertEq(strategy.dragonRouter(), dragonRouter);
        assertEq(strategy.keeper(), keeper);
        assertEq(strategy.enableBurning(), enableBurning);
    }

    function test_operation(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        assertEq(strategy.totalAssets(), _amount, "!totalAssets");

        // Earn Interest
        skip(1 days);

        // Report profit
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();

        // Check return Values
        assertGe(profit, 0, "!profit");
        assertEq(loss, 0, "!loss");

        // YieldDonating strategies don't have profit unlocking time
        // skip(strategy.profitMaxUnlockTime());

        uint256 balanceBefore = asset.balanceOf(user);

        // Withdraw all funds
        vm.prank(user);
        strategy.redeem(_amount, user, user);

        assertGe(
            asset.balanceOf(user),
            balanceBefore + _amount,
            "!final balance"
        );
    }

    function test_profitableReport(
        uint256 _amount,
        uint16 _profitFactor
    ) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);
        _profitFactor = uint16(bound(uint256(_profitFactor), 10, MAX_BPS));

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        assertEq(strategy.totalAssets(), _amount, "!totalAssets");

        // Earn Interest
        skip(1 days);

        // Simulate earning interest.
        uint256 toAirdrop = (_amount * _profitFactor) / MAX_BPS;
        airdrop(asset, address(strategy), toAirdrop);

        // Report profit
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();

        // Check return Values
        assertGe(profit, toAirdrop, "!profit");
        assertEq(loss, 0, "!loss");

        // Check that profit was minted to dragon router
        uint256 dragonRouterShares = strategy.balanceOf(dragonRouter);
        assertGt(dragonRouterShares, 0, "!dragon router shares");

        // Convert shares back to assets to verify
        uint256 dragonRouterAssets = strategy.convertToAssets(
            dragonRouterShares
        );
        assertEq(dragonRouterAssets, toAirdrop, "!dragon router assets");

        uint256 balanceBefore = asset.balanceOf(user);

        // Withdraw all funds
        vm.prank(user);
        strategy.redeem(_amount, user, user);

        assertGe(
            asset.balanceOf(user),
            balanceBefore + _amount,
            "!final balance"
        );
    }

    function test_lossReport_withBurning(
        uint256 _amount,
        uint16 _lossFactor
    ) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);
        _lossFactor = uint16(bound(uint256(_lossFactor), 10, 5000)); // Max 50% loss

        // First deposit and create some profits to mint shares to dragon router
        mintAndDepositIntoStrategy(strategy, user, _amount);

        // Create profit
        uint256 profitAmount = _amount / 10; // 10% profit
        airdrop(asset, address(strategy), profitAmount);

        vm.prank(keeper);
        strategy.report();

        uint256 dragonSharesBefore = strategy.balanceOf(dragonRouter);
        assertGt(dragonSharesBefore, 0, "Dragon router should have shares");

        // Now simulate loss
        uint256 lossAmount = (_amount * _lossFactor) / MAX_BPS;

        // Remove funds to simulate loss
        vm.prank(address(strategy));
        asset.transfer(address(0xdead), lossAmount);

        // Report loss
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();

        assertEq(profit, 0, "!profit should be 0");
        assertGe(loss, lossAmount, "!loss");

        // Check that dragon shares were burned to cover loss
        uint256 dragonSharesAfter = strategy.balanceOf(dragonRouter);
        assertLt(
            dragonSharesAfter,
            dragonSharesBefore,
            "Dragon shares should be burned"
        );

        // If loss was bigger than dragon shares value, some shares should remain
        if (lossAmount > strategy.convertToAssets(dragonSharesBefore)) {
            assertGt(dragonSharesAfter, 0, "Some dragon shares should remain");
        }
    }

    function test_tendTrigger(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        (bool trigger, ) = strategy.tendTrigger();
        assertTrue(!trigger);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        (trigger, ) = strategy.tendTrigger();
        assertTrue(!trigger);

        // Skip some time
        skip(1 days);

        (trigger, ) = strategy.tendTrigger();
        assertTrue(!trigger);

        vm.prank(keeper);
        strategy.report();

        (trigger, ) = strategy.tendTrigger();
        assertTrue(!trigger);

        // Unlock Profits
        // YieldDonating strategies don't have profit unlocking time
        // skip(strategy.profitMaxUnlockTime());

        (trigger, ) = strategy.tendTrigger();
        assertTrue(!trigger);

        vm.prank(user);
        strategy.redeem(_amount, user, user);

        (trigger, ) = strategy.tendTrigger();
        assertTrue(!trigger);
    }
}
