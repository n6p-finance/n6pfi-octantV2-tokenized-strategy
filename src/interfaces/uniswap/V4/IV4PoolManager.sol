// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// Uniswap V4 Core Imports
import {BaseHook} from "@uniswap/v4-periphery/src/BaseHook.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";

/**
 * @title IV4PoolManager
 * @notice Extended interface for V4 Pool Manager
 */
interface IV4PoolManager is IPoolManager {
    function getPool(PoolKey calldata key) external view returns (address pool);
    function getLiquidity(PoolKey calldata key) external view returns (uint128 liquidity);
    function getFee(PoolKey calldata key) external view returns (uint24 fee);
}