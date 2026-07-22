// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {USDSToUSDC} from "./USDSToUSDC.sol";
import {IStrategyInterface} from "./interfaces/IStrategyInterface.sol";

contract USDSToUSDCFactory {
    event NewStrategy(address indexed strategy, address indexed vault);

    error AlreadyDeployed(address deployed);

    address public immutable emergencyAdmin;

    address public management;
    address public performanceFeeRecipient;
    address public keeper;

    mapping(address => address) public deployments;

    constructor(address _management, address _performanceFeeRecipient, address _keeper, address _emergencyAdmin) {
        management = _management;
        performanceFeeRecipient = _performanceFeeRecipient;
        keeper = _keeper;
        emergencyAdmin = _emergencyAdmin;
    }

    function newStrategy(address _vault) external returns (address) {
        address deployed = deployments[_vault];
        if (deployed != address(0)) revert AlreadyDeployed(deployed);

        string memory name = string(abi.encodePacked("USDS to ", ERC20(_vault).name(), " Convertor"));
        IStrategyInterface strategy = IStrategyInterface(address(new USDSToUSDC(_vault, name)));

        strategy.setPerformanceFeeRecipient(performanceFeeRecipient);
        strategy.setKeeper(keeper);
        strategy.setEmergencyAdmin(emergencyAdmin);
        strategy.setPendingManagement(management);

        deployments[_vault] = address(strategy);
        emit NewStrategy(address(strategy), _vault);

        return address(strategy);
    }

    function setAddresses(address _management, address _performanceFeeRecipient, address _keeper) external {
        require(msg.sender == management, "!management");
        management = _management;
        performanceFeeRecipient = _performanceFeeRecipient;
        keeper = _keeper;
    }

    function isDeployedStrategy(address _strategy) external view returns (bool) {
        return deployments[IStrategyInterface(_strategy).VAULT()] == _strategy;
    }
}
