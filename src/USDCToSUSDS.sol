// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {USDCToUSDS} from "./USDCToUSDS.sol";
import {ISUSDS} from "./interfaces/ISky.sol";

contract USDCToSUSDS is USDCToUSDS {
    uint16 public referralCode = 1007;

    constructor(address _vault, string memory _name) USDCToUSDS(_vault, _name) {}

    function setReferralCode(uint16 _referralCode) external onlyManagement {
        referralCode = _referralCode;
    }

    function _depositInVault(uint256 _amount) internal override {
        ISUSDS(VAULT).deposit(_amount, address(this), referralCode);
    }
}
