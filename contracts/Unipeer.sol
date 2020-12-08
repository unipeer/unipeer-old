// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.6.0;

import "@chainlink/contracts/src/v0.6/ChainlinkClient.sol";
import "@chainlink/contracts/src/v0.6/LinkTokenReceiver.sol";
import "@chainlink/contracts/src/v0.6/interfaces/LinkTokenInterface.sol";
import "@openzeppelin/contracts/utils/Address.sol";

import "hardhat/console.sol";

import "./utils/WithStatus.sol";
import "./adapters/AssetAdapterWithFees.sol";

contract Unipeer is
    ChainlinkClient,
    WithStatus,
    LinkTokenReceiver,
    AssetAdapterWithFees
{
    bytes32 private jobId;
    uint256 private fee;

    struct Seller {
        string paymentid;
        mapping(address => uint256) balance;
    }

    Seller[] private sellers;
    // paymentid => index of sellers
    mapping(string => uint256) public sellerIds;

    struct Job {
        uint256 sellerId;
        address payable buyer;
        uint256 amount;
        address token;
    }
    mapping(bytes32 => Job) private jobs;

    /**
     *
     * @param _link The address on the Link ERC20 Token contract
     * @param _oracle The chainlink node oracle address to send requests
     * @param _jobId The JobId for the Request
     */
    constructor(
        address _link,
        address _oracle,
        bytes32 _jobId
    )
        public
        AssetAdapterWithFees(490, 100 * 10**9) /* 0.49% or 100 gwei */
    {
        if (_link == address(0)) {
            setPublicChainlinkToken();
        } else {
            setChainlinkToken(_link);
        }
        setChainlinkOracle(_oracle);
        jobId = _jobId;
        fee = 0.01 * 10**18; // 0.01 LINK
    }

    function withdrawFees(
        address token,
        address payable _to,
        uint256 _amount
    ) public onlyOwner() statusAtLeast(Status.RETURN_ONLY) {
        token.sendValue(_to, _amount);
    }

    /**
     * @notice Returns the address of the LINK token
     * @dev This is the public implementation for chainlinkTokenAddress, which is
     * an internal method of the ChainlinkClient contract
     */
    function getChainlinkToken() public view override returns (address) {
        return chainlinkTokenAddress();
    }

    function createFiatPaymentWithLinkRequest(
        string calldata _senderpaymentid,
        address payable _buyer,
        uint256 _amount,
        address _token
    ) public statusAtLeast(Status.ACTIVE) {
        bytes memory payload = abi.encodeWithSignature(
            "requestFiatPaymentWithLink(string,address,uint256,address)",
            _senderpaymentid,
            _buyer,
            _amount,
            _token
        );

        require(
            LinkTokenInterface(chainlinkTokenAddress()).transferAndCall(
                address(this),
                fee,
                payload
            ),
            "Unipeer: unable to transferAndCall"
        );
    }

    function requestFiatPaymentWithLink(
        string calldata _senderpaymentid,
        address payable _buyer,
        uint256 _amount,
        address _token
    ) public onlyLINK() {
        _requestFiatPayment(_senderpaymentid, _buyer, _amount, _token);
    }

    function requestFiatPayment(
        string calldata _senderpaymentid,
        address payable _buyer,
        uint256 _amount,
        address _token /* onlyOwner() */
    ) public {
        _requestFiatPayment(_senderpaymentid, _buyer, _amount, _token);
    }

    function _requestFiatPayment(
        string calldata _senderpaymentid,
        address payable _buyer,
        uint256 _amount,
        address _token
    ) internal statusAtLeast(Status.ACTIVE) returns (bytes32 requestId) {
        uint256 sellerId = 1; // findSeller(_amount);
        Seller storage seller = sellers[sellerId];

        Chainlink.Request memory req = buildChainlinkRequest(
            jobId, // Chainlink JobId
            address(this), // contract address with the callback function
            this.fulfillFiatPayment.selector // callback function selector
        );
        req.add("method", "collectrequest");
        req.add("receiver", seller.paymentid);
        req.add("sender", _senderpaymentid);
        //req.addBytes("token", bytes(_token));
        req.addUint("amount", _amount);

        bytes32 reqId = sendChainlinkRequest(req, fee);

        // "lock" amount from seller balance
        seller.balance[_token] = seller.balance[_token].sub(_amount);

        jobs[reqId] = Job({
            sellerId: sellerId,
            buyer: _buyer,
            amount: _amount,
            token: _token
        });

        return reqId;
    }

    function fulfillFiatPayment(bytes32 _requestId, bool successful)
        public
        recordChainlinkFulfillment(_requestId)
    {
        Job memory job = jobs[_requestId];
        delete jobs[_requestId]; // cleanup storage

        if (successful) {
            sendAssetKeepingFee(job.token, job.buyer, job.amount);
        } else {
            // "unlock" amount from seller balance
            Seller storage seller = sellers[job.sellerId];
            seller.balance[job.token] = seller.balance[job.token].add(
                job.amount
            );
        }
    }

    /**
     * @dev We have the payable receive function to accept ether payment only
     * and not the fallback function to avoid delegating calls further.
     */
    receive() external payable {} // solhint-disable-line no-empty-blocks
}
