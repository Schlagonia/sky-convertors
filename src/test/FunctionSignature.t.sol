// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {USDCToUSDS} from "../USDCToUSDS.sol";
import {IStrategyInterface} from "../interfaces/IStrategyInterface.sol";
import {Setup} from "./utils/Setup.sol";

contract FunctionSignatureTest is Setup {
    function setUpStrategy() public override returns (IStrategyInterface) {
        return IStrategyInterface(address(new USDCToUSDS(SUSDS, "USDC to USDS")));
    }

    // Checks that custom strategy functions do not collide with TokenizedStrategy.
    function test_functionCollisions() public {
        uint256 unit = 10 ** asset.decimals();
        vm.expectRevert("initialized");
        strategy.initialize(address(asset), "name", management, performanceFeeRecipient, keeper);

        assertEq(strategy.convertToAssets(unit), unit, "convert to assets");
        assertEq(strategy.convertToShares(unit), unit, "convert to shares");
        assertEq(strategy.previewDeposit(unit), unit, "preview deposit");
        assertEq(strategy.previewMint(unit), unit, "preview mint");
        assertEq(strategy.previewWithdraw(unit), unit, "preview withdraw");
        assertEq(strategy.previewRedeem(unit), unit, "preview redeem");
        assertEq(strategy.totalAssets(), 0, "total assets");
        assertEq(strategy.totalSupply(), 0, "total supply");
        assertEq(strategy.unlockedShares(), 0, "unlocked shares");
        assertEq(strategy.asset(), address(asset), "asset");
        assertEq(strategy.apiVersion(), "3.1.0", "api");
        assertEq(strategy.MAX_FEE(), 5_000, "max fee");
        assertEq(strategy.fullProfitUnlockDate(), 0, "unlock date");
        assertEq(strategy.profitUnlockingRate(), 0, "unlock rate");
        assertGt(strategy.lastReport(), 0, "last report");
        assertEq(strategy.pricePerShare(), unit, "pps");
        assertTrue(!strategy.isShutdown());
        assertEq(strategy.symbol(), string(abi.encodePacked("ys", asset.symbol())), "symbol");
        assertEq(strategy.decimals(), asset.decimals(), "decimals");

        vm.startPrank(user);
        vm.expectRevert("!management");
        strategy.setPendingManagement(user);
        vm.expectRevert("!pending");
        strategy.acceptManagement();
        vm.expectRevert("!management");
        strategy.setKeeper(user);
        vm.expectRevert("!management");
        strategy.setEmergencyAdmin(user);
        vm.expectRevert("!management");
        strategy.setPerformanceFee(uint16(2_000));
        vm.expectRevert("!management");
        strategy.setPerformanceFeeRecipient(user);
        vm.expectRevert("!management");
        strategy.setProfitMaxUnlockTime(1);
        vm.stopPrank();

        vm.startPrank(strategy.management());
        vm.expectRevert("Cannot be self");
        strategy.setPerformanceFeeRecipient(address(strategy));
        strategy.setProfitMaxUnlockTime(type(uint256).max);
        assertEq(strategy.profitMaxUnlockTime(), type(uint256).max, "max unlock time");
        vm.stopPrank();

        mintAndDepositIntoStrategy(strategy, user, unit);
        uint256 shares = strategy.balanceOf(user);

        assertGt(shares, 0, "shares");
        vm.prank(user);
        assertTrue(strategy.transfer(keeper, shares), "transfer");
        assertEq(strategy.balanceOf(user), 0, "second balance");
        assertEq(strategy.balanceOf(keeper), shares, "keeper balance");
        assertEq(strategy.allowance(keeper, user), 0, "allowance");
        vm.prank(keeper);
        assertTrue(strategy.approve(user, shares), "approval");
        assertEq(strategy.allowance(keeper, user), shares, "second allowance");
        vm.prank(user);
        assertTrue(strategy.transferFrom(keeper, user, shares), "transfer from");
        assertEq(strategy.balanceOf(user), shares, "third balance");
        assertEq(strategy.balanceOf(keeper), 0, "final keeper balance");

        ERC20(address(strategy));
    }
}
