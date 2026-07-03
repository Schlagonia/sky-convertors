// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {USDCToUSDS} from "../USDCToUSDS.sol";
import {IStrategyInterface} from "../interfaces/IStrategyInterface.sol";
import {Setup} from "./utils/Setup.sol";

contract ShutdownTest is Setup {
    function setUpStrategy() public override returns (IStrategyInterface) {
        return IStrategyInterface(address(new USDCToUSDS(SUSDS, "USDC to USDS")));
    }

    function test_shutdownCanWithdraw(uint256 amount) public {
        amount = _boundAmount(amount);

        mintAndDepositIntoStrategy(strategy, user, amount);
        assertGe(strategy.totalAssets(), amount, "!totalAssets");

        skip(1 days);
        uint256 assets = strategy.totalAssets();

        vm.prank(emergencyAdmin);
        strategy.shutdownStrategy();

        assertApproxEqAbs(strategy.totalAssets(), assets, 1, "!totalAssets");

        uint256 balanceBefore = asset.balanceOf(user);
        uint256 shares = strategy.balanceOf(user);
        uint256 expected = strategy.previewRedeem(shares);

        vm.prank(user);
        strategy.redeem(shares, user, user, MAX_BPS);

        assertApproxEqAbs(asset.balanceOf(user), balanceBefore + expected, 1, "!final balance");
    }

    function test_emergencyWithdrawMaxUint(uint256 amount) public {
        amount = _boundAmount(amount);

        mintAndDepositIntoStrategy(strategy, user, amount);
        assertGe(strategy.totalAssets(), amount, "!totalAssets");

        skip(1 days);
        uint256 assets = strategy.totalAssets();

        vm.prank(emergencyAdmin);
        strategy.shutdownStrategy();

        assertApproxEqAbs(strategy.totalAssets(), assets, 1, "!totalAssets");

        vm.prank(emergencyAdmin);
        strategy.emergencyWithdraw(type(uint256).max);

        uint256 balanceBefore = asset.balanceOf(user);
        uint256 shares = strategy.balanceOf(user);
        uint256 expected = strategy.previewRedeem(shares);

        vm.prank(user);
        strategy.redeem(shares, user, user, MAX_BPS);

        assertApproxEqAbs(asset.balanceOf(user), balanceBefore + expected, 1, "!final balance");
    }
}
