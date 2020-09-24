// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

import "@chainlink/contracts/src/v0.6/ChainlinkClient.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "@nomiclabs/buidler/console.sol";

import "./StaticProxy.sol";
import "./adapters/EthAdapter.sol";

contract Escrow is StaticStorage, ChainlinkClient, EthAdapter, Ownable {
  address public comptroller;

  uint256 lockedAmount;
  struct Job {
    address buyer;
    uint256 amount;
  }
  mapping(bytes32 => Job) jobs;

  constructor(address _comptroller) public {
    comptroller = _comptroller;
  }

  modifier onlyComptroller() {
    require(comptroller == msg.sender, "Escrow: caller is not the comptroller");
    _;
  }

  function getUnlockedBalance() public view returns (uint256 amount) {
    return getBalance().sub(lockedAmount);
  }

  function withdraw(uint256 _amount, address _to) public onlyOwner() returns (bool success) {
    require(
      getUnlockedBalance() > _amount,
      "Escrow: cannot withdraw more than unlocked balance"
    );
    return rawSendAsset(_amount, payable(_to));
  }

  function expectResponseFor(
    address _oracle,
    bytes32 _requestId,
    address _buyer,
    uint256 _amount
  ) public onlyComptroller {
    jobs[_requestId] = Job({buyer: _buyer, amount: _amount});
    lockedAmount.add(_amount);
    addChainlinkExternalRequest(_oracle, _requestId);
  }

  function fulfillFiatPayment(bytes32 _requestId, bool successful) public {
    validateChainlinkCallback(_requestId);

    Job memory job = jobs[_requestId];
    delete jobs[_requestId]; // cleanup storage

    if (successful) {
      rawSendAsset(job.amount, payable(job.buyer));
    } else {
      lockedAmount.sub(job.amount);
    }
  }
}
