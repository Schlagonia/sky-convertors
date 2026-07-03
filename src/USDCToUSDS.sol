// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {BaseHealthCheck} from "@periphery/Bases/HealthCheck/BaseHealthCheck.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {TokenizedStrategyLib as TokenizedStrategy} from "@tokenized-strategy/libraries/TokenizedStrategyLib.sol";

import {ILitePSMWrapper, IPSM} from "./interfaces/ISky.sol";

contract USDCToUSDS is BaseHealthCheck {
    using SafeERC20 for ERC20;

    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant USDS = 0xdC035D45d973E3EC169d2276DDab16f1e407384F;
    address public constant PSM = 0xf6e72Db5454dd049d0788e411b06CfAF16853042;
    address public constant LITE_PSM_WRAPPER = 0xA188EEC8F81263234dA3622A406892F3D630f98c;

    address public immutable VAULT;

    uint256 public constant SCALE = 1e12;

    constructor(address _vault, string memory _name) BaseHealthCheck(USDC, _name) {
        require(IERC4626(_vault).asset() == USDS, "!vault asset");
        VAULT = _vault;

        asset.forceApprove(LITE_PSM_WRAPPER, type(uint256).max);
        ERC20(USDS).forceApprove(LITE_PSM_WRAPPER, type(uint256).max);
        ERC20(USDS).forceApprove(VAULT, type(uint256).max);
    }

    function availableWithdrawLimit(address) public view override returns (uint256) {
        return asset.balanceOf(address(this)) + _availableConvertedInAsset();
    }

    function availableDepositLimit(address _owner) public view override returns (uint256) {
        if (_psmHasFee()) return 0;
        return _min(super.availableDepositLimit(_owner), IERC4626(VAULT).maxDeposit(address(this)) / SCALE);
    }

    function _deployFunds(uint256 _amount) internal override {
        uint256 usdsOut = ILitePSMWrapper(LITE_PSM_WRAPPER).sellGem(address(this), _amount);
        require(usdsOut >= _amount * SCALE, "psm fee");

        uint256 looseUsds = ERC20(USDS).balanceOf(address(this));
        if (looseUsds != 0) {
            _depositInVault(looseUsds);
        }
    }

    function _freeFunds(uint256 _amount) internal override {
        uint256 usdsNeeded = _amount * SCALE;
        uint256 looseUsds = ERC20(USDS).balanceOf(address(this));

        if (looseUsds < usdsNeeded) {
            _redeemFromVault(usdsNeeded - looseUsds);
        }

        uint256 gemAmount = _min(_amount, ERC20(USDS).balanceOf(address(this)) / SCALE);
        if (gemAmount == 0) return;

        ILitePSMWrapper(LITE_PSM_WRAPPER).buyGem(address(this), gemAmount);
    }

    function _harvestAndReport() internal override returns (uint256) {
        if (!TokenizedStrategy.isShutdown()) {
            uint256 looseAsset = asset.balanceOf(address(this));
            if (looseAsset != 0) {
                _deployFunds(looseAsset);
            }
        }

        return _strategyTotalAssets();
    }

    function _strategyTotalAssets() internal view override returns (uint256) {
        return asset.balanceOf(address(this)) + _totalConvertedInAsset();
    }

    function _emergencyWithdraw(uint256 _amount) internal override {
        _amount = _min(_amount, _availableConvertedInAsset());

        _freeFunds(_amount);
    }

    function _totalConvertedInAsset() internal view returns (uint256) {
        uint256 balance = ERC20(USDS).balanceOf(address(this))
            + IERC4626(VAULT).convertToAssets(IERC4626(VAULT).balanceOf(address(this)));
        return balance / SCALE;
    }

    function _availableConvertedInAsset() internal view returns (uint256) {
        uint256 balance = ERC20(USDS).balanceOf(address(this))
            + IERC4626(VAULT).convertToAssets(IERC4626(VAULT).maxRedeem(address(this)));
        return balance / SCALE;
    }

    function _depositInVault(uint256 _amount) internal virtual {
        IERC4626(VAULT).deposit(_amount, address(this));
    }

    function _redeemFromVault(uint256 _needed) internal {
        uint256 shares = _min(IERC4626(VAULT).previewWithdraw(_needed), IERC4626(VAULT).balanceOf(address(this)));

        if (shares != 0) {
            IERC4626(VAULT).redeem(shares, address(this), address(this));
        }
    }

    function _psmHasFee() internal view returns (bool) {
        return IPSM(PSM).tin() > 0 || IPSM(PSM).tout() > 0;
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}
