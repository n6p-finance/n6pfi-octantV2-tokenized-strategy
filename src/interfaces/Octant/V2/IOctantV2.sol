// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IOctantV2
 * @notice Minimal interface for Octant V2 integration based on existing usage
 * @dev Simplified to match exactly what's used in AaveALender.sol
 */
interface IOctantV2 {
    // ===========================================
    // BASIC DONATION FUNCTION
    // ===========================================
    
    /**
     * @notice Donate assets to Octant V2 protocol
     * @dev Based on actual usage in AaveALender._executeOctantDonation
     * @param amount Amount of tokens to donate
     */
    function donate(uint256 amount) external;
    
    /**
     * @notice Donate to a specific project in Octant V2
     * @param project Address of the project to donate to
     * @param amount Amount of tokens to donate
     */
    function donateToProject(address project, uint256 amount) external;
    
    // ===========================================
    // GLOW TOKEN MANAGEMENT
    // ===========================================
    
    /**
     * @notice Get GLOW token address
     * @return glowToken Address of GLOW token
     */
    function glow() external view returns (address glowToken);
    
    function estimateGlowRewards(uint256 _amount) external view returns (uint256 estimatedRewards);

    /**
     * @notice Get earned GLOW rewards for an address
     * @param account Address to check rewards for
     * @return glowRewards Amount of GLOW rewards earned
     */
    function getGlowRewards(address account) external view returns (uint256 glowRewards);
    
    /**
     * @notice Claim GLOW rewards
     * @return claimedAmount Amount of GLOW claimed
     */
    function claimGlowRewards() external returns (uint256 claimedAmount);
    
    // ===========================================
    // ROUND & PROJECT MANAGEMENT
    // ===========================================
    
    /**
     * @notice Get current active round
     * @return roundId Current round identifier
     */
    function getCurrentRound() external view returns (uint256 roundId);
    
    /**
     * @notice Get round information
     * @param roundId Round identifier
     * @return startTime Round start time
     * @return endTime Round end time
     * @return totalDonations Total donations in round
     * @return isActive Whether round is active
     */
    function getRound(uint256 roundId) external view returns (
        uint256 startTime,
        uint256 endTime,
        uint256 totalDonations,
        bool isActive
    );
    
    /**
     * @notice Get project information
     * @param project Address of the project
     * @return totalDonations Total donations to project
     * @return isActive Whether project is active
     */
    function getProject(address project) external view returns (
        uint256 totalDonations,
        bool isActive
    );
    
    /**
     * @notice Get all active projects
     * @return activeProjects Array of active project addresses
     */
    function getActiveProjects() external view returns (address[] memory activeProjects);
    
    // ===========================================
    // VOTING & GOVERNANCE
    // ===========================================
    
    /**
     * @notice Vote on projects in a round
     * @param roundId The round identifier
     * @param projects Array of project addresses to vote for
     * @param votes Array of vote weights
     */
    function voteOnProjects(
        uint256 roundId,
        address[] calldata projects,
        uint256[] calldata votes
    ) external;
    
    /**
     * @notice Get voting power for an address
     * @param voter Address of the voter
     * @return votingPower Available voting power
     */
    function getVotingPower(address voter) external view returns (uint256 votingPower);
    
    /**
     * @notice Get total votes cast by an address in a round
     * @param voter Address of the voter
     * @param roundId Round identifier
     * @return totalVotes Total votes cast
     */
    function getVotes(address voter, uint256 roundId) external view returns (uint256 totalVotes);
    
    // ===========================================
    // DONATION TRACKING
    // ===========================================
    
    /**
     * @notice Get total donations by an address
     * @param donor Address of the donor
     * @return totalDonated Total amount donated
     */
    function getTotalDonations(address donor) external view returns (uint256 totalDonated);
    
    /**
     * @notice Get donations by an address to a specific project
     * @param donor Address of the donor
     * @param project Address of the project
     * @return donationAmount Total donated to the project
     */
    function getProjectDonations(address donor, address project) external view returns (uint256 donationAmount);
    
    // ===========================================
    // EVENTS (Based on Octant V2 core)
    // ===========================================
    
    event DonationReceived(
        address indexed donor,
        address indexed project,
        uint256 amount,
        uint256 glowRewards,
        uint256 roundId
    );
    
    event VotesCast(
        address indexed voter,
        uint256 indexed roundId,
        address[] projects,
        uint256[] votes
    );
    
    event GlowRewardsClaimed(
        address indexed claimer,
        uint256 amount
    );
    
    event RoundStarted(
        uint256 indexed roundId,
        uint256 startTime,
        uint256 endTime
    );
    
    event RoundFinalized(
        uint256 indexed roundId,
        uint256 totalDonations,
        uint256 glowDistributed
    );
}