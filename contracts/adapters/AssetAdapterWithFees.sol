// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.6.0;

import "@openzeppelin/contracts/math/SafeMath.sol";

import "./AssetAdapter.sol";

abstract contract AssetAdapterWithFees {
    using AssetAdapter for address;

    uint16 public feeThousandthsPercent;
    uint256 public minFeeAmount;

    mapping(address => uint256) private fees;

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

    function sendAssetKeepingFee(
        address _asset,
        address payable _to,
        uint256 _amount
    ) internal {
        _asset.sendValue(_to, _amount);
        fees[_asset] = SafeMath.add(fees[_asset], getFee(_amount));
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
