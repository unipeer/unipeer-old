// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.6.0;

import "@openzeppelin/contracts/math/SafeMath.sol";

import "./AssetAdapterWithLocking.sol";

abstract contract AssetAdapterWithFees is AssetAdapterWithLocking {
    uint16 public feeThousandthsPercent;
    uint256 public minFeeAmount;

    /**
     * @param _feeThousandthsPercent The fee percentage with three decimal places.
     * @param _minFeeAmount The minimuim fee to charge.
     */
    constructor(uint16 _feeThousandthsPercent, uint256 _minFeeAmount) public {
        require(_feeThousandthsPercent < (1 << 16), "fee % too high");
        require(_minFeeAmount <= (1 << 255), "minFeeAmount too high");
        feeThousandthsPercent = _feeThousandthsPercent;
        minFeeAmount = _minFeeAmount;
    }

    function getFee(uint256 _amount) internal view returns (uint256) {
        uint256 fee = (_amount * feeThousandthsPercent) / 100000;
        return fee < minFeeAmount ? minFeeAmount : fee;
    }

    function getAmountWithFee(uint256 _amount) internal view returns (uint256) {
        uint256 baseAmount = _amount;
        return baseAmount + getFee(baseAmount);
    }

    function lockAssetWithFee(address _asset, uint256 _amount) internal {
        uint256 totalAmount = getAmountWithFee(_amount);
        lockAsset(_asset, totalAmount);
    }

    function unlockAssetWithFee(address _asset, uint256 _amount) internal {
        uint256 totalAmount = getAmountWithFee(_amount);
        unlockAsset(_asset, totalAmount);
    }

    function sendAssetWithFee(
        address _asset,
        address payable _to,
        uint256 _amount,
        address payable _feeCollector
    ) internal {
        _asset.sendValue(_to, _amount);
        _asset.sendValue(_feeCollector, getFee(_amount));
    }
}
