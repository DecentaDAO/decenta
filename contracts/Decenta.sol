// SPDX-License-Identifier: UNLICENSE
pragma solidity ^0.8.0;

import {IDecenta} from "./interfaces/IDecenta.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Counters} from "@openzeppelin/contracts/utils/Counters.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

contract Decenta is IDecenta, IERC721Receiver{

    using Counters for Counters.Counter;

    Counters.Counter internal _orderNo;
    Counters.Counter internal _placeOrderNo;

    mapping(address => mapping(uint256 => Order)) internal _orderData;
    mapping(address => mapping(uint256 => mapping(uint256 => Order))) internal _placeOfferData;
    mapping(address => uint256[]) internal _orderList;

    address internal _weth;

    constructor(address weth_) {
        require(weth_ != address(0), "Unset weth address");
        _weth = weth_;
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes memory
    ) public virtual override returns (bytes4) {
        return this.onERC721Received.selector;
    }

    function createOrder(
        bool isCall, 
        uint256 strike, 
        uint256 premium, 
        uint256 duration, 
        FloorToken memory floorTokens
    ) external payable override returns(uint256) {
        require(block.timestamp < duration && floorTokens.num != 0, "Invalid duration time");
        if (floorTokens.flag) {
            require(floorTokens._tokenId.length == 1 && floorTokens._tokenId.length == floorTokens.num, "Invalid parameter");
        }
        if (isCall && !floorTokens.flag) {
            require(floorTokens._tokenId.length == 0, "Invalid parameter");
        }
        if (!isCall && !floorTokens.flag) {
            require(floorTokens._tokenId.length == floorTokens.num, "Invalid parameter");
        }
        uint256 orderId = _orderNo.current();
        _orderData[msg.sender][orderId] = Order({
            _maker: msg.sender,
            _user: address(0),
            _isCall: isCall,
            _status: 0,
            _strike: strike,
            _premium: premium,
            _duration: duration,
            _floorTokens: floorTokens
        });
        Order memory order = _orderData[msg.sender][orderId];
        _orderList[msg.sender].push(orderId);
        _orderNo.increment();
        IERC20(_weth).transferFrom(msg.sender,address(this), order._premium);
        if (!isCall) {
            _transferFloorsIn(order._floorTokens, msg.sender);
        } 
        emit CreateOrder(msg.sender, orderId, order);
        return orderId;
    }

    function fillOrder(address maker, uint256 orderId, uint256[] memory floorTokenIds) external payable override {
        Order memory order = _orderData[maker][orderId];
        require(order._maker != msg.sender, "Can not buy own order");
        require(order._status == 0 && block.timestamp <= order._duration, "InvalidCall");
        order._isCall
            ? require(floorTokenIds.length == order._floorTokens.num, "Wrong amount of floor tokenIds")
            : require(floorTokenIds.length == 0, "Invalid floor tokens length");
        if(!order._floorTokens.flag && order._isCall) {
            order._floorTokens._tokenId = floorTokenIds;
        }
        order._user = msg.sender;
        order._status = 2;
        _orderData[order._maker][orderId] = order;
        _orderData[order._user][orderId] = order;
        _orderList[msg.sender].push(orderId);
        if (order._isCall) {
            IERC20(_weth).transfer(msg.sender, order._premium);
            _transferFloorsIn(order._floorTokens, msg.sender);
        } else {
            IERC20(_weth).transfer(msg.sender, order._premium);
            IERC20(_weth).transferFrom(msg.sender, address(this), order._strike);
        }
        emit FillOrder(msg.sender, orderId, order);
    }

    function exercise(uint256 orderId) external payable override {
        Order memory order = _orderData[msg.sender][orderId];
        require(order._maker == msg.sender && order._status == 2, "Only orderMaker can exercise");
        require(block.timestamp <= order._duration, "Is expired");
        order._status = 3;
        _orderData[order._user][orderId] = order;
        _orderData[msg.sender][orderId] = order;
        if (order._isCall) {
            IERC20(_weth).transferFrom(msg.sender, order._user, order._strike);
            _transferFloorsOut(order._floorTokens,msg.sender);
        } else {
            IERC20(_weth).transfer(msg.sender, order._strike);
            _transferFloorsOut(order._floorTokens,order._user);
        }
        emit Exercise(msg.sender, orderId, order);
    }

    function withdraw(uint256 orderId) external payable override {
        Order memory order = _orderData[msg.sender][orderId];
        require(block.timestamp > order._duration && order._status == 2,"InvalidCall");
        order._status = 4;
        _orderData[msg.sender][orderId] = order;
        if((order._maker == msg.sender && !order._isCall) || (order._user == msg.sender && order._isCall)){
            _transferFloorsOut(order._floorTokens, msg.sender);
        }
        if(order._user == msg.sender && !order._isCall){
            IERC20(_weth).transfer(msg.sender, order._strike);
        }
        emit Withdraw(msg.sender, orderId, order);
    }

    function placeOffer(uint256 strike, uint256 premium, uint256 duration, address maker, uint256 orderId, uint256[] memory floorTokenIds) external payable override {
        Order memory order = _orderData[maker][orderId];
        order._isCall
            ? require(floorTokenIds.length == order._floorTokens.num, "Wrong amount of floor tokenIds")
            : require(floorTokenIds.length == 0, "Invalid floor tokens length");
        if(!order._floorTokens.flag && order._isCall) {
            order._floorTokens._tokenId = floorTokenIds;
        }
        require(block.timestamp < duration, "Invalid duration time");
        require(order._status == 0 && order._maker != msg.sender, "Order is filled");
        order._strike = strike;
        order._premium = premium;
        order._duration = duration;
        order._user = msg.sender;
        order._status = 0;
        uint256 placeOfferId = _placeOrderNo.current();
        _placeOfferData[msg.sender][orderId][placeOfferId] = order;
        _placeOrderNo.increment();
        if (order._isCall) {
            _transferFloorsIn(order._floorTokens, msg.sender);
        } else {
            IERC20(_weth).transferFrom(msg.sender, address(this), order._strike);
        }
        emit PlaceOffer(msg.sender, orderId, order, placeOfferId);
    }

    function cancelPlace(uint256 orderId, uint256 placeOfferId) external override {
        Order memory order = _placeOfferData[msg.sender][orderId][placeOfferId];
        require(order._status == 0 && order._user == msg.sender, "InvalidCall");
        order._status = 1;
        _placeOfferData[msg.sender][orderId][placeOfferId] = order;
        if (order._isCall) {
            _transferFloorsOut(order._floorTokens, msg.sender);
        } else {
            IERC20(_weth).transfer(msg.sender, order._strike);
        }
        emit CancelPlace(msg.sender, orderId, order, placeOfferId);
    }

    function cancelOrder(uint256 orderId) public override {
        Order memory order = _orderData[msg.sender][orderId];
        require(order._status == 0 && msg.sender == order._maker, "InvalidCall");
        order._status = 1;
        _orderData[msg.sender][orderId] = order;
        IERC20(_weth).transfer(msg.sender, order._premium);
        if (!order._isCall) {
            _transferFloorsOut(order._floorTokens, msg.sender);
        } 
        emit CancelOrder(msg.sender, orderId, order);
    }
 
    function acceptOffer(address user, uint256 orderId, uint256 placeOfferId) external payable override returns (uint256) {
        Order memory order = _placeOfferData[user][orderId][placeOfferId];
        Order memory originalOrder = _orderData[msg.sender][orderId];
        require(order._maker == msg.sender && order._status ==0, "Invalidcall");
        require(originalOrder._status == 0 && block.timestamp <= originalOrder._duration, "Position is filled");
        originalOrder._status = 1;
        order._status = 1;
        _placeOfferData[order._user][orderId][placeOfferId] = order;
        _orderData[msg.sender][orderId] = originalOrder;
        order._maker = msg.sender;
        order._status = 2;
        uint256 _orderId = _orderNo.current();
        _orderData[msg.sender][_orderId] = order;
        _orderData[order._user][_orderId] = order;
        _orderList[msg.sender].push(_orderId);
        _orderList[order._user].push(_orderId);
        if (order._premium > originalOrder._premium) {
            IERC20(_weth).transferFrom(msg.sender, address(this), order._premium - originalOrder._premium);
        } else {
            IERC20(_weth).transfer(order._maker, originalOrder._premium - order._premium);
        }
        IERC20(_weth).transfer(order._user, order._premium);
        _orderNo.increment();
        emit AcceptOffer(msg.sender, user, orderId, originalOrder, placeOfferId, _orderId, order);
        return _orderId;
    }

    function getWeth() external view returns(address) {
        return _weth;
    }

    function getUserOrderData(address user, uint256 _orderId) external view override returns(Order memory order) {
        return _orderData[user][_orderId];    
    }

    function getUserOrderList(address user) external view override returns (uint256[] memory) {
        return _orderList[user];
    }
    
    function _transferFloorsIn(
        FloorToken memory floorTokens,
        address from
    ) internal {
        for (uint256 i = 0; i < floorTokens._tokenId.length; i++) {
            IERC721(floorTokens._token).safeTransferFrom(from, address(this), floorTokens._tokenId[i]);
        }
    }

    function _transferFloorsOut(FloorToken memory floorTokens,address user) internal {
        for (uint256 i = 0; i < floorTokens._tokenId.length; i++) {
            IERC721(floorTokens._token).safeTransferFrom(address(this), user, floorTokens._tokenId[i]);
        }
    }
}
