// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;
/**
 * @title IAuction
 * @notice Interface for Auction contracts
 * This interface defines the functions that an Auction contract must implement.
 * Auction contracts are responsible for managing auctions, including checking
 * if an auction is kickable, calculating the amount needed for a take, enabling
 * new auctions, and handling the kick and take actions.
 * Auction is a process that allows users to bid on assets, typically in a decentralized finance (DeFi) context in liquidation engine.
 */
interface IAuction {
    function kickable(bytes32 _auctionId) external view returns (uint256);

    function getAmountNeeded(
        bytes32 _auctionId,
        uint256 _amountToTake
    ) external view returns (uint256);

    function enable(
        address _from,
        address _receiver
    ) external returns (bytes32 _auctionId);

    function setHookFlags(
        bool _kickable,
        bool _kick,
        bool _preTake,
        bool _postTake
    ) external;

    function kick(bytes32 _auctionId) external returns (uint256 available);

    function take(bytes32 _auctionId) external returns (uint256);
}