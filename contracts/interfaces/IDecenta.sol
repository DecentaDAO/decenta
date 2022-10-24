pragma solidity ^0.8.0;

interface IDecenta {

    struct FloorToken {
        address _token;
        uint256[] _tokenId;
        uint256 num;
        bool flag;// true is single ,false is multiple
    }

    struct Order {
        address _maker;
        address _user;
        bool _isCall;
        uint256 _status;//0 is unFill,1 is cancelled,2 is filled,3 is exercised, 4 is expired
        uint256 _strike;
        uint256 _premium;
        uint256 _duration;
        FloorToken _floorTokens;
    }

    event CreateOrder(address maker,uint256 orderId, Order order);

    event FillOrder(address user,uint256 orderId, Order order);

    event Exercise(address maker,uint256 orderId, Order order);

    event Withdraw(address user,uint256 orderId, Order order);

    event PlaceOffer(address user,uint256 orderId, Order order,uint256 placeOfferId);

    event CancelPlace(address user,uint256 orderId, Order order, uint256 placeOfferId);

    event CancelOrder(address user,uint256 orderId, Order order);

    event AcceptOffer(address maker,address user,uint256 originalOrderId, Order originalOrder,uint256 placeOfferId, uint256 newOrderId, Order newOrder);
    
    function createOrder(
        bool isCall, 
        uint256 strike, 
        uint256 premium, 
        uint256 duration, 
        FloorToken memory floorTokens
    ) external payable returns(uint256);

    function fillOrder(address maker, uint256 orderId, uint256[] memory floorTokenIds) external payable;

    function exercise(uint256 orderId) external payable;

    function withdraw(uint256 orderId) external payable;

    function placeOffer(uint256 strike, uint256 premium, uint256 duration, address maker, uint256 orderId, uint256[] memory floorTokenIds) external payable;

    function cancelPlace(uint256 orderId, uint256 placeOfferId) external;

    function cancelOrder(uint256 orderId) external;

    function acceptOffer(address user, uint256 orderId, uint256 placeOfferId) external payable returns (uint256);

    function getUserOrderData(address user, uint256 _orderId) external view returns (Order memory order);

    function getUserOrderList (address user) external view returns (uint256[] memory);
}
