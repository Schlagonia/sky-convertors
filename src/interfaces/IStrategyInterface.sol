// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {IStrategy} from "@tokenized-strategy/interfaces/IStrategy.sol";

interface IStrategyInterface is IStrategy {
    function VAULT() external view returns (address);
    function manualRedeem(uint256 _shares) external returns (uint256);
    function manualPsmSwap(uint256 _gemAmount) external returns (uint256);
}
