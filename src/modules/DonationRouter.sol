// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

/// @title DonationRouter
/// @notice Splits and routes donations (ERC20 tokens) to multiple recipients with governance-controlled weights.
/// Intended for use by strategy contracts which call `distribute(...)` after harvesting/reward events.
///
/// Security notes:
///  - `distribute(...)` is callable only by addresses with STRATEGY_ROLE. Strategy contracts must `approve` this router
///    to pull the donated token (or call `donateFromStrategy` where strategy pushes tokens).
///  - Governance (GOVERNOR_ROLE) controls recipients + weights; weights must sum to 10000 (=100%).
///  - Timelock + Governor pattern recommended: grant GOV role to timelock, not EOA.

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract DonationRouter is AccessControl {
    using SafeERC20 for IERC20;

    /// Roles
    bytes32 public constant GOVERNOR_ROLE = keccak256("GOVERNOR_ROLE");
    bytes32 public constant STRATEGY_ROLE = keccak256("STRATEGY_ROLE");

    /// Constants
    uint256 public constant BPS_DENOM = 10000;

    /// Recipient data
    address[] public recipients;
    mapping(address => uint256) public recipientWeightBps; // weight in bps (0..10000)

    /// Totals
    uint256 public totalDonated; // total tokens routed via this router (token-agnostic counter)
    address public immutable defaultRecipient; // fallback if recipients list is empty

    /// Events
    event RecipientAdded(address indexed recipient, uint256 weightBps);
    event RecipientRemoved(address indexed recipient);
    event RecipientUpdated(address indexed recipient, uint256 newWeightBps);
    event RecipientsSet(address[] recipients, uint256[] weights);
    event DonationDistributed(address indexed token, uint256 amount, address[] recipients, uint256[] amounts);
    event StrategyRoleGranted(address indexed strategy);
    event StrategyRoleRevoked(address indexed strategy);

    /// Errors
    error InvalidRecipientWeights();
    error ZeroAmount();
    error NotEnoughAllowanceOrBalance();

    /// @param _defaultRecipient fallback address for donations if recipients list empty
    /// @param governor initial governor address (e.g., Timelock or Governor contract)
    constructor(address _defaultRecipient, address governor) {
        require(_defaultRecipient != address(0), "DonationRouter: zero default recipient");
        require(governor != address(0), "DonationRouter: zero governor");

        defaultRecipient = _defaultRecipient;

        // Setup roles
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender); // deployer can manage roles initially
        _setupRole(GOVERNOR_ROLE, governor);
        _setRoleAdmin(STRATEGY_ROLE, GOVERNOR_ROLE); // governor manages which strategies are allowed
    }

    // -----------------------------
    // Governance / Admin functions
    // -----------------------------

    /// @notice Set the full recipient list and weights. Sum(weights) must equal BPS_DENOM.
    /// @dev Callable by GOVERNOR_ROLE. Replaces previous lists.
    function setRecipients(address[] calldata _recipients, uint256[] calldata _weightsBps) external onlyRole(GOVERNOR_ROLE) {
        require(_recipients.length == _weightsBps.length, "DonationRouter: len mismatch");
        uint256 n = _recipients.length;
        uint256 total = 0;
        for (uint256 i = 0; i < n; i++) {
            require(_recipients[i] != address(0), "DonationRouter: zero recipient");
            require(_weightsBps[i] <= BPS_DENOM, "DonationRouter: weight > bps");
            total += _weightsBps[i];
        }
        if (n > 0) require(total == BPS_DENOM, "DonationRouter: weights must sum to 10000");

        // Clear old mapping
        for (uint256 i = 0; i < recipients.length; i++) {
            delete recipientWeightBps[recipients[i]];
        }

        // Set new list
        recipients = _recipients;
        for (uint256 i = 0; i < n; i++) {
            recipientWeightBps[_recipients[i]] = _weightsBps[i];
        }

        emit RecipientsSet(_recipients, _weightsBps);
    }

    /// @notice Add or update a single recipient weight. If not previously present, appends to recipients array.
    /// @dev Admin must ensure total weights remain consistent (use setRecipients for atomic set).
    function upsertRecipient(address _recipient, uint256 _weightBps) external onlyRole(GOVERNOR_ROLE) {
        require(_recipient != address(0), "DonationRouter: zero recipient");
        require(_weightBps <= BPS_DENOM, "DonationRouter: weight > bps");

        if (recipientWeightBps[_recipient] == 0) {
            recipients.push(_recipient);
            recipientWeightBps[_recipient] = _weightBps;
            emit RecipientAdded(_recipient, _weightBps);
        } else {
            recipientWeightBps[_recipient] = _weightBps;
            emit RecipientUpdated(_recipient, _weightBps);
        }
    }

    /// @notice Remove a recipient. Leaves array entry removed by swapping-with-last for gas efficiency.
    function removeRecipient(address _recipient) external onlyRole(GOVERNOR_ROLE) {
        if (recipientWeightBps[_recipient] == 0) revert InvalidRecipientWeights();

        // Remove mapping + array entry
        delete recipientWeightBps[_recipient];

        uint256 len = recipients.length;
        for (uint256 i = 0; i < len; i++) {
            if (recipients[i] == _recipient) {
                // swap-with-last and pop
                if (i != len - 1) {
                    recipients[i] = recipients[len - 1];
                }
                recipients.pop();
                emit RecipientRemoved(_recipient);
                return;
            }
        }
    }

    /// @notice Grant strategy role to contract allowed to call distribute (governor-controlled).
    function grantStrategyRole(address _strategy) external onlyRole(GOVERNOR_ROLE) {
        grantRole(STRATEGY_ROLE, _strategy);
        emit StrategyRoleGranted(_strategy);
    }

    /// @notice Revoke strategy role.
    function revokeStrategyRole(address _strategy) external onlyRole(GOVERNOR_ROLE) {
        revokeRole(STRATEGY_ROLE, _strategy);
        emit StrategyRoleRevoked(_strategy);
    }

    // -----------------------------
    // Donation distribution
    // -----------------------------

    /// @notice Distribute `amount` of `token` across recipients according to configured weights.
    /// @dev Callable only by STRATEGY_ROLE. The router will *pull* tokens from caller using `transferFrom`,
    /// so the caller (strategy) must approve this router for `amount`. Alternatively, strategy can call
    /// `donatePushed(...)` (see below) to push tokens directly.
    function distribute(IERC20 token, uint256 amount) external onlyRole(STRATEGY_ROLE) {
        if (amount == 0) revert ZeroAmount();

        // Pull tokens from caller
        uint256 pre = token.balanceOf(address(this));
        token.safeTransferFrom(msg.sender, address(this), amount);
        uint256 post = token.balanceOf(address(this));
        uint256 pulled = post - pre;
        if (pulled != amount) {
            // defensive: allow but set amount to actual pulled
            amount = pulled;
        }

        _distributeInternal(token, amount);
    }

    /// @notice Alternative: strategy pushes tokens directly to router and calls this to perform split.
    function distributePushed(IERC20 token) external onlyRole(STRATEGY_ROLE) {
        uint256 amount = token.balanceOf(address(this));
        if (amount == 0) revert ZeroAmount();
        _distributeInternal(token, amount);
    }

    /// @notice Internal distribution logic
    function _distributeInternal(IERC20 token, uint256 amount) internal {
        uint256 n = recipients.length;
        if (n == 0) {
            // fallback: send all to defaultRecipient
            token.safeTransfer(defaultRecipient, amount);
            totalDonated += amount;
            address;
            single[0] = defaultRecipient;
            uint256;
            amt[0] = amount;
            emit DonationDistributed(address(token), amount, single, amt);
            return;
        }

        // Compose recipients and amounts arrays for event
        address[] memory recs = new address[](n);
        uint256[] memory amounts = new uint256[](n);

        uint256 remaining = amount;
        for (uint256 i = 0; i < n; i++) {
            address r = recipients[i];
            uint256 w = recipientWeightBps[r];
            // Calculate share (floor), last recipient gets remainder
            uint256 share = (i == n - 1) ? remaining : (amount * w) / BPS_DENOM;
            if (share > 0) {
                token.safeTransfer(r, share);
                remaining -= share;
            }
            recs[i] = r;
            amounts[i] = share;
        }

        // Bookkeeping
        totalDonated += amount;

        emit DonationDistributed(address(token), amount, recs, amounts);
    }

    // -----------------------------
    // Views / helpers
    // -----------------------------

    /// @notice Return recipients list
    function getRecipients() external view returns (address[] memory) {
        return recipients;
    }

    /// @notice Return weights for a list of recipients
    function getWeights(address[] calldata _recipients) external view returns (uint256[] memory) {
        uint256[] memory w = new uint256[](_recipients.length);
        for (uint256 i = 0; i < _recipients.length; i++) {
            w[i] = recipientWeightBps[_recipients[i]];
        }
        return w;
    }
}
