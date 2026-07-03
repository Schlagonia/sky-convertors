// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IEvents} from "@tokenized-strategy/interfaces/IEvents.sol";

import {IStrategyInterface} from "../../interfaces/IStrategyInterface.sol";

interface IHealthCheck {
    function open() external view returns (bool);
    function lossLimitRatio() external view returns (uint256);
    function setAllowed(address _depositor, bool _allowed) external;
}

abstract contract Setup is Test, IEvents {
    uint256 public constant MAX_BPS = 10_000;
    uint256 public constant SCALE = 1e12;
    address public constant TOKENIZED_STRATEGY = 0x310f5Db015E9d6E542fd41bd4542640790791e76;
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address public constant USDS = 0xdC035D45d973E3EC169d2276DDab16f1e407384F;
    address public constant SUSDS = 0xa3931d71877C0E7a3148CB7Eb4463524FEc27fbD;
    address public constant USDC_VAULT = 0x696d02Db93291651ED510704c9b286841d506987;
    address public constant DAI_USDS = 0x3225737a9Bbb6473CB4a45b7244ACa2BeFdB276A;
    address public constant PSM = 0xf6e72Db5454dd049d0788e411b06CfAF16853042;
    address public constant LITE_PSM_WRAPPER = 0xA188EEC8F81263234dA3622A406892F3D630f98c;

    ERC20 public usdc;
    ERC20 public usds;
    ERC20 public dai;
    IERC4626 public vault;
    IERC4626 public usdcVault;

    ERC20 public asset;
    IStrategyInterface public strategy;

    address public user = address(10);
    address public keeper = address(4);
    address public management = address(1);
    address public performanceFeeRecipient = address(3);
    address public emergencyAdmin = address(5);

    uint256 public decimals;
    uint256 public minFuzzAmount;
    uint256 public maxFuzzAmount;

    function setUp() public virtual {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));

        usdc = ERC20(USDC);
        usds = ERC20(USDS);
        dai = ERC20(DAI);
        vault = IERC4626(SUSDS);
        usdcVault = IERC4626(USDC_VAULT);
        require(usdcVault.asset() == USDC, "!usdc vault asset");

        strategy = setUpStrategy();
        asset = ERC20(strategy.asset());
        decimals = asset.decimals();
        minFuzzAmount = 10 ** decimals;
        maxFuzzAmount = 100_000 * 10 ** decimals;

        _configureRoles(strategy);

        vm.prank(management);
        strategy.acceptManagement();

        vm.prank(management);
        IHealthCheck(address(strategy)).setAllowed(user, true);

        vm.prank(management);
        strategy.setPerformanceFee(0);

        vm.label(user, "user");
        vm.label(keeper, "keeper");
        vm.label(address(asset), "asset");
        vm.label(management, "management");
        vm.label(address(strategy), "strategy");
        vm.label(performanceFeeRecipient, "performanceFeeRecipient");
        vm.label(SUSDS, "susds");
        vm.label(USDC_VAULT, "usdcVault");
    }

    function setUpStrategy() public virtual returns (IStrategyInterface);

    function depositIntoStrategy(IStrategyInterface _strategy, address _user, uint256 _amount) public {
        vm.prank(_user);
        asset.approve(address(_strategy), _amount);

        vm.prank(_user);
        _strategy.deposit(_amount, _user);
    }

    function mintAndDepositIntoStrategy(IStrategyInterface _strategy, address _user, uint256 _amount) public {
        airdrop(asset, _user, _amount);
        depositIntoStrategy(_strategy, _user, _amount);
    }

    function checkStrategyTotals(
        IStrategyInterface _strategy,
        uint256 _totalAssets,
        uint256 _totalDebt,
        uint256 _totalIdle
    ) public {
        uint256 assets_ = _strategy.totalAssets();
        uint256 balance = ERC20(_strategy.asset()).balanceOf(address(_strategy));
        uint256 idle = balance > assets_ ? assets_ : balance;
        uint256 debt = assets_ - idle;
        assertEq(assets_, _totalAssets, "!totalAssets");
        assertEq(debt, _totalDebt, "!totalDebt");
        assertEq(idle, _totalIdle, "!totalIdle");
        assertEq(_totalAssets, _totalDebt + _totalIdle, "!Added");
    }

    function airdrop(ERC20 _asset, address _to, uint256 _amount) public {
        deal(address(_asset), _to, _amount);
    }

    function accrueYield(uint256 _amount) public virtual returns (uint256) {
        _amount;
        return 0;
    }

    function _configureRoles(IStrategyInterface _strategy) internal {
        _strategy.setPerformanceFeeRecipient(performanceFeeRecipient);
        _strategy.setKeeper(keeper);
        _strategy.setEmergencyAdmin(emergencyAdmin);
        _strategy.setPendingManagement(management);
    }

    function _boundAmount(uint256 _amount) internal view returns (uint256) {
        return bound(_amount, minFuzzAmount, maxFuzzAmount);
    }
}
