// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

/// @title ImpactOracle (static registry)
/// @notice Simple on-chain registry for token impact scores (0..10000).
/// Designed to be updated by governance (Timelock + Governor). Consumers (strategies, routers)
/// read scores to apply discounts, boosts, or to prefer high-impact tokens.
///
/// Governance should set the Timelock/DAO as GOVERNOR_ROLE in constructor post-deploy.

import "@openzeppelin/contracts/access/AccessControl.sol";

contract ImpactOracle is AccessControl {
    bytes32 public constant GOVERNOR_ROLE = keccak256("GOVERNOR_ROLE");

    /// Score scale: 0 .. 10000 (10000 == 100.00%)
    uint256 public constant MAX_SCORE = 10000;

    mapping(address => uint256) private _scores;
    address[] private _tokens; // list of registered tokens
    mapping(address => bool) private _isRegistered;

    event TokenRegistered(address indexed token, uint256 score);
    event TokenUpdated(address indexed token, uint256 oldScore, uint256 newScore);
    event TokenRemoved(address indexed token);

    constructor(address governor) {
        require(governor != address(0), "ImpactOracle: zero governor");
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(GOVERNOR_ROLE, governor);
    }

    /// @notice Register or update an impact score for a token. 0..MAX_SCORE.
    function setTokenScore(address token, uint256 score) external onlyRole(GOVERNOR_ROLE) {
        require(token != address(0), "ImpactOracle: zero token");
        require(score <= MAX_SCORE, "ImpactOracle: score > max");

        if (_isRegistered[token]) {
            uint256 old = _scores[token];
            _scores[token] = score;
            emit TokenUpdated(token, old, score);
        } else {
            _isRegistered[token] = true;
            _tokens.push(token);
            _scores[token] = score;
            emit TokenRegistered(token, score);
        }
    }

    /// @notice Remove a token from registry (governance)
    function removeToken(address token) external onlyRole(GOVERNOR_ROLE) {
        require(_isRegistered[token], "ImpactOracle: not registered");
        _isRegistered[token] = false;
        delete _scores[token];

        // remove from _tokens array (swap & pop)
        uint256 len = _tokens.length;
        for (uint256 i = 0; i < len; i++) {
            if (_tokens[i] == token) {
                if (i != len - 1) _tokens[i] = _tokens[len - 1];
                _tokens.pop();
                break;
            }
        }

        emit TokenRemoved(token);
    }

    /// @notice Read score for a token (0 if not registered)
    function getScore(address token) external view returns (uint256) {
        return _scores[token];
    }

    /// @notice Return list of registered tokens
    function getRegisteredTokens() external view returns (address[] memory) {
        return _tokens;
    }

    /// @notice Helper: return the best token by score among registered tokens that also pass an external `isSafe` check.
    /// Consumers supply an offchain or onchain safety predicate via callback-like interface (not possible in solidity),
    /// so this helper assumes caller will filter tokens after reading results.
    function getTopToken() external view returns (address best, uint256 bestScore) {
        uint256 len = _tokens.length;
        bestScore = 0;
        best = address(0);
        for (uint256 i = 0; i < len; i++) {
            address t = _tokens[i];
            uint256 s = _scores[t];
            if (s > bestScore) {
                bestScore = s;
                best = t;
            }
        }
    }
}
