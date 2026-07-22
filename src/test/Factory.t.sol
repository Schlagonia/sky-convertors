// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {IStrategyInterface} from "../interfaces/IStrategyInterface.sol";
import {USDSToUSDCFactory} from "../USDSToUSDCFactory.sol";

contract USDSToUSDCFactoryTest is Test {
    address public constant USDS = 0xdC035D45d973E3EC169d2276DDab16f1e407384F;
    address public constant USDC_VAULT = 0x696d02Db93291651ED510704c9b286841d506987;
    address public constant SUSDS = 0xa3931d71877C0E7a3148CB7Eb4463524FEc27fbD;

    address public management = address(1);
    address public performanceFeeRecipient = address(2);
    address public keeper = address(3);
    address public emergencyAdmin = address(4);
    address public user = address(5);

    USDSToUSDCFactory public factory;

    function setUp() public {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));
        factory = new USDSToUSDCFactory(management, performanceFeeRecipient, keeper, emergencyAdmin);
    }

    function test_newStrategy() public {
        address deployed = factory.newStrategy(USDC_VAULT);
        IStrategyInterface strategy = IStrategyInterface(deployed);

        assertEq(strategy.asset(), USDS);
        assertEq(strategy.VAULT(), USDC_VAULT);
        assertEq(strategy.name(), string(abi.encodePacked("USDS to ", ERC20(USDC_VAULT).name(), " Convertor")));
        assertEq(strategy.performanceFeeRecipient(), performanceFeeRecipient);
        assertEq(strategy.keeper(), keeper);
        assertEq(strategy.emergencyAdmin(), emergencyAdmin);
        assertEq(strategy.management(), address(factory));
        assertEq(strategy.pendingManagement(), management);
        assertEq(factory.deployments(USDC_VAULT), deployed);
        assertTrue(factory.isDeployedStrategy(deployed));

        vm.prank(management);
        strategy.acceptManagement();
        assertEq(strategy.management(), management);
        assertEq(strategy.pendingManagement(), address(0));
    }

    function test_newStrategyRevertsForNonUsdcVault() public {
        vm.expectRevert("!vault asset");
        factory.newStrategy(SUSDS);
    }

    function test_newStrategyRevertsOnDuplicateVault() public {
        address deployed = factory.newStrategy(USDC_VAULT);

        vm.expectRevert(abi.encodeWithSelector(USDSToUSDCFactory.AlreadyDeployed.selector, deployed));
        factory.newStrategy(USDC_VAULT);
    }

    function test_setAddressesOnlyManagement() public {
        vm.prank(user);
        vm.expectRevert("!management");
        factory.setAddresses(address(6), address(7), address(8));

        vm.prank(management);
        factory.setAddresses(address(6), address(7), address(8));

        assertEq(factory.management(), address(6));
        assertEq(factory.performanceFeeRecipient(), address(7));
        assertEq(factory.keeper(), address(8));
    }
}
