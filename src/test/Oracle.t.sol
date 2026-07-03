// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {StrategyAprOracle} from "../periphery/StrategyAprOracle.sol";
import {USDCToUSDS} from "../USDCToUSDS.sol";
import {IStrategyInterface} from "../interfaces/IStrategyInterface.sol";
import {Setup} from "./utils/Setup.sol";

contract OracleTest is Setup {
    StrategyAprOracle public oracle;

    function setUpStrategy() public override returns (IStrategyInterface) {
        return IStrategyInterface(address(new USDCToUSDS(SUSDS, "USDC to USDS")));
    }

    function setUp() public override {
        super.setUp();
        oracle = new StrategyAprOracle();
    }

    function checkOracle(address _strategy, uint256 _delta) public view {
        _delta;
        uint256 currentApr = oracle.aprAfterDebtChange(_strategy, 0);

        assertGt(currentApr, 0, "ZERO");
        assertLt(currentApr, 1e18, "+100%");
    }

    function test_oracle(uint256 amount, uint16 percentChange) public {
        amount = _boundAmount(amount);
        percentChange = uint16(bound(uint256(percentChange), 10, MAX_BPS));

        mintAndDepositIntoStrategy(strategy, user, amount);

        uint256 delta = (amount * percentChange) / MAX_BPS;

        checkOracle(address(strategy), delta);
    }
}
