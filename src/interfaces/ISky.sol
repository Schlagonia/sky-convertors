// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

interface ILitePSMWrapper {
    function sellGem(address usr, uint256 gemAmt) external returns (uint256 usdsOut);
    function buyGem(address usr, uint256 gemAmt) external returns (uint256 usdsIn);
}

interface IPSM {
    function tin() external view returns (uint256);
    function tout() external view returns (uint256);
}

interface IDaiUsds {
    function daiToUsds(address usr, uint256 wad) external;
    function usdsToDai(address usr, uint256 wad) external;
}

interface ISUSDS is IERC4626 {
    function deposit(uint256 assets, address receiver, uint16 referral) external returns (uint256 shares);
}
