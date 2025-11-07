// In your AaveV4PublicGoodsStrategyEnhanced:

function _executeOctantDonation(uint256 _amount) internal {
    totalDonated += _amount;
    lastDonationTimestamp = block.timestamp;
    
    // Transfer to Octant V2 and earn Glow rewards
    asset.safeApprove(address(OCTANT_V2), _amount);
    uint256 glowEarned = OCTANT_V2.donateToProject(GLOW_DISTRIBUTION_POOL, _amount);
    
    // Track earned Glow for future governance participation
    _updateGlowRewards(glowEarned);
    
    emit DonationToOctant(_amount, block.timestamp, impactScore);
}

function participateInGovernance(
    address[] calldata projects, 
    uint256[] calldata votes
) external onlyManagement {
    // Use earned Glow for governance participation
    OCTANT_V2.voteOnProjects(
        OCTANT_V2.getCurrentRound(),
        projects,
        votes
    );
}