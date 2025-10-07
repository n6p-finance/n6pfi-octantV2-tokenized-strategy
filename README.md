# Strategy Templates for Octant

This repository provides templates for creating strategies compatible with Octant's ecosystem using [Foundry](https://book.getfoundry.sh/). It supports both **YieldDonating** and **YieldSkimming** strategy patterns adapted for Octant's public goods funding model.

## Strategy Types

### YieldDonating Strategies (`src/strategies/yieldDonating/`)
- **Purpose**: Donate yield generated from productive assets to public goods funding
- **Profit Distribution**: Profits are minted as shares to a designated `dragonRouter` address instead of charging performance fees
- **Loss Protection**: When enabled, the strategy can burn shares from the dragonRouter to cover losses and protect users
- **Use Case**: Traditional yield strategies (Aave, Compound, Yearn vaults) that donate their yield to Octant

### YieldSkimming Strategies (`src/strategies/yieldSkimming/`)

- **Purpose**: Capture yield from appreciating assets through exchange rate tracking and donate the profits to public goods funding
- **Profit Distribution**: Profits are minted as shares to a designated `dragonRouter` address instead of charging performance fees
- **Loss Protection**: When enabled, the strategy can burn shares from the dragonRouter to cover losses and protect users
- **Yield Mechanism**: Works with yield-bearing assets (wstETH, rETH) that appreciate in value over time
- **Exchange Rate Tracking**: Monitors exchange rate changes to detect and capture yield appreciation
- **Use Case**: Liquid staking tokens, rebasing tokens, or any asset where yield comes from price appreciation rather than separate rewards

## Key Differences from Standard Yearn Strategies

This repository is adapted from Yearn V3 tokenized strategies for Octant's ecosystem:

- ❌ **No Performance Fees**: Strategies don't charge performance fees to users
- ✅ **Profit Donation**: All profits are donated to Octant's dragonRouter for public goods funding
- ✅ **Loss Protection**: Optional burning of dragon shares to protect users from losses
- ✅ **Two Strategy Patterns**: Support for both traditional yield harvesting and yield-bearing asset appreciation

## Repository Structure

```
src/
├── strategies/
│   ├── yieldDonating/
│   │   ├── YieldDonatingStrategy.sol       # Template for yield harvesting strategies
│   │   └── YieldDonatingStrategyFactory.sol
│   └── yieldSkimming/
│       ├── YieldSkimmingStrategy.sol        # Template for yield-bearing asset strategies
│       └── YieldSkimmingStrategyFactory.sol
├── interfaces/
│   └── IStrategyInterface.sol
└── test/
    ├── yieldDonating/                       # Tests for YieldDonating pattern
    │   ├── YieldDonatingSetup.sol           # Base setup for YieldDonating tests
    │   ├── YieldDonatingOperation.t.sol     # Main operation tests
    │   ├── YieldDonatingFunctionSignature.t.sol # Function signature collision tests
    │   └── YieldDonatingShutdown.t.sol      # Shutdown and emergency tests
    ├── yieldSkimming/                       # Tests for YieldSkimming pattern
    │   ├── YieldSkimmingSetup.sol           # Base setup for YieldSkimming tests
    │   ├── YieldSkimmingOperation.t.sol     # Main operation tests
    │   ├── YieldSkimmingFunctionSignature.t.sol # Function signature collision tests
    │   └── YieldSkimmingShutdown.t.sol      # Shutdown and emergency tests
    └── utils/                               # Shared testing utilities
```

## Getting Started

For YieldDonating, strategy types, you need to override three core functions:
- `_deployFunds`: Deploy assets into yield-generating positions
- `_freeFunds`: Withdraw assets from positions  
- `_harvestAndReport`: Harvest rewards and report total assets

For YieldSkimming, strategy types, you need to override two core functions:
- `getCurrentExchangeRate`: Get the current exchange rate of the yield-bearing asset
- `decimalsOfExchangeRate`: Get the decimals of the exchange rate

Optional overrides include `_tend`, `_tendTrigger`, `availableDepositLimit`, `availableWithdrawLimit` and `_emergencyWithdraw`.

## How to start

### Requirements

- First you will need to install [Foundry](https://book.getfoundry.sh/getting-started/installation).
NOTE: If you are on a windows machine it is recommended to use [WSL](https://learn.microsoft.com/en-us/windows/wsl/install)
- Install [Node.js](https://nodejs.org/en/download/package-manager/)

### Clone this repository

```sh
git clone --recursive https://github.com/golemfoundation/octant-v2-tokenized-strategy-foundry-mix

cd octant-v2-tokenized-strategy-foundry-mix

yarn
```

### Set your environment Variables

Use the `.env.example` template to create a `.env` file and store the environment variables. You will need to populate the `RPC_URL` for the desired network(s). RPC url can be obtained from various providers, including [Ankr](https://www.ankr.com/rpc/) (no sign-up required) and [Infura](https://infura.io/).

Use .env file

1. Make a copy of `.env.example`
2. Add the value for `ETH_RPC_URL` and other example vars
     NOTE: If you set up a global environment variable, that will take precedence.

### Build the project

```sh
make build
```

Run tests

```sh
make test
```

## Strategy Implementation Guide

### YieldDonating Pattern

For strategies that harvest external rewards and donate them to public goods funding.

**Example Use Cases:**
- Aave lending strategies
- Compound lending strategies
- Yearn vault strategies
- Any strategy that earns separate reward tokens

**Key Implementation Points:**
```solidity
function _deployFunds(uint256 _amount) internal override {
    // Deploy assets into yield source
    // Example: aavePool.supply(address(asset), _amount, address(this), 0);
}

function _freeFunds(uint256 _amount) internal override {
    // Withdraw assets from yield source
    // Example: aavePool.withdraw(address(asset), _amount, address(this));
}

function _harvestAndReport() internal override returns (uint256 _totalAssets) {
    // 1. Claim rewards from yield source
    // 2. Sell rewards for base asset (optional)
    // 3. Return accurate total assets including loose balance
    // 4. Profits will automatically be minted to dragonRouter
}
```

### YieldSkimming Pattern  

For strategies that work with yield-bearing assets that appreciate over time.

**Example Use Cases:**
- Lido wstETH (wstETH/ETH exchange rate appreciation)
- Rocket Pool rETH (rETH/ETH exchange rate appreciation)  
- ERC4626 vaults that appreciate in value
- Rebasing tokens that increase in value

**Key Implementation Points:**
```solidity
function getCurrentExchangeRate() public view returns (uint256) {
    // Return current exchange rate of your yield-bearing asset
    // Example for wstETH: return IWstETH(address(asset)).stEthPerToken();
    // Example for rETH: return IRocketPool(address(asset)).getExchangeRate();
    // Example for ERC4626: return IERC4626(address(asset)).convertToAssets(1e18);
}

function _deployFunds(uint256 _amount) internal override {
    // Usually no deployment needed for yield-bearing assets
    // Assets appreciate automatically through exchange rate
}

function _harvestAndReport() internal override returns (uint256 _totalAssets) {
    // Track exchange rate changes to detect yield
    // Return current asset balance - appreciation is captured automatically
}
```

## Strategy Pattern Details

### YieldDonating Pattern

Designed for strategies that:
1. Deploy assets into external yield sources (Aave, Compound, etc.)
2. Harvest external rewards or interest
3. Donate all profits by minting shares to dragonRouter
4. Optionally protect against losses by burning dragonRouter shares

**Key Features:**
- No performance fees charged to users
- All yield goes to public goods funding
- Loss protection through dragon share burning
- Compatible with any yield source that provides separate rewards

### YieldSkimming Pattern

Designed for strategies that:
1. Hold yield-bearing assets that appreciate in value
2. Track exchange rate changes to capture yield appreciation
3. Donate appreciation gains by minting shares to dragonRouter
4. Require minimal maintenance (assets appreciate automatically)

**Key Features:**
- Works with liquid staking tokens and appreciating assets
- Exchange rate tracking captures yield without external harvesting
- Ideal for assets like wstETH, rETH, or yield-bearing vaults
- Simplified implementation for self-appreciating assets

## Testing

### YieldDonating Strategy Tests
- **Profit Distribution**: Verify profits are minted to dragonRouter
- **Loss Protection**: Test dragon share burning during losses
- **Harvest Functionality**: Test reward claiming and asset accounting
- **Dragon Router Management**: Test address updates and cooldowns

### YieldSkimming Strategy Tests  
- **Exchange Rate Tracking**: Verify rate changes are detected using `vm.mockCall`
- **Yield Appreciation**: Test profit capture from asset appreciation through mocked exchange rates
- **Asset Limits**: Test deposit/withdrawal limits
- **Basic Functionality**: Test core strategy operations

**Note**: YieldSkimming tests use `vm.mockCall` to simulate exchange rate changes rather than adding tokens, since yield comes from appreciation of the underlying asset value, not additional token rewards.

**YieldSkimming Behavior**: When the exchange rate appreciates (e.g., wstETH becomes worth more ETH), users benefit from the appreciation on their holdings, while the yield portion (the appreciation amount) gets minted as new shares to the donation address. This allows users to participate in the asset's growth while donating the yield to public goods funding.

Run tests:

```sh
# All tests
make test

# YieldDonating tests only
make test-contract contract=YieldDonatingOperation
make test-contract contract=YieldDonatingFunctionSignature
make test-contract contract=YieldDonatingShutdown

# YieldSkimming tests only  
make test-contract contract=YieldSkimmingOperation
make test-contract contract=YieldSkimmingFunctionSignature
make test-contract contract=YieldSkimmingShutdown

# With traces for debugging
make trace
```

## Current Implementation Status


## Dependencies

This repository uses octant-v2-core from GitHub:
```bash
forge install golemfoundation/octant-v2-core
```

The strategies inherit from `BaseStrategy` available in octant-v2-core and use the TokenizedStrategy pattern for vault functionality.

## Choosing the Right Strategy Type

### Use YieldDonating When:
- Your strategy earns separate reward tokens (COMP, AAVE, CRV, etc.)
- You need to harvest and sell rewards
- You're working with lending protocols or farms
- You want traditional yield strategy behavior with donation mechanics

### Use YieldSkimming When:
- Your asset appreciates in value over time (wstETH, rETH)
- Yield comes from exchange rate changes, not separate rewards
- You want minimal maintenance overhead
- You're working with liquid staking tokens or rebasing assets

Both patterns donate all profits to Octant's public goods funding and provide loss protection mechanisms.

## Example Implementations

### YieldDonating: Morpho Compounder Strategy
```solidity
function _deployFunds(uint256 _amount) internal override {
    IERC4626(compounderVault).deposit(_amount, address(this));
}

function _harvestAndReport() internal view override returns (uint256 _totalAssets) {
    // get strategy's balance in the vault
    uint256 shares = IERC4626(compounderVault).balanceOf(address(this));
    uint256 vaultAssets = IERC4626(compounderVault).convertToAssets(shares);

    // include idle funds as per BaseStrategy specification
    uint256 idleAssets = IERC20(asset).balanceOf(address(this));

    _totalAssets = vaultAssets + idleAssets;

    return _totalAssets;
}
```

### YieldSkimming: Lido wstETH Strategy  
```solidity
// Hold wstETH, track stETH/ETH rate appreciation
function getCurrentExchangeRate() public view returns (uint256) {
    return IWstETH(address(asset)).stEthPerToken();
}

function _harvestAndReport() internal override returns (uint256) {
    // No harvesting needed - wstETH appreciates automatically
    return asset.balanceOf(address(this));
}
```

## Contract Verification

Once deployed and verified, strategies will need TokenizedStrategy function verification on Etherscan:

1. Navigate to the contract's /#code page on Etherscan
2. Click "More Options" → "is this a proxy?"
3. Click "Verify" → "Save"

This adds all TokenizedStrategy functions to the contract interface.

## CI/CD

This repo uses GitHub Actions for:
- **Lint**: Code formatting and style checks
- **Test**: Automated test execution
- **Slither**: Static analysis for security issues
- **Coverage**: Test coverage reporting

Add `ETH_RPC_URL` secret to enable test workflows. See [GitHub Actions docs](https://docs.github.com/en/actions/security-guides/encrypted-secrets) for setup.

## Contributing

When implementing strategies:
1. Choose the appropriate pattern (YieldDonating vs YieldSkimming)
2. Implement the required override functions
3. Add comprehensive tests
4. Document exchange rate logic for YieldSkimming strategies
5. Test profit donation and loss protection mechanisms

For questions or support, please open an issue or reach out to the Octant team.