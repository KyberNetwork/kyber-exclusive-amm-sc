// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IFFHookAdmin} from './modules/IFFHookAdmin.sol';
import {IFFHookAfterSwap} from './modules/IFFHookAfterSwap.sol';
import {IFFHookBeforeSwap} from './modules/IFFHookBeforeSwap.sol';
import {IFFHookNonces} from './modules/IFFHookNonces.sol';
import {IFFHookStateView} from './modules/IFFHookStateView.sol';

interface IFFHook is
  IFFHookAdmin,
  IFFHookStateView,
  IFFHookBeforeSwap,
  IFFHookAfterSwap,
  IFFHookNonces
{}
