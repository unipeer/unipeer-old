// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.6.0;

import "./AssetAdapter.sol";

abstract contract AssetAdapterWithLocking {
    using AssetAdapter for address;

    event AmountLocked(address indexed seller, uint256 amount);
    event AmountUnlocked(address indexed seller, uint256 amount);

    mapping(address => uint256) private lockedBalance;

    function getUnlockedBalance(address _asset) public view returns (uint256) {
        return SafeMath.sub(_asset.getBalance(), lockedBalance[_asset]);
    }

    function lockAsset(address _asset, uint256 _amount) internal {
        require(
            getUnlockedBalance(_asset) >= _amount,
            "EthAdapter: insufficient funds to lock"
        );
        lockedBalance[_asset] = SafeMath.add(lockedBalance[_asset], _amount);
        emit AmountLocked(address(this), _amount);
    }

    function unlockAsset(address _asset, uint256 _amount) internal {
        lockedBalance[_asset] = SafeMath.sub(lockedBalance[_asset], _amount);
        emit AmountUnlocked(address(this), _amount);
    }
}
