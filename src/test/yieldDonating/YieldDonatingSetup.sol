// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import "forge-std/console2.sol";
import {Test} from "forge-std/Test.sol";

import {AaveV4PublicGoodsStrategyEnhanced as Strategy, ERC20} from "../../strategies/AaveV4PublicGoodsStrategyEnhanced.sol";
import {AaveAdapterV4Enhanced} from "../../adapters/AaveAdapterV4Enhanced.sol";
import {IStrategyInterface} from "../../interfaces/IStrategyInterface.sol";
import {ITokenizedStrategy} from "@octant-core/core/interfaces/ITokenizedStrategy.sol";

// Uniswap V4 imports
import {IPoolManager} from "v4-core/contracts/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/contracts/types/PoolKey.sol";
import {Currency, CurrencyLibrary} from "v4-core/contracts/types/Currency.sol";

// Inherit the events so they can be checked if desired.
import {IEvents} from "@tokenized-strategy/interfaces/IEvents.sol";

contract AaveV4PublicGoodsStrategySetup is Test, IEvents {
    using CurrencyLibrary for Currency;

    // Contract instances that we will use repeatedly.
    ERC20 public asset;
    IStrategyInterface public strategy;
    AaveAdapterV4Enhanced public aaveAdapter;
    IPoolManager public poolManager;

    // Addresses for different roles we will use repeatedly.
    address public user = address(10);
    address public keeper = address(4);
    address public management = address(1);
    address public dragonRouter = address(3); // This is the donation address
    address public emergencyAdmin = address(5);
    address public v4Hook = address(6);

    // V4 Specific addresses
    address public uniswapV4PoolManager = address(7);
    address public aaveLendingPool = address(8);
    address public aaveRewardsController = address(9);
    address public octantV2 = address(11);
    address public glowDistributionPool = address(12);

    // V4 Strategy specific variables
    bool public enableV4Features = true;
    uint256 public initialDonationPercentage = 500; // 5%
    address public tokenizedStrategyAddress;
    address public yieldSource;

    // V4 Pool Configuration
    PoolKey public samplePoolKey;

    // Integer variables that will be used repeatedly.
    uint256 public decimals;
    uint256 public MAX_BPS = 10_000;

    // Fuzz from $0.01 of 1e6 stable coins up to 1,000,000 of the asset
    uint256 public maxFuzzAmount;
    uint256 public minFuzzAmount = 10_000;

    // Default profit max unlock time is set for 10 days
    uint256 public profitMaxUnlockTime = 10 days;

    // V4 Innovation Test Parameters
    uint256 public microDonationBps = 10; // 0.1%
    uint256 public minMicroDonation = 1e15; // 0.001 ETH
    bool public autoCompoundFees = true;
    uint256 public feeReinvestmentBps = 8000; // 80%
    bool public mevProtectionEnabled = true;
    uint256 public mevTimeLockWindow = 5 minutes;

    function setUp() public virtual {
        // Read asset address from environment
        address testAssetAddress = vm.envAddress("TEST_ASSET_ADDRESS");
        require(testAssetAddress != address(0), "TEST_ASSET_ADDRESS not set in .env");

        // Set asset
        asset = ERC20(testAssetAddress);

        // Set decimals
        decimals = asset.decimals();

        // Set max fuzz amount to 1,000,000 of the asset
        maxFuzzAmount = 1_000_000 * 10 ** decimals;

        // Read yield source from environment
        yieldSource = vm.envAddress("TEST_YIELD_SOURCE");
        require(yieldSource != address(0), "TEST_YIELD_SOURCE not set in .env");

        // Deploy mock Aave Adapter
        aaveAdapter = new AaveAdapterV4Enhanced(
            aaveLendingPool,
            aaveRewardsController,
            IPoolManager(uniswapV4PoolManager),
            glowDistributionPool
        );

        // Deploy mock Pool Manager
        poolManager = IPoolManager(uniswapV4PoolManager);

        // Initialize sample V4 pool key for testing
        _initializeSamplePoolKey();

        // Deploy strategy and set variables
        strategy = IStrategyInterface(setUpStrategy());

        // label all the used addresses for traces
        vm.label(keeper, "keeper");
        vm.label(address(asset), "asset");
        vm.label(management, "management");
        vm.label(address(strategy), "strategy");
        vm.label(dragonRouter, "dragonRouter");
        vm.label(address(aaveAdapter), "aaveAdapter");
        vm.label(address(poolManager), "poolManager");
        vm.label(octantV2, "octantV2");
        vm.label(glowDistributionPool, "glowDistributionPool");
    }

    function _initializeSamplePoolKey() internal {
        samplePoolKey = PoolKey({
            currency0: Currency.wrap(address(asset)),
            currency1: Currency.wrap(address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2)), // WETH
            fee: 3000, // 0.3%
            tickSpacing: 60,
            hooks: v4Hook
        });
    }

    function setUpStrategy() public returns (address) {
        // we save the strategy as a IStrategyInterface to give it the needed interface
        IStrategyInterface _strategy = IStrategyInterface(
            address(
                new Strategy(
                    address(asset),
                    "Aave V4 Public Goods Strategy Enhanced",
                    aaveLendingPool,
                    poolManager,
                    address(aaveAdapter),
                    initialDonationPercentage
                )
            )
        );

        // Set up V4 specific configurations after deployment
        _setupV4StrategyConfig(_strategy);

        return address(_strategy);
    }

    function _setupV4StrategyConfig(IStrategyInterface _strategy) internal {
        // Set V4 innovation configurations
        vm.prank(management);
        _strategy.setV4InnovationConfig(
            true,  // donationVerifiedSwaps
            true,  // adaptiveFeeOptimization  
            true,  // impactTokenPriority
            true,  // microDonationAutomation
            microDonationBps
        );

        // Set up donation recipients
        address[] memory recipients = new address[](3);
        recipients[0] = dragonRouter;
        recipients[1] = glowDistributionPool;
        recipients[2] = octantV2;

        uint256[] memory weights = new uint256[](3);
        weights[0] = 4000; // 40%
        weights[1] = 4000; // 40%
        weights[2] = 2000; // 20%

        vm.prank(management);
        _strategy.updateDonationRecipients(recipients, weights);

        // Register impact tokens
        vm.prank(management);
        _strategy.registerImpactToken(address(asset), 7500); // 75% impact score

        // Set up MEV protection
        vm.prank(management);
        _strategy.setMEVProtectionConfig(
            mevProtectionEnabled,
            50, // 0.5% max slippage
            minFuzzAmount,
            maxFuzzAmount / 10,
            mevTimeLockWindow
        );

        // Set up liquidity mining
        vm.prank(management);
        _strategy.setLiquidityMiningConfig(
            autoCompoundFees,
            minMicroDonation * 10, // 0.01 ETH threshold
            feeReinvestmentBps
        );
    }

    function depositIntoStrategy(IStrategyInterface _strategy, address _user, uint256 _amount) public {
        vm.prank(_user);
        asset.approve(address(_strategy), _amount);

        vm.prank(_user);
        _strategy.deposit(_amount, _user);
    }

    function mintAndDepositIntoStrategy(IStrategyInterface _strategy, address _user, uint256 _amount) public {
        airdrop(asset, _user, _amount);
        depositIntoStrategy(_strategy, _user, _amount);
    }

    // Enhanced test function for V4 features
    function executeV4DonationVerifiedSwap(
        IStrategyInterface _strategy,
        address _user,
        uint256 _amount,
        uint256 _donationAmount
    ) public returns (uint256) {
        vm.prank(_user);
        asset.approve(address(_strategy), _amount + _donationAmount);

        // This would call the actual donation verified swap function
        // For testing, we'll simulate the behavior
        vm.prank(_user);
        return _strategy.executeDonationVerifiedSwap(
            address(asset),
            address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2), // WETH
            _amount,
            _amount * 9950 / 10000, // 0.5% slippage
            _donationAmount
        );
    }

    function registerGovernanceParticipation(
        IStrategyInterface _strategy,
        address _user,
        uint256 _voteCount,
        uint256 _donationAmount
    ) public {
        vm.prank(_user);
        _strategy.registerGovernanceParticipation(_voteCount, _donationAmount);
    }

    function triggerV4MicroDonation(IStrategyInterface _strategy, address _user, uint256 _operationAmount) public {
        // Simulate a V4 operation that triggers micro-donation
        bytes32 operationHash = keccak256(abi.encodePacked(_operationAmount, block.timestamp, _user));
        vm.prank(_user);
        _strategy.triggerMicroDonation(_operationAmount, operationHash);
    }

    function simulateV4Swap(
        IStrategyInterface _strategy,
        address _user,
        uint256 _amount
    ) public {
        vm.prank(_user);
        _strategy.simulateV4Swap(_amount);
    }

    function simulateV4LiquidityAdd(
        IStrategyInterface _strategy,
        address _user,
        uint256 _amount
    ) public {
        vm.prank(_user);
        _strategy.simulateV4LiquidityAdd(_amount);
    }

    // For checking the amounts in the strategy
    function checkStrategyTotals(
        IStrategyInterface _strategy,
        uint256 _totalAssets,
        uint256 _totalDebt,
        uint256 _totalIdle
    ) public {
        uint256 _assets = _strategy.totalAssets();
        uint256 _balance = ERC20(_strategy.asset()).balanceOf(address(_strategy));
        uint256 _idle = _balance > _assets ? _assets : _balance;
        uint256 _debt = _assets - _idle;
        assertEq(_assets, _totalAssets, "!totalAssets");
        assertEq(_debt, _totalDebt, "!totalDebt");
        assertEq(_idle, _totalIdle, "!totalIdle");
        assertEq(_totalAssets, _totalDebt + _totalIdle, "!Added");
    }

    // Enhanced V4 metrics checking
    function checkV4StrategyMetrics(
        IStrategyInterface _strategy,
        uint256 _expectedFeeSavings,
        uint256 _expectedPublicGoodsDonations,
        uint256 _expectedVerifiedSwaps,
        uint256 _expectedMicroDonations
    ) public {
        (uint256 adaptiveFeeRate, 
         uint256 totalFeeSavings, 
         uint256 governanceScore,
         uint256 publicGoodsDonations,
         uint256 verifiedSwapsCount,
         uint256 microDonationsCount,
         bool donationVerifiedSwapsEnabled,
         bool governanceParticipant) = _strategy.getV4InnovationStatus();

        console2.log("V4 Strategy Metrics:");
        console2.log("Adaptive Fee Rate:", adaptiveFeeRate);
        console2.log("Total Fee Savings:", totalFeeSavings);
        console2.log("Governance Score:", governanceScore);
        console2.log("Public Goods Donations:", publicGoodsDonations);
        console2.log("Verified Swaps Count:", verifiedSwapsCount);
        console2.log("Micro Donations Count:", microDonationsCount);
        console2.log("Donation Verified Swaps Enabled:", donationVerifiedSwapsEnabled);
        console2.log("Governance Participant:", governanceParticipant);

        assertGe(totalFeeSavings, _expectedFeeSavings, "!feeSavings");
        assertGe(publicGoodsDonations, _expectedPublicGoodsDonations, "!publicGoodsDonations");
        assertGe(verifiedSwapsCount, _expectedVerifiedSwaps, "!verifiedSwaps");
        assertGe(microDonationsCount, _expectedMicroDonations, "!microDonations");
    }

    function checkImpactTokenInfo(
        IStrategyInterface _strategy,
        address _token,
        uint256 _expectedImpactScore,
        uint256 _expectedFeeDiscount
    ) public {
        (uint256 impactScore,
         uint256 feeDiscount,
         uint256 lastUpdate,
         bool isHighImpact) = _strategy.getImpactTokenInfo(_token);

        console2.log("Impact Token Info for", _token);
        console2.log("Impact Score:", impactScore);
        console2.log("Fee Discount:", feeDiscount);
        console2.log("Last Update:", lastUpdate);
        console2.log("Is High Impact:", isHighImpact);

        assertEq(impactScore, _expectedImpactScore, "!impactScore");
        assertGe(feeDiscount, _expectedFeeDiscount, "!feeDiscount");
        assertTrue(isHighImpact, "!isHighImpact");
    }

    function airdrop(ERC20 _asset, address _to, uint256 _amount) public {
        uint256 balanceBefore = _asset.balanceOf(_to);
        deal(address(_asset), _to, balanceBefore + _amount);
    }

    function setDragonRouter(address _newDragonRouter) public {
        vm.prank(management);
        ITokenizedStrategy(address(strategy)).setDragonRouter(_newDragonRouter);

        // Fast forward to bypass cooldown
        skip(7 days);

        // Anyone can finalize after cooldown
        ITokenizedStrategy(address(strategy)).finalizeDragonRouterChange();
    }

    function setV4InnovationConfig(
        bool _donationVerifiedSwaps,
        bool _adaptiveFeeOptimization,
        bool _impactTokenPriority,
        bool _microDonationAutomation,
        uint256 _microDonationBps
    ) public {
        vm.prank(management);
        strategy.setV4InnovationConfig(
            _donationVerifiedSwaps,
            _adaptiveFeeOptimization,
            _impactTokenPriority,
            _microDonationAutomation,
            _microDonationBps
        );
    }

    function updateDonationRecipients(
        address[] memory _newRecipients,
        uint256[] memory _newWeights
    ) public {
        vm.prank(management);
        strategy.updateDonationRecipients(_newRecipients, _newWeights);
    }

    function registerImpactToken(address _token, uint256 _impactScore) public {
        vm.prank(management);
        strategy.registerImpactToken(_token, _impactScore);
    }

    function setMEVProtectionConfig(
        bool _enabled,
        uint256 _maxSlippageBps,
        uint256 _minSwapAmount,
        uint256 _maxSwapAmount,
        uint256 _timeLockWindow
    ) public {
        vm.prank(management);
        strategy.setMEVProtectionConfig(
            _enabled,
            _maxSlippageBps,
            _minSwapAmount,
            _maxSwapAmount,
            _timeLockWindow
        );
    }

    function setLiquidityMiningConfig(
        bool _autoCompoundFees,
        uint256 _minFeeClaimThreshold,
        uint256 _feeReinvestmentBps
    ) public {
        vm.prank(management);
        strategy.setLiquidityMiningConfig(
            _autoCompoundFees,
            _minFeeClaimThreshold,
            _feeReinvestmentBps
        );
    }

    function simulateHarvestWithV4Features() public {
        // Simulate a harvest that includes V4 features
        vm.prank(keeper);
        strategy.harvest();
    }

    function getV4NetworkConditions() public view returns (
        uint256 currentVolatility,
        uint256 networkCongestion,
        bool safeToOperate,
        uint256 adaptiveFeeRate
    ) {
        return strategy.getV4NetworkConditions();
    }

    function getPublicGoodsInfo() public view returns (
        uint256 totalDonated,
        uint256 publicGoodsScore,
        uint256 yieldBoost,
        uint256 pendingRedistribution,
        address[] memory supportedFunds,
        uint256[] memory allocationWeights
    ) {
        return strategy.getPublicGoodsInfo();
    }

    function getDonationMetrics(address _fund) public view returns (
        uint256 totalDonated,
        uint256 lastDonationTime,
        uint256 donationCount,
        uint256 avgDonationSize
    ) {
        return strategy.getDonationMetrics(_fund);
    }

    function getFeeCaptureStats() public view returns (
        uint256 totalTradingFeesPaid,
        uint256 totalFeesRedirected,
        uint256 pendingRedistribution,
        uint256 lastCaptureTime
    ) {
        return strategy.getFeeCaptureStats();
    }

    // Helper function to simulate time passage for V4 features
    function advanceTimeForV4Features() public {
        // Advance time to trigger various V4 features
        skip(1 days);
    }

    // Helper function to simulate market volatility
    function simulateMarketVolatility(uint256 _volatilityLevel) public {
        // This would interact with the strategy's volatility oracle
        // For testing, we can manipulate the strategy's internal state
        // Implementation depends on how volatility is measured
    }

    // Helper function to simulate network congestion
    function simulateNetworkCongestion(uint256 _gasPrice) public {
        // Set the basefee for the next block
        vm.fee(_gasPrice);
    }
}