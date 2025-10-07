// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import {console2} from "forge-std/console2.sol";
import {Test} from "forge-std/Test.sol";

import {YieldSkimmingStrategy} from "../../strategies/yieldSkimming/YieldSkimmingStrategy.sol";
import {YieldSkimmingStrategyFactory} from "../../strategies/yieldSkimming/YieldSkimmingStrategyFactory.sol";
import {IStrategyInterface} from "../../interfaces/IStrategyInterface.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

contract YieldSkimmingSetup is Test {
    // Contract instances that we will use repeatedly.
    IERC20 public asset;
    YieldSkimmingStrategy public skimmingStrategy;
    IStrategyInterface public strategy; // For compatibility with existing interface

    YieldSkimmingStrategyFactory public strategyFactory;

    mapping(string => address) public tokenAddrs;

    // Addresses for different roles we will use repeatedly.
    address public user = address(10);
    address public keeper = address(4);
    address public management = address(1);
    address public dragonRouter = address(3); // Receives yield donations
    address public emergencyAdmin = address(5);

    // Integer variables that will be used repeatedly.
    uint256 public decimals;
    uint256 public maxBps = 10_000;
    uint256 public constant MAX_BPS = 10_000;

    // Fuzz from $0.01 of 1e6 stable coins up to 1 trillion of a 1e18 coin
    uint256 public maxFuzzAmount = 1e30;
    uint256 public minFuzzAmount = 10_000;

    function setUp() public virtual {
        _setTokenAddrs();

        // Set asset - using wstETH as example yield-bearing asset
        asset = IERC20(tokenAddrs["WSTETH"]);

        // Set decimals
        decimals = 18; // wstETH uses 18 decimals

        strategyFactory = new YieldSkimmingStrategyFactory(
            management,
            dragonRouter,
            keeper,
            emergencyAdmin
        );

        // Deploy strategy and set variables
        skimmingStrategy = YieldSkimmingStrategy(setUpStrategy());
        strategy = IStrategyInterface(address(skimmingStrategy)); // For compatibility

        // label all the used addresses for traces
        vm.label(keeper, "keeper");
        vm.label(address(asset), "asset");
        vm.label(management, "management");
        vm.label(address(skimmingStrategy), "skimmingStrategy");
        vm.label(dragonRouter, "dragonRouter");
    }

    function setUpStrategy() public returns (address) {
        // Deploy strategy using factory
        address _strategy = strategyFactory.newStrategy(
            address(asset),
            "YieldSkimming Strategy"
        );

        return _strategy;
    }

    function depositIntoStrategy(
        YieldSkimmingStrategy _strategy,
        address _user,
        uint256 _amount
    ) public {
        vm.prank(_user);
        asset.approve(address(_strategy), _amount);

        vm.prank(_user);
        _strategy.deposit(_amount, _user);
    }

    function mintAndDepositIntoStrategy(
        YieldSkimmingStrategy _strategy,
        address _user,
        uint256 _amount
    ) public {
        airdrop(asset, _user, _amount);
        depositIntoStrategy(_strategy, _user, _amount);
    }

    // For checking the amounts in the strategy
    function checkStrategyTotals(
        YieldSkimmingStrategy _strategy,
        uint256 _totalAssets,
        uint256 _totalDebt,
        uint256 _totalIdle
    ) public {
        uint256 _assets = _strategy.totalAssets();
        uint256 _balance = asset.balanceOf(address(_strategy));
        uint256 _idle = _balance > _assets ? _assets : _balance;
        uint256 _debt = _assets - _idle;
        assertEq(_assets, _totalAssets, "!totalAssets");
        assertEq(_debt, _totalDebt, "!totalDebt");
        assertEq(_idle, _totalIdle, "!totalIdle");
        assertEq(_totalAssets, _totalDebt + _totalIdle, "!Added");
    }

    function airdrop(IERC20 _asset, address _to, uint256 _amount) public {
        uint256 balanceBefore = _asset.balanceOf(_to);
        deal(address(_asset), _to, balanceBefore + _amount);
    }

    function setDragonRouter(address _newDragonRouter) public {
        vm.prank(management);
        skimmingStrategy.setPendingDragonRouter(_newDragonRouter);
        
        // Fast forward to bypass cooldown
        skip(7 days);
        
        // Anyone can finalize after cooldown
        skimmingStrategy.finalizeDragonRouterChange();
    }
    
    function setEnableBurning(bool _enableBurning) public {
        vm.prank(management);
        skimmingStrategy.setEnableBurning(_enableBurning);
    }
    
    /**
     * @notice Helper function to simulate yield appreciation through exchange rate changes
     * @param _newRate The new exchange rate (in 18 decimals, e.g., 1.1e18 for 10% appreciation)
     */
    function simulateYieldAppreciation(uint256 _newRate) public {
        vm.mockCall(
            address(skimmingStrategy),
            abi.encodeWithSignature("getCurrentExchangeRate()"),
            abi.encode(_newRate)
        );
    }
    
    /**
     * @notice Clear the mock for getCurrentExchangeRate to return to normal behavior
     */
    function clearExchangeRateMock() public {
        vm.clearMockedCalls();
    }

    function _setTokenAddrs() internal {
        tokenAddrs["WBTC"] = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
        tokenAddrs["YFI"] = 0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e;
        tokenAddrs["WETH"] = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        tokenAddrs["LINK"] = 0x514910771AF9Ca656af840dff83E8264EcF986CA;
        tokenAddrs["USDT"] = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
        tokenAddrs["DAI"] = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
        tokenAddrs["USDC"] = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        tokenAddrs["WSTETH"] = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0; // Lido wstETH
        tokenAddrs["RETH"] = 0xae78736Cd615f374D3085123A210448E74Fc6393; // Rocket Pool rETH
    }
}