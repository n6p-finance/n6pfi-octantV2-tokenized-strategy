// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {BaseStrategy} from "@octant-core/dragons/vaults/BaseStrategy.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title YieldSkimming Strategy Template (Simplified)
 * @author Octant
 * @notice Simplified template for creating YieldSkimming strategies
 * @dev Since the complex YieldSkimmingTokenizedStrategy is not available in this version
 *      of octant-v2-core, this is a simplified implementation that demonstrates the pattern.
 *
 *      Key concepts for yield-bearing assets:
 *      - Assets like wstETH, rETH appreciate in value over time
 *      - Exchange rate tracking captures this appreciation as yield
 *      - In a full implementation, this would use specialized accounting
 */
contract YieldSkimmingStrategy is BaseStrategy {
    using SafeERC20 for ERC20;

    /// @notice Exchange rate tracking (for demonstration purposes)
    uint256 public lastExchangeRate;

    /**
     * @param _asset Address of the underlying asset (wstETH)
     * @param _name Strategy name
     * @param _management Address with management role
     * @param _keeper Address with keeper role
     * @param _emergencyAdmin Address with emergency admin role
     * @param _donationAddress Address that receives donated/minted yield
     * @param _enableBurning Whether loss-protection burning from donation address is enabled
     * @param _tokenizedStrategyAddress Address of TokenizedStrategy implementation
     */
    constructor(
        address _asset,
        string memory _name,
        address _management,
        address _keeper,
        address _emergencyAdmin,
        address _donationAddress,
        bool _enableBurning,
        address _tokenizedStrategyAddress
    )
        BaseStrategy(
            _asset,
            _name,
            _management,
            _keeper,
            _emergencyAdmin,
            _donationAddress,
            _enableBurning,
            _tokenizedStrategyAddress
        )
    {
        // Initialize the asset
        asset = ERC20(_asset);

        // TokenizedStrategy initialization will be handled separately
        // This is just a template - the actual initialization depends on
        // the specific TokenizedStrategy implementation being used

        // Initialize exchange rate tracking
        lastExchangeRate = getCurrentExchangeRate();
    }

    /*//////////////////////////////////////////////////////////////
                NEEDED TO BE OVERRIDDEN BY STRATEGIST
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev For yield-bearing assets, typically no deployment is needed
     * as the assets themselves appreciate in value.
     * @param _amount The amount of 'asset' that the strategy can attempt
     * to deploy in the yield source.
     */
    function _deployFunds(uint256 _amount) internal override {
        // For yield-bearing assets like wstETH, rETH, no deployment needed
        // They appreciate automatically through exchange rate changes
        // Override this if your yield-bearing asset requires deployment
    }

    /**
     * @dev For yield-bearing assets, funds are typically always liquid.
     * @param _amount The amount of 'asset' to be freed.
     */
    function _freeFunds(uint256 _amount) internal override {
        // For yield-bearing assets, funds are already liquid
        // No action needed as we simply hold the appreciating asset
        // Override this if your yield-bearing asset has lockup periods
    }

    /**
     * @dev Internal function to harvest all rewards, redeploy any idle
     * funds and return an accurate accounting of all funds currently
     * held by the Strategy.
     *
     * For yield-bearing assets, this primarily tracks exchange rate changes
     * to capture yield appreciation as profit.
     *
     * @return _totalAssets A trusted and accurate account for the total
     * amount of 'asset' the strategy currently holds.
     */
    function _harvestAndReport()
        internal
        override
        returns (uint256 _totalAssets)
    {
        // Return the current balance of yield-bearing assets
        _totalAssets = asset.balanceOf(address(this));
    }

    /*//////////////////////////////////////////////////////////////
                    YIELD-BEARING ASSET SPECIFIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Gets the current exchange rate from the yield-bearing asset
     * @return The current exchange rate (how much underlying asset 1 share is worth)
     * @dev MUST be implemented to return the current exchange rate of your yield-bearing asset
     *      This is a placeholder implementation that returns 1:1 for testing
     */
    function getCurrentExchangeRate() public view virtual returns (uint256) {
        // TODO: Implement exchange rate logic for your specific yield-bearing asset
        //
        // Examples:
        // For wstETH (Lido):
        // return IWstETH(address(asset)).stEthPerToken();
        //
        // For rETH (Rocket Pool):
        // return IRocketPool(address(asset)).getExchangeRate();
        //
        // For ERC4626 vaults:
        // return IERC4626(address(asset)).convertToAssets(1e18);
        //
        // For testing with constant rate:
        return 1e18; // 1:1 ratio - replace with actual implementation
    }

    /**
     * @notice Returns the decimals of the exchange rate
     * @return The decimals of the exchange rate (usually 18 for most assets)
     */
    function decimalsOfExchangeRate() public pure virtual returns (uint256) {
        return 18; // Most assets use 18 decimals, adjust if needed
    }

    /*//////////////////////////////////////////////////////////////
                    OPTIONAL TO OVERRIDE BY STRATEGIST
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Gets the max amount of `asset` that can be withdrawn.
     * @dev Can be overridden to implement withdrawal limits
     * @param _owner The address that is withdrawing from the strategy
     * @return . The available amount that can be withdrawn
     */
    function availableWithdrawLimit(
        address _owner
    ) public view virtual override returns (uint256) {
        // Override to implement withdrawal limits based on liquidity
        return asset.balanceOf(address(this));
    }

    /**
     * @notice Gets the max amount of `asset` that can be deposited.
     * @dev Can be overridden to implement deposit limits
     * @param _owner The address that is depositing into the strategy
     * @return . The available amount that can be deposited
     */
    function availableDepositLimit(
        address _owner
    ) public view virtual override returns (uint256) {
        // Override to implement deposit limits if needed
        return type(uint256).max;
    }

    /**
     * @dev Optional function for strategist to override that can
     *  be called in between reports.
     *
     * For yield-bearing assets, this might be used to update
     * exchange rate tracking or perform maintenance tasks.
     *
     * @param _totalIdle The current amount of idle funds
     */
    function _tend(uint256 _totalIdle) internal virtual override {
        // Can be used to update exchange rate tracking
        // or other maintenance tasks
    }

    /**
     * @dev Optional trigger to override if tend() will be used by the strategy.
     * @return . Should return true if tend() should be called by keeper or false if not.
     */
    function _tendTrigger() internal view virtual override returns (bool) {
        // Could trigger based on time since last update
        // or significant exchange rate changes
        return false;
    }

    /**
     * @dev Optional function for a strategist to override that will
     * allow management to manually withdraw deployed funds from the
     * yield source if a strategy is shutdown.
     *
     * For yield-bearing assets, this typically just ensures all
     * funds are liquid (which they usually already are).
     *
     * @param _amount The amount of asset to attempt to free.
     */
    function _emergencyWithdraw(uint256 _amount) internal virtual override {
        // For most yield-bearing assets, no action needed
        // as funds are already liquid
    }
}
