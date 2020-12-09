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
        string paymentId;
        mapping(address => uint256) balance;
    }

    Seller[] private sellers;
    mapping(address => uint256) public sellerIds;

    // Could be IterableMapping
    // mapping(address => Seller) public sellers;

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

    /**
     * @dev deposit funds from a seller
     * TODO: split into separate newSeller & deposit function?
     *
     */
    function deposit(
        string calldata _paymentId,
        address _token,
        uint256 _amount
    ) public payable {
        uint256 sellerId = sellerIds[msg.sender];
        if (sellerId == 0) {
            Seller storage seller;
            seller.paymentId = _paymentId;
            seller.balance[_token] = _amount;
            sellers.push(seller);
            sellerId = sellers.length; // replace with counter?
            sellerIds[msg.sender] = sellerId;
        }
        Seller storage seller = sellers[sellerId];
        seller.balance[_token] = seller.balance[_token].add(_amount);
    }

    function withdraw(
        address _token,
        address payable _to,
        uint256 _amount
    ) public {
        uint256 sellerId = sellerIds[msg.sender];
        require(sellerId != 0, "Unipeer: user is not a seller");

        Seller storage seller = sellers[sellerId];
        require(
            seller.balance[_token] >= _amount,
            "Unipeer: cannot withdraw more the available funds"
        );
        _token.sendValue(_to, _amount);
    }

    function withdrawFees(
        address _token,
        address payable _to,
        uint256 _amount
    ) public onlyOwner() statusAtLeast(Status.RETURN_ONLY) {
        require(
            fees[_token] >= _amount,
            "Unipeer: Cannot withdraw more than collected fees"
        );
        _token.sendValue(_to, _amount);
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
        bytes memory payload =
            abi.encodeWithSignature(
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
        uint256 sellerId = 1; // findSeller(_amount); // TODO
        Seller storage seller = sellers[sellerId];

        Chainlink.Request memory req =
            buildChainlinkRequest(
                jobId, // Chainlink JobId
                address(this), // contract address with the callback function
                this.fulfillFiatPayment.selector // callback function selector
            );
        req.add("method", "collectrequest");
        req.add("receiver", seller.paymentId);
        req.add("sender", _senderpaymentid);
        //req.addBytes("token", bytes(_token));
        req.addUint("amount", _amount);

        bytes32 reqId = sendChainlinkRequest(req, fee);

        lockWithFees(seller, _token, _amount);

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
            Seller storage seller = sellers[job.sellerId];
            unlockWithFees(seller, job.token, job.amount);
        }
    }

    /**
     * @dev lock amount from seller balance
     */
    function lockWithFees(
        Seller storage _seller,
        address _token,
        uint256 _amount
    ) internal {
        _seller.balance[_token] = _seller.balance[_token].sub(_amount).sub(
            getFee(_amount)
        );
    }

    /**
     * @dev unlock amount from seller balance
     */
    function unlockWithFees(
        Seller storage _seller,
        address _token,
        uint256 _amount
    ) internal {
        _seller.balance[_token] = _seller.balance[_token].add(_amount).add(
            getFee(_amount)
        );
    }

    /**
     * @dev We have the payable receive function to accept ether payment only
     * and not the fallback function to avoid delegating calls further.
     */
    receive() external payable {} // solhint-disable-line no-empty-blocks
}
