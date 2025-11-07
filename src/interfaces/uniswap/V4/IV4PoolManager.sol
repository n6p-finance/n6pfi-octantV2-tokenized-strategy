// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// Periphery (Hooks)
import {BaseHook} from "../../../../lib/v4-periphery/src/utils/BaseHook.sol";

// Uniswap V4 Core Imports
import {Hooks} from "../../../../lib/v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "../../../../lib/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "../../../../lib/v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "../../../../lib/v4-core/src/types/BalanceDelta.sol";
import {Currency, CurrencyLibrary} from "../../../../lib/v4-core/src/types/Currency.sol";

/**
 * @title IV4PoolManager
 * @notice Extended interface for V4 Pool Manager
 */
interface IV4PoolManager is IPoolManager {
    function getPool(PoolKey calldata key) external view returns (address pool);
    function getLiquidity(PoolKey calldata key) external view returns (uint128 liquidity);
    function getFee(PoolKey calldata key) external view returns (uint24 fee);
}