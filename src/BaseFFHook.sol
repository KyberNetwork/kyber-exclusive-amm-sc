// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {FFHookAccounting} from './modules/FFHookAccounting.sol';
import {FFHookAdmin} from './modules/FFHookAdmin.sol';
import {FFHookAfterModifyLiquidity} from './modules/FFHookAfterModifyLiquidity.sol';
import {FFHookAfterSwap} from './modules/FFHookAfterSwap.sol';
import {FFHookBeforeSwap} from './modules/FFHookBeforeSwap.sol';
import {FFHookStateView} from './modules/FFHookStateView.sol';

abstract contract BaseFFHook is
  FFHookAdmin,
  FFHookAfterModifyLiquidity,
  FFHookBeforeSwap,
  FFHookAfterSwap
{}
