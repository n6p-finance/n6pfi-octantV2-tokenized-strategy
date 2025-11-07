// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.24;

import "forge-std/console2.sol";
import {Test} from "forge-std/Test.sol";

import {YieldDonatingStrategyFactory as StrategyFactory, ERC20} from "../../strategies/YieldDonatingStrategyFactory.sol";
import {AaveALender as StrategyAave1, ERC20} from "../../strategies/aave/AaveALender.sol"; // The strategy we are testing 1
import {AaveV4Leveraged as StrategyAave2, ERC20} from "../../strategies/aave/AaveV4Leveraged.sol"; // The strategy we are testing 2
import {AaveAdapterV4Enhanced} from "../../adapter/AaveAdapterV4Enhanced.sol";
import {IStrategyInterface} from "../../interfaces/IStrategyInterface.sol";
import {ITokenizedStrategy} from "../../../lib/octant-v2-core/src/core/interfaces/ITokenizedStrategy.sol";

// Core
import {Hooks} from "../../../lib/v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "../../../lib/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "../../../lib/v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "../../../lib/v4-core/src/types/BalanceDelta.sol";
import {Currency, CurrencyLibrary} from "../../../lib/v4-core/src/types/Currency.sol";
import {PoolId, PoolIdLibrary} from "../../../lib/v4-core/src/types/PoolId.sol";

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
        console2.log("Starting AaveV4PublicGoodsStrategySetup...");
        
        // Read asset address from environment
        address testAssetAddress = vm.envAddress("TEST_ASSET_ADDRESS");
        require(testAssetAddress != address(0), "TEST_ASSET_ADDRESS not set in .env");
        console2.log("Test Asset Address:", testAssetAddress);

        // Set asset
        asset = ERC20(testAssetAddress);

        // Set decimals
        decimals = asset.decimals();
        console2.log("Asset decimals:", decimals);

        // Set max fuzz amount to 1,000,000 of the asset
        maxFuzzAmount = 1_000_000 * 10 ** decimals;
        console2.log("Max fuzz amount:", maxFuzzAmount);

        // Read yield source from environment
        yieldSource = vm.envAddress("TEST_YIELD_SOURCE");
        require(yieldSource != address(0), "TEST_YIELD_SOURCE not set in .env");
        console2.log("Yield Source:", yieldSource);

        // Deploy mock Aave Adapter
        console2.log("Deploying AaveAdapterV4Enhanced...");
        aaveAdapter = new AaveAdapterV4Enhanced(
            aaveLendingPool,
            aaveRewardsController,
            IPoolManager(uniswapV4PoolManager),
            glowDistributionPool
        );
        console2.log("AaveAdapterV4Enhanced deployed at:", address(aaveAdapter));

        // Deploy mock Pool Manager
        poolManager = IPoolManager(uniswapV4PoolManager);
        console2.log("Pool Manager set to:", uniswapV4PoolManager);

        // Initialize sample V4 pool key for testing
        _initializeSamplePoolKey();

        // Deploy strategy and set variables
        console2.log("Deploying strategy...");
        strategy = IStrategyInterface(setUpStrategy());
        console2.log("Strategy deployed at:", address(strategy));

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
        
        console2.log("Setup completed successfully");
    }

    function _initializeSamplePoolKey() internal {
        console2.log("Initializing sample pool key...");
        samplePoolKey = PoolKey({
            currency0: Currency.wrap(address(asset)),
            currency1: Currency.wrap(address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2)), // WETH
            fee: 3000, // 0.3%
            tickSpacing: 60,
            hooks: v4Hook
        });
        console2.log("Sample pool key initialized with fee:", samplePoolKey.fee);
    }

    function setUpStrategy() public returns (address) {
        console2.log("Setting up strategy deployment...");
        
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
        console2.log("Strategy deployed at:", address(_strategy));

        // Set up V4 specific configurations after deployment
        console2.log("Setting up V4 strategy configuration...");
        _setupV4StrategyConfig(_strategy);

        return address(_strategy);
    }

    function _setupV4StrategyConfig(IStrategyInterface _strategy) internal {
        console2.log("Configuring V4 innovation settings...");
        
        // Set V4 innovation configurations
        vm.prank(management);
        _strategy.setV4InnovationConfig(
            true,  // donationVerifiedSwaps
            true,  // adaptiveFeeOptimization  
            true,  // impactTokenPriority
            true,  // microDonationAutomation
            microDonationBps
        );
        console2.log("V4 innovation config set with microDonationBps:", microDonationBps);

        // Set up donation recipients
        address[] memory recipients = new address[](3);
        recipients[0] = dragonRouter;
        recipients[1] = glowDistributionPool;
        recipients[2] = octantV2;

        uint256[] memory weights = new uint256[](3);
        weights[0] = 4000; // 40%
        weights[1] = 4000; // 40%
        weights[2] = 2000; // 20%

        console2.log("Setting up donation recipients...");
        vm.prank(management);
        _strategy.updateDonationRecipients(recipients, weights);
        console2.log("Donation recipients configured with weights:", weights[0], weights[1], weights[2]);

        // Register impact tokens
        console2.log("Registering impact token:", address(asset));
        vm.prank(management);
        _strategy.registerImpactToken(address(asset), 7500); // 75% impact score
        console2.log("Impact token registered with score: 7500");

        // Set up MEV protection
        console2.log("Configuring MEV protection...");
        vm.prank(management);
        _strategy.setMEVProtectionConfig(
            mevProtectionEnabled,
            50, // 0.5% max slippage
            minFuzzAmount,
            maxFuzzAmount / 10,
            mevTimeLockWindow
        );
        console2.log("MEV protection configured with timelock window:", mevTimeLockWindow);

        // Set up liquidity mining
        console2.log("Configuring liquidity mining...");
        vm.prank(management);
        _strategy.setLiquidityMiningConfig(
            autoCompoundFees,
            minMicroDonation * 10, // 0.01 ETH threshold
            feeReinvestmentBps
        );
        console2.log("Liquidity mining configured with fee reinvestment:", feeReinvestmentBps, "bps");
        
        console2.log("V4 strategy configuration completed");
    }

    function depositIntoStrategy(IStrategyInterface _strategy, address _user, uint256 _amount) public {
        console2.log("Depositing into strategy - User:", _user, "Amount:", _amount);
        
        vm.prank(_user);
        asset.approve(address(_strategy), _amount);

        uint256 balanceBefore = asset.balanceOf(_user);
        uint256 strategyBalanceBefore = asset.balanceOf(address(_strategy));
        
        vm.prank(_user);
        _strategy.deposit(_amount, _user);
        
        uint256 balanceAfter = asset.balanceOf(_user);
        uint256 strategyBalanceAfter = asset.balanceOf(address(_strategy));
        
        console2.log("Deposit completed - User balance change:", balanceBefore - balanceAfter);
        console2.log("Strategy balance change:", strategyBalanceAfter - strategyBalanceBefore);
    }

    function mintAndDepositIntoStrategy(IStrategyInterface _strategy, address _user, uint256 _amount) public {
        console2.log("Minting and depositing - User:", _user, "Amount:", _amount);
        
        uint256 userBalanceBefore = asset.balanceOf(_user);
        airdrop(asset, _user, _amount);
        uint256 userBalanceAfter = asset.balanceOf(_user);
        
        console2.log("Airdrop completed - User balance increased by:", userBalanceAfter - userBalanceBefore);
        
        depositIntoStrategy(_strategy, _user, _amount);
    }

    // Enhanced test function for V4 features
    function executeV4DonationVerifiedSwap(
        IStrategyInterface _strategy,
        address _user,
        uint256 _amount,
        uint256 _donationAmount
    ) public returns (uint256) {
        console2.log("Executing V4 donation verified swap - User:", _user, "Amount:", _amount, "Donation:", _donationAmount);
        
        vm.prank(_user);
        asset.approve(address(_strategy), _amount + _donationAmount);

        uint256 userBalanceBefore = asset.balanceOf(_user);
        
        // This would call the actual donation verified swap function
        // For testing, we'll simulate the behavior
        vm.prank(_user);
        uint256 result = _strategy.executeDonationVerifiedSwap(
            address(asset),
            address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2), // WETH
            _amount,
            _amount * 9950 / 10000, // 0.5% slippage
            _donationAmount
        );
        
        console2.log("V4 donation verified swap completed - Result:", result);
        console2.log("User balance change:", userBalanceBefore - asset.balanceOf(_user));
        
        return result;
    }

    function registerGovernanceParticipation(
        IStrategyInterface _strategy,
        address _user,
        uint256 _voteCount,
        uint256 _donationAmount
    ) public {
        console2.log("Registering governance participation - User:", _user, "Votes:", _voteCount, "Donation:", _donationAmount);
        
        uint256 userBalanceBefore = asset.balanceOf(_user);
        
        vm.prank(_user);
        _strategy.registerGovernanceParticipation(_voteCount, _donationAmount);
        
        console2.log("Governance participation registered - User balance change:", userBalanceBefore - asset.balanceOf(_user));
    }

    function triggerV4MicroDonation(IStrategyInterface _strategy, address _user, uint256 _operationAmount) public {
        console2.log("Triggering V4 micro donation - User:", _user, "Operation Amount:", _operationAmount);
        
        // Simulate a V4 operation that triggers micro-donation
        bytes32 operationHash = keccak256(abi.encodePacked(_operationAmount, block.timestamp, _user));
        
        vm.prank(_user);
        _strategy.triggerMicroDonation(_operationAmount, operationHash);
        
        console2.log("V4 micro donation triggered with hash:", vm.toString(operationHash));
    }

    function simulateV4Swap(
        IStrategyInterface _strategy,
        address _user,
        uint256 _amount
    ) public {
        console2.log("Simulating V4 swap - User:", _user, "Amount:", _amount);
        
        vm.prank(_user);
        _strategy.simulateV4Swap(_amount);
        
        console2.log("V4 swap simulation completed");
    }

    function simulateV4LiquidityAdd(
        IStrategyInterface _strategy,
        address _user,
        uint256 _amount
    ) public {
        console2.log("Simulating V4 liquidity add - User:", _user, "Amount:", _amount);
        
        vm.prank(_user);
        _strategy.simulateV4LiquidityAdd(_amount);
        
        console2.log("V4 liquidity add simulation completed");
    }

    // For checking the amounts in the strategy
    function checkStrategyTotals(
        IStrategyInterface _strategy,
        uint256 _totalAssets,
        uint256 _totalDebt,
        uint256 _totalIdle
    ) public {
        console2.log("Checking strategy totals...");
        
        uint256 _assets = _strategy.totalAssets();
        uint256 _balance = ERC20(_strategy.asset()).balanceOf(address(_strategy));
        uint256 _idle = _balance > _assets ? _assets : _balance;
        uint256 _debt = _assets - _idle;
        
        console2.log("Current - Assets:", _assets, "Debt:", _debt, "Idle:", _idle);
        console2.log("Expected - Assets:", _totalAssets, "Debt:", _totalDebt, "Idle:", _totalIdle);
        
        assertEq(_assets, _totalAssets, "!totalAssets");
        assertEq(_debt, _totalDebt, "!totalDebt");
        assertEq(_idle, _totalIdle, "!totalIdle");
        assertEq(_totalAssets, _totalDebt + _totalIdle, "!Added");
        
        console2.log("Strategy totals check passed");
    }

    // Enhanced V4 metrics checking
    function checkV4StrategyMetrics(
        IStrategyInterface _strategy,
        uint256 _expectedFeeSavings,
        uint256 _expectedPublicGoodsDonations,
        uint256 _expectedVerifiedSwaps,
        uint256 _expectedMicroDonations
    ) public {
        console2.log("Checking V4 strategy metrics...");
        
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

        console2.log("Expected Metrics:");
        console2.log("Fee Savings:", _expectedFeeSavings);
        console2.log("Public Goods Donations:", _expectedPublicGoodsDonations);
        console2.log("Verified Swaps:", _expectedVerifiedSwaps);
        console2.log("Micro Donations:", _expectedMicroDonations);

        assertGe(totalFeeSavings, _expectedFeeSavings, "!feeSavings");
        assertGe(publicGoodsDonations, _expectedPublicGoodsDonations, "!publicGoodsDonations");
        assertGe(verifiedSwapsCount, _expectedVerifiedSwaps, "!verifiedSwaps");
        assertGe(microDonationsCount, _expectedMicroDonations, "!microDonations");
        
        console2.log("V4 strategy metrics check passed");
    }

    function checkImpactTokenInfo(
        IStrategyInterface _strategy,
        address _token,
        uint256 _expectedImpactScore,
        uint256 _expectedFeeDiscount
    ) public {
        console2.log("Checking impact token info for:", _token);
        
        (uint256 impactScore,
         uint256 feeDiscount,
         uint256 lastUpdate,
         bool isHighImpact) = _strategy.getImpactTokenInfo(_token);

        console2.log("Impact Token Info for", _token);
        console2.log("Impact Score:", impactScore);
        console2.log("Fee Discount:", feeDiscount);
        console2.log("Last Update:", lastUpdate);
        console2.log("Is High Impact:", isHighImpact);

        console2.log("Expected - Impact Score:", _expectedImpactScore, "Fee Discount:", _expectedFeeDiscount);

        assertEq(impactScore, _expectedImpactScore, "!impactScore");
        assertGe(feeDiscount, _expectedFeeDiscount, "!feeDiscount");
        assertTrue(isHighImpact, "!isHighImpact");
        
        console2.log("Impact token info check passed");
    }

    function airdrop(ERC20 _asset, address _to, uint256 _amount) public {
        console2.log("Airdropping - To:", _to, "Amount:", _amount, "Asset:", address(_asset));
        
        uint256 balanceBefore = _asset.balanceOf(_to);
        deal(address(_asset), _to, balanceBefore + _amount);
        uint256 balanceAfter = _asset.balanceOf(_to);
        
        console2.log("Airdrop completed - Balance increased from", balanceBefore, "to", balanceAfter);
    }

    function setDragonRouter(address _newDragonRouter) public {
        console2.log("Setting dragon router to:", _newDragonRouter);
        
        vm.prank(management);
        ITokenizedStrategy(address(strategy)).setDragonRouter(_newDragonRouter);

        // Fast forward to bypass cooldown
        skip(7 days);
        console2.log("Skipped 7 days cooldown period");

        // Anyone can finalize after cooldown
        ITokenizedStrategy(address(strategy)).finalizeDragonRouterChange();
        
        console2.log("Dragon router change finalized");
    }

    function setV4InnovationConfig(
        bool _donationVerifiedSwaps,
        bool _adaptiveFeeOptimization,
        bool _impactTokenPriority,
        bool _microDonationAutomation,
        uint256 _microDonationBps
    ) public {
        console2.log("Setting V4 innovation config:");
        console2.log("Donation Verified Swaps:", _donationVerifiedSwaps);
        console2.log("Adaptive Fee Optimization:", _adaptiveFeeOptimization);
        console2.log("Impact Token Priority:", _impactTokenPriority);
        console2.log("Micro Donation Automation:", _microDonationAutomation);
        console2.log("Micro Donation BPS:", _microDonationBps);
        
        vm.prank(management);
        strategy.setV4InnovationConfig(
            _donationVerifiedSwaps,
            _adaptiveFeeOptimization,
            _impactTokenPriority,
            _microDonationAutomation,
            _microDonationBps
        );
        
        console2.log("V4 innovation config updated");
    }

    function updateDonationRecipients(
        address[] memory _newRecipients,
        uint256[] memory _newWeights
    ) public {
        console2.log("Updating donation recipients...");
        console2.log("Number of recipients:", _newRecipients.length);
        
        for (uint i = 0; i < _newRecipients.length; i++) {
            console2.log("Recipient", i, ":", _newRecipients[i], "Weight:", _newWeights[i]);
        }
        
        vm.prank(management);
        strategy.updateDonationRecipients(_newRecipients, _newWeights);
        
        console2.log("Donation recipients updated");
    }

    function registerImpactToken(address _token, uint256 _impactScore) public {
        console2.log("Registering impact token:", _token, "with score:", _impactScore);
        
        vm.prank(management);
        strategy.registerImpactToken(_token, _impactScore);
        
        console2.log("Impact token registered");
    }

    function setMEVProtectionConfig(
        bool _enabled,
        uint256 _maxSlippageBps,
        uint256 _minSwapAmount,
        uint256 _maxSwapAmount,
        uint256 _timeLockWindow
    ) public {
        console2.log("Setting MEV protection config:");
        console2.log("Enabled:", _enabled);
        console2.log("Max Slippage BPS:", _maxSlippageBps);
        console2.log("Min Swap Amount:", _minSwapAmount);
        console2.log("Max Swap Amount:", _maxSwapAmount);
        console2.log("Time Lock Window:", _timeLockWindow);
        
        vm.prank(management);
        strategy.setMEVProtectionConfig(
            _enabled,
            _maxSlippageBps,
            _minSwapAmount,
            _maxSwapAmount,
            _timeLockWindow
        );
        
        console2.log("MEV protection config updated");
    }

    function setLiquidityMiningConfig(
        bool _autoCompoundFees,
        uint256 _minFeeClaimThreshold,
        uint256 _feeReinvestmentBps
    ) public {
        console2.log("Setting liquidity mining config:");
        console2.log("Auto Compound Fees:", _autoCompoundFees);
        console2.log("Min Fee Claim Threshold:", _minFeeClaimThreshold);
        console2.log("Fee Reinvestment BPS:", _feeReinvestmentBps);
        
        vm.prank(management);
        strategy.setLiquidityMiningConfig(
            _autoCompoundFees,
            _minFeeClaimThreshold,
            _feeReinvestmentBps
        );
        
        console2.log("Liquidity mining config updated");
    }

    function simulateHarvestWithV4Features() public {
        console2.log("Simulating harvest with V4 features...");
        
        uint256 assetsBefore = strategy.totalAssets();
        
        vm.prank(keeper);
        strategy.harvest();
        
        uint256 assetsAfter = strategy.totalAssets();
        
        console2.log("Harvest completed - Assets before:", assetsBefore, "Assets after:", assetsAfter);
        console2.log("Asset change:", assetsAfter - assetsBefore);
    }

    function getV4NetworkConditions() public view returns (
        uint256 currentVolatility,
        uint256 networkCongestion,
        bool safeToOperate,
        uint256 adaptiveFeeRate
    ) {
        console2.log("Getting V4 network conditions...");
        
        (currentVolatility, networkCongestion, safeToOperate, adaptiveFeeRate) = strategy.getV4NetworkConditions();
        
        console2.log("V4 Network Conditions:");
        console2.log("Volatility:", currentVolatility);
        console2.log("Network Congestion:", networkCongestion);
        console2.log("Safe to Operate:", safeToOperate);
        console2.log("Adaptive Fee Rate:", adaptiveFeeRate);
        
        return (currentVolatility, networkCongestion, safeToOperate, adaptiveFeeRate);
    }

    function getPublicGoodsInfo() public view returns (
        uint256 totalDonated,
        uint256 publicGoodsScore,
        uint256 yieldBoost,
        uint256 pendingRedistribution,
        address[] memory supportedFunds,
        uint256[] memory allocationWeights
    ) {
        console2.log("Getting public goods info...");
        
        (totalDonated, publicGoodsScore, yieldBoost, pendingRedistribution, supportedFunds, allocationWeights) = 
            strategy.getPublicGoodsInfo();
        
        console2.log("Public Goods Info:");
        console2.log("Total Donated:", totalDonated);
        console2.log("Public Goods Score:", publicGoodsScore);
        console2.log("Yield Boost:", yieldBoost);
        console2.log("Pending Redistribution:", pendingRedistribution);
        console2.log("Number of supported funds:", supportedFunds.length);
        
        for (uint i = 0; i < supportedFunds.length; i++) {
            console2.log("Fund", i, ":", supportedFunds[i], "Weight:", allocationWeights[i]);
        }
        
        return (totalDonated, publicGoodsScore, yieldBoost, pendingRedistribution, supportedFunds, allocationWeights);
    }

    function getDonationMetrics(address _fund) public view returns (
        uint256 totalDonated,
        uint256 lastDonationTime,
        uint256 donationCount,
        uint256 avgDonationSize
    ) {
        console2.log("Getting donation metrics for fund:", _fund);
        
        (totalDonated, lastDonationTime, donationCount, avgDonationSize) = strategy.getDonationMetrics(_fund);
        
        console2.log("Donation Metrics for", _fund);
        console2.log("Total Donated:", totalDonated);
        console2.log("Last Donation Time:", lastDonationTime);
        console2.log("Donation Count:", donationCount);
        console2.log("Average Donation Size:", avgDonationSize);
        
        return (totalDonated, lastDonationTime, donationCount, avgDonationSize);
    }

    function getFeeCaptureStats() public view returns (
        uint256 totalTradingFeesPaid,
        uint256 totalFeesRedirected,
        uint256 pendingRedistribution,
        uint256 lastCaptureTime
    ) {
        console2.log("Getting fee capture stats...");
        
        (totalTradingFeesPaid, totalFeesRedirected, pendingRedistribution, lastCaptureTime) = 
            strategy.getFeeCaptureStats();
        
        console2.log("Fee Capture Stats:");
        console2.log("Total Trading Fees Paid:", totalTradingFeesPaid);
        console2.log("Total Fees Redirected:", totalFeesRedirected);
        console2.log("Pending Redistribution:", pendingRedistribution);
        console2.log("Last Capture Time:", lastCaptureTime);
        
        return (totalTradingFeesPaid, totalFeesRedirected, pendingRedistribution, lastCaptureTime);
    }

    // Helper function to simulate time passage for V4 features
    function advanceTimeForV4Features() public {
        console2.log("Advancing time for V4 features by 1 day...");
        uint256 currentTime = block.timestamp;
        
        skip(1 days);
        
        console2.log("Time advanced from", currentTime, "to", block.timestamp);
    }

    // Helper function to simulate market volatility
    function simulateMarketVolatility(uint256 _volatilityLevel) public {
        console2.log("Simulating market volatility with level:", _volatilityLevel);
        
        // This would interact with the strategy's volatility oracle
        // For testing, we can manipulate the strategy's internal state
        // Implementation depends on how volatility is measured
        
        console2.log("Market volatility simulation completed");
    }

    // Helper function to simulate network congestion
    function simulateNetworkCongestion(uint256 _gasPrice) public {
        console2.log("Simulating network congestion with gas price:", _gasPrice);
        
        // Set the basefee for the next block
        vm.fee(_gasPrice);
        
        console2.log("Network congestion simulation completed");
    }
}