// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.24;

interface IStrategyFactory {
    function deploySingleStrategy(
        address asset,
        address adapter,
        bytes memory initData
    ) external returns (address vault, address strategy);

    function deployHybridStrategy(
        address asset,
        address[] calldata adapters,
        uint256[] calldata weights,
        bytes[] calldata initDatas
    ) external returns (address vault, address router);

    function deployAdapter(
        AdapterType adapterType,
        bytes memory params
    ) external returns (address);

    function setGlobalPolicy(address policy) external;

    function registry(uint256 id) external view returns (Deployment memory);
}
