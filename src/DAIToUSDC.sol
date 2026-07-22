// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {BaseHealthCheck} from "@periphery/Bases/HealthCheck/BaseHealthCheck.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {TokenizedStrategyLib as TokenizedStrategy} from "@tokenized-strategy/libraries/TokenizedStrategyLib.sol";

import {IDaiUsds, ILitePSMWrapper, IPSM} from "./interfaces/ISky.sol";

contract DAIToUSDC is BaseHealthCheck {
    using SafeERC20 for ERC20;

    address public constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address public constant USDS = 0xdC035D45d973E3EC169d2276DDab16f1e407384F;
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant DAI_USDS = 0x3225737a9Bbb6473CB4a45b7244ACa2BeFdB276A;
    address public constant PSM = 0xf6e72Db5454dd049d0788e411b06CfAF16853042;
    address public constant LITE_PSM_WRAPPER = 0xA188EEC8F81263234dA3622A406892F3D630f98c;

    address public immutable VAULT;

    uint256 public constant SCALE = 1e12;

    constructor(address _vault, string memory _name) BaseHealthCheck(DAI, _name) {
        require(IERC4626(_vault).asset() == USDC, "!vault asset");
        VAULT = _vault;

        allowed[address(this)] = true;

        asset.forceApprove(DAI_USDS, type(uint256).max);
        ERC20(USDS).forceApprove(DAI_USDS, type(uint256).max);
        ERC20(USDS).forceApprove(LITE_PSM_WRAPPER, type(uint256).max);
        ERC20(USDC).forceApprove(LITE_PSM_WRAPPER, type(uint256).max);
        ERC20(USDC).forceApprove(VAULT, type(uint256).max);
    }

    function availableWithdrawLimit(address) public view override returns (uint256) {
        return asset.balanceOf(address(this)) + _availableConvertedInAsset();
    }

    function availableDepositLimit(address _owner) public view override returns (uint256) {
        if (_psmHasFee()) return 0;
        return _min(super.availableDepositLimit(_owner), _scaleUsdcToAsset(IERC4626(VAULT).maxDeposit(address(this))));
    }

    function _deployFunds(uint256 _amount) internal override {
        IDaiUsds(DAI_USDS).daiToUsds(address(this), _amount);

        uint256 gemAmount = ERC20(USDS).balanceOf(address(this)) / SCALE;
        if (gemAmount != 0) {
            uint256 usdsIn = ILitePSMWrapper(LITE_PSM_WRAPPER).buyGem(address(this), gemAmount);
            require(usdsIn <= gemAmount * SCALE, "psm fee");
        }

        uint256 looseUsdc = ERC20(USDC).balanceOf(address(this));
        if (looseUsdc != 0) {
            _depositInVault(looseUsdc);
        }
    }

    function _freeFunds(uint256 _amount) internal override {
        uint256 usdsBalance = ERC20(USDS).balanceOf(address(this));
        if (usdsBalance < _amount) {
            uint256 gemNeeded = _ceilDiv(_amount - usdsBalance, SCALE);
            uint256 looseUsdc = ERC20(USDC).balanceOf(address(this));

            if (looseUsdc < gemNeeded) {
                _redeemFromVault(gemNeeded - looseUsdc);
            }

            uint256 gemAmount = _min(gemNeeded, ERC20(USDC).balanceOf(address(this)));
            if (gemAmount != 0) {
                ILitePSMWrapper(LITE_PSM_WRAPPER).sellGem(address(this), gemAmount);
            }
        }

        uint256 usdsToConvert = _min(_amount, ERC20(USDS).balanceOf(address(this)));
        if (usdsToConvert != 0) {
            IDaiUsds(DAI_USDS).usdsToDai(address(this), usdsToConvert);
        }
    }

    function _harvestAndReport() internal override returns (uint256) {
        if (!TokenizedStrategy.isShutdown()) {
            uint256 toDeploy = _min(asset.balanceOf(address(this)), availableDepositLimit(address(this)));
            if (toDeploy != 0) {
                _deployFunds(toDeploy);
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
        uint256 usdcBalance = ERC20(USDC).balanceOf(address(this))
            + IERC4626(VAULT).convertToAssets(IERC4626(VAULT).balanceOf(address(this)));
        return ERC20(USDS).balanceOf(address(this)) + _scaleUsdcToAsset(usdcBalance);
    }

    function _availableConvertedInAsset() internal view returns (uint256) {
        uint256 usdcBalance = ERC20(USDC).balanceOf(address(this))
            + IERC4626(VAULT).convertToAssets(IERC4626(VAULT).maxRedeem(address(this)));
        return ERC20(USDS).balanceOf(address(this)) + _scaleUsdcToAsset(usdcBalance);
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

    function _ceilDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        return a == 0 ? 0 : (a - 1) / b + 1;
    }

    function _scaleUsdcToAsset(uint256 _amount) internal pure returns (uint256) {
        if (_amount > type(uint256).max / SCALE) return type(uint256).max;
        return _amount * SCALE;
    }

    function _psmHasFee() internal view returns (bool) {
        return IPSM(PSM).tin() > 0 || IPSM(PSM).tout() > 0;
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    function manualRedeem(uint256 _shares) external onlyManagement returns (uint256) {
        _shares = _min(_shares, IERC4626(VAULT).maxRedeem(address(this)));
        if (_shares == 0) return 0;
        return IERC4626(VAULT).redeem(_shares, address(this), address(this));
    }

    function manualPsmSwap(uint256 _gemAmount) external onlyManagement returns (uint256) {
        return ILitePSMWrapper(LITE_PSM_WRAPPER).sellGem(address(this), _gemAmount);
    }
}
