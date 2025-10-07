// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {YieldSkimmingStrategy} from "./YieldSkimmingStrategy.sol";
import {IStrategyInterface} from "../../interfaces/IStrategyInterface.sol";
import {TokenizedStrategy} from "@octant-core/dragons/vaults/TokenizedStrategy.sol";

contract YieldSkimmingStrategyFactory {
    event NewStrategy(address indexed strategy, address indexed asset);

    address public immutable emergencyAdmin;
    address public immutable tokenizedStrategyAddress;

    address public management;
    address public donationAddress;
    address public keeper;
    bool public enableBurning = true;

    /// @notice Track the deployments. asset => strategy
    mapping(address => address) public deployments;

    constructor(
        address _management,
        address _donationAddress,
        address _keeper,
        address _emergencyAdmin
    ) {
        management = _management;
        donationAddress = _donationAddress;
        keeper = _keeper;
        emergencyAdmin = _emergencyAdmin;

        // Deploy the standard TokenizedStrategy implementation
        tokenizedStrategyAddress = address(new TokenizedStrategy());
    }

    /**
     * @notice Deploy a new YieldSkimming Strategy.
     * @param _asset The underlying yield-bearing asset for the strategy to use (e.g., wstETH, rETH)
     * @param _name The name for the strategy.
     * @return The address of the new strategy.
     */
    function newStrategy(
        address _asset,
        string calldata _name
    ) external virtual returns (address) {
        // Deploy new YieldSkimming strategy
        IStrategyInterface _newStrategy = IStrategyInterface(
            address(
                new YieldSkimmingStrategy(
                    _asset,
                    _name,
                    management,
                    keeper,
                    emergencyAdmin,
                    donationAddress,
                    enableBurning,
                    tokenizedStrategyAddress
                )
            )
        );

        emit NewStrategy(address(_newStrategy), _asset);

        deployments[_asset] = address(_newStrategy);
        return address(_newStrategy);
    }

    function setAddresses(
        address _management,
        address _donationAddress,
        address _keeper
    ) external {
        require(msg.sender == management, "!management");
        management = _management;
        donationAddress = _donationAddress;
        keeper = _keeper;
    }

    function setEnableBurning(bool _enableBurning) external {
        require(msg.sender == management, "!management");
        enableBurning = _enableBurning;
    }

    function isDeployedStrategy(
        address _strategy
    ) external view returns (bool) {
        address _asset = IStrategyInterface(_strategy).asset();
        return deployments[_asset] == _strategy;
    }
}
