// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {Setup, IHealthCheck, IStrategyInterface} from "./utils/Setup.sol";

import {DAIToUSDC} from "../DAIToUSDC.sol";
import {USDCToSUSDS} from "../USDCToSUSDS.sol";
import {USDCToUSDS} from "../USDCToUSDS.sol";
import {USDSToUSDC} from "../USDSToUSDC.sol";
import {IPSM, ISUSDS} from "../interfaces/ISky.sol";

abstract contract ConverterBehaviorTest is Setup {
    function test_setupStrategyOK() public {
        assertTrue(address(strategy) != address(0));
        assertEq(strategy.asset(), address(asset));
        assertEq(strategy.management(), management);
        assertEq(strategy.performanceFeeRecipient(), performanceFeeRecipient);
        assertEq(strategy.keeper(), keeper);
        assertEq(strategy.emergencyAdmin(), emergencyAdmin);
        assertEq(strategy.apiVersion(), "3.1.0");
        assertEq(strategy.totalAssets(), 0);
        assertEq(strategy.strategyTotalAssets(), 0);
        assertTrue(!IHealthCheck(address(strategy)).open());
        assertEq(IHealthCheck(address(strategy)).lossLimitRatio(), 0);
    }

    function test_depositWithdraw(uint256 amount) public {
        amount = _boundAmount(amount);

        mintAndDepositIntoStrategy(strategy, user, amount);

        assertGe(strategy.totalAssets(), amount, "!totalAssets");
        assertGe(strategy.lastTotalAssets(), amount, "!lastTotalAssets");
        assertEq(asset.balanceOf(user), 0, "!userSpent");

        skip(1 days);

        // The vault's maxRedeem can lag totalAssets by unreported profit,
        // so a full exit is not always possible in a single redeem.
        uint256 shares = strategy.maxRedeem(user);
        assertGt(shares, 0, "!shares");
        uint256 expected = strategy.previewRedeem(shares);
        vm.prank(user);
        uint256 withdrawn = strategy.redeem(shares, user, user, MAX_BPS);

        assertApproxEqAbs(withdrawn, expected, 1, "!withdrawn");
        assertEq(asset.balanceOf(user), withdrawn, "!assetOut");
        assertGe(withdrawn, amount - (amount / 1000), "!fullValue");
        assertLe(strategy.totalAssets(), amount / 1000 + 2, "!residual");
    }

    function test_depositLimitZeroWhenPsmTinFeeOn() public {
        assertGt(strategy.availableDepositLimit(user), 0, "!depositLimit");

        vm.mockCall(PSM, abi.encodeWithSelector(IPSM.tin.selector), abi.encode(1));

        assertEq(strategy.availableDepositLimit(user), 0, "!feeDepositLimit");
    }

    function test_depositLimitZeroWhenPsmToutFeeOn() public {
        assertGt(strategy.availableDepositLimit(user), 0, "!depositLimit");

        vm.mockCall(PSM, abi.encodeWithSelector(IPSM.tout.selector), abi.encode(1));

        assertEq(strategy.availableDepositLimit(user), 0, "!feeDepositLimit");
    }

    function test_liveAccountingWithoutReport(uint256 amount, uint16 profitBps) public {
        amount = _boundAmount(amount);
        profitBps = uint16(bound(uint256(profitBps), 1, 1_000));

        mintAndDepositIntoStrategy(strategy, user, amount);

        uint256 baseline = strategy.totalAssets();
        uint256 lastTotalAssets = strategy.lastTotalAssets();
        uint256 requestedProfit = (amount * profitBps) / MAX_BPS;
        uint256 actualProfit = accrueYield(requestedProfit);

        skip(1);

        uint256 liveAssets = strategy.totalAssets();
        assertGe(liveAssets, baseline + actualProfit, "!liveAssets");
        assertEq(strategy.lastTotalAssets(), lastTotalAssets, "!noWriteSync");

        uint256 shares = strategy.maxRedeem(user);
        assertGt(shares, 0, "!shares");
        uint256 expected = strategy.previewRedeem(shares);
        vm.prank(user);
        uint256 withdrawn = strategy.redeem(shares, user, user, MAX_BPS);

        assertApproxEqAbs(withdrawn, expected, 1, "!withdrawnWithProfit");
        assertEq(asset.balanceOf(user), withdrawn, "!profitOut");
    }

    function test_reportIsNoopAfterLiveAccrual(uint256 amount, uint16 profitBps) public {
        amount = _boundAmount(amount);
        profitBps = uint16(bound(uint256(profitBps), 1, 1_000));

        mintAndDepositIntoStrategy(strategy, user, amount);

        accrueYield((amount * profitBps) / MAX_BPS);
        skip(1);

        uint256 liveAssets = strategy.totalAssets();
        assertGe(liveAssets, amount, "!liveAssets");

        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();

        assertEq(profit, 0, "!reportProfit");
        assertEq(loss, 0, "!reportLoss");
        assertApproxEqAbs(strategy.lastTotalAssets(), liveAssets, 1, "!synced");
    }

    function test_shutdownAndEmergencyWithdraw(uint256 amount) public {
        amount = _boundAmount(amount);

        mintAndDepositIntoStrategy(strategy, user, amount);
        uint256 assets = strategy.totalAssets();

        vm.prank(emergencyAdmin);
        strategy.shutdownStrategy();

        vm.prank(emergencyAdmin);
        strategy.emergencyWithdraw(type(uint256).max);

        assertApproxEqAbs(strategy.totalAssets(), assets, 1, "!assetsAfterEmergency");

        uint256 shares = strategy.maxRedeem(user);
        assertGt(shares, 0, "!shares");
        uint256 expected = strategy.previewRedeem(shares);
        vm.prank(user);
        uint256 withdrawn = strategy.redeem(shares, user, user, MAX_BPS);

        assertApproxEqAbs(withdrawn, expected, 1, "!withdrawn");
        assertEq(asset.balanceOf(user), withdrawn, "!assetOut");
    }

    function test_tendTriggerFalse(uint256 amount) public {
        amount = _boundAmount(amount);

        (bool trigger,) = strategy.tendTrigger();
        assertTrue(!trigger);

        mintAndDepositIntoStrategy(strategy, user, amount);

        (trigger,) = strategy.tendTrigger();
        assertTrue(!trigger);
    }
}

contract USDCToUSDSTest is ConverterBehaviorTest {
    function setUpStrategy() public override returns (IStrategyInterface) {
        return IStrategyInterface(address(new USDCToUSDS(SUSDS, "USDC to USDS")));
    }

    function accrueYield(uint256 amount) public override returns (uint256) {
        amount;
        uint256 beforeAssets = strategy.totalAssets();
        skip(1 days);
        uint256 afterAssets = strategy.totalAssets();
        return afterAssets > beforeAssets ? afterAssets - beforeAssets : 0;
    }

    function test_depositsConvertedFundsIntoVault() public {
        mintAndDepositIntoStrategy(strategy, user, 1_000e6);

        assertGt(vault.balanceOf(address(strategy)), 0, "!vaultShares");
        assertLt(usds.balanceOf(address(strategy)), SCALE, "!looseUsds");
    }
}

contract USDSToUSDCTest is ConverterBehaviorTest {
    function setUpStrategy() public override returns (IStrategyInterface) {
        return IStrategyInterface(address(new USDSToUSDC(USDC_VAULT, "USDS to USDC")));
    }

    function accrueYield(uint256 amount) public override returns (uint256) {
        uint256 beforeAssets = strategy.totalAssets();
        uint256 gemAmount = amount / SCALE;
        if (gemAmount == 0) gemAmount = 1;
        deal(USDC, address(this), gemAmount);
        usdc.approve(address(usdcVault), gemAmount);
        usdcVault.deposit(gemAmount, address(strategy));
        uint256 afterAssets = strategy.totalAssets();
        return afterAssets > beforeAssets ? afterAssets - beforeAssets : 0;
    }

    function test_depositsConvertedFundsIntoVault() public {
        mintAndDepositIntoStrategy(strategy, user, 1_000e18);

        assertGt(usdcVault.balanceOf(address(strategy)), 0, "!vaultShares");
        assertEq(usdc.balanceOf(address(strategy)), 0, "!looseUsdc");
    }
}

contract DAIToUSDCTest is ConverterBehaviorTest {
    function setUpStrategy() public override returns (IStrategyInterface) {
        return IStrategyInterface(address(new DAIToUSDC(USDC_VAULT, "DAI to USDC")));
    }

    function accrueYield(uint256 amount) public override returns (uint256) {
        uint256 beforeAssets = strategy.totalAssets();
        uint256 gemAmount = amount / SCALE;
        if (gemAmount == 0) gemAmount = 1;
        deal(USDC, address(this), gemAmount);
        usdc.approve(address(usdcVault), gemAmount);
        usdcVault.deposit(gemAmount, address(strategy));
        uint256 afterAssets = strategy.totalAssets();
        return afterAssets > beforeAssets ? afterAssets - beforeAssets : 0;
    }

    function test_depositsConvertedFundsIntoVault() public {
        mintAndDepositIntoStrategy(strategy, user, 1_000e18);

        assertGt(usdcVault.balanceOf(address(strategy)), 0, "!vaultShares");
        assertEq(usdc.balanceOf(address(strategy)), 0, "!looseUsdc");
    }
}

contract USDCToSUSDSTest is ConverterBehaviorTest {
    function setUpStrategy() public override returns (IStrategyInterface) {
        return IStrategyInterface(address(new USDCToSUSDS(SUSDS, "USDC to sUSDS")));
    }

    function accrueYield(uint256 amount) public override returns (uint256) {
        amount;
        uint256 beforeAssets = strategy.totalAssets();
        skip(1 days);
        uint256 afterAssets = strategy.totalAssets();
        return afterAssets > beforeAssets ? afterAssets - beforeAssets : 0;
    }

    function test_depositsConvertedFundsIntoVault() public {
        mintAndDepositIntoStrategy(strategy, user, 1_000e6);

        assertGt(vault.balanceOf(address(strategy)), 0, "!vaultShares");
        assertLt(usds.balanceOf(address(strategy)), SCALE, "!looseUsds");
    }

    function test_susdsReferralDeposit() public {
        uint256 amount = 1_000e6;
        vm.expectCall(
            SUSDS,
            abi.encodeWithSelector(
                ISUSDS.deposit.selector,
                amount * SCALE,
                address(strategy),
                USDCToSUSDS(address(strategy)).referralCode()
            )
        );
        mintAndDepositIntoStrategy(strategy, user, amount);
    }

    function test_setReferralCode() public {
        USDCToSUSDS susdsStrategy = USDCToSUSDS(address(strategy));
        assertEq(susdsStrategy.referralCode(), 224, "!default");

        vm.expectRevert("!management");
        vm.prank(user);
        susdsStrategy.setReferralCode(42);

        vm.prank(management);
        susdsStrategy.setReferralCode(42);
        assertEq(susdsStrategy.referralCode(), 42, "!set");

        uint256 amount = 1_000e6;
        vm.expectCall(
            SUSDS, abi.encodeWithSelector(ISUSDS.deposit.selector, amount * SCALE, address(strategy), uint16(42))
        );
        mintAndDepositIntoStrategy(strategy, user, amount);
    }
}
