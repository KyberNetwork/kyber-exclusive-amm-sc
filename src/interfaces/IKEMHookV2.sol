// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IKEMHookV2Admin} from './IKEMHookV2Admin.sol';
import {IKEMHookV2Errors} from './IKEMHookV2Errors.sol';
import {IKEMHookV2Events} from './IKEMHookV2Events.sol';
import {IKEMHookV2State} from './IKEMHookV2State.sol';


/**
 * @title IKEMHookV2
 * @notice Common interface for the KEMHookV2 contracts
 */
interface IKEMHookV2 is IKEMHookV2Admin, IKEMHookV2Errors, IKEMHookV2Events, IKEMHookV2State {}
