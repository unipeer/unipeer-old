// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.6.2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

library AssetAdapter {
    using SafeERC20 for IERC20;

    address
        internal constant ETH_ADDR = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    /**
     * @dev Get the current balance of the Asset held by the implementing contract.
     */
    function getBalance(address asset) internal view returns (uint256 amount) {
        if (asset == ETH_ADDR) {
            return address(this).balance;
        } else {
            return IERC20(asset).balanceOf(address(this));
        }
    }

    /**
     * @dev Ensure the described asset is sent to the given address.
     * Reverts on failure.
     *
     * @dev Use openzeppelins Address#sendValue for ETH to circumvent gas price
     * increase after the istanbul fork. See Address#sendValue for more details or
     * https://diligence.consensys.net/blog/2019/09/stop-using-soliditys-transfer-now/.
     *
     * @param recipient Address to send the funds from the contract
     * @param amount Amount to transfer in the lowest unit (wei for ether)
     */
    function sendValue(
        address asset,
        address payable recipient,
        uint256 amount
    ) internal {
        if (asset == ETH_ADDR) {
            Address.sendValue(recipient, amount);
        } else {
            IERC20(asset).safeTransfer(recipient, amount);
        }
    }
}
