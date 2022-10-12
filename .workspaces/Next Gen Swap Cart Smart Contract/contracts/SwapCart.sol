// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;
// Author: Enes Arat
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

contract SwapCart{
    
    struct Item{    // We use struct as data structure to hold our Item data.
        uint itemId;
        string itemImage;
        uint star;
        address seller;
        uint price;
        uint32 dueDate;
    }

    struct User{    // We use struct as data structure to hold our User data.
        uint userID;
        string userName;
        string deliveryAddress;
        Item[] cart;
        uint balance;
    }

    // For minimizing the risk we only support one token per contract we will store the token in erc20. 
    IERC20 public immutable token; // We define variable as immutable to make sure  token will not be change.
    Item[] public itemList;

    mapping(address => User) public users; // We store user information according to the user id using mapping.
    mapping(uint256 => Item) public items; // We store item information according to the item id using mapping.
    mapping(uint => mapping(address => uint)) public itemsOfUsers; // We store item count according to the user which purchased any item using mapping.

    using Counters for Counters.Counter; // We use counter contract from openzeppelin
    Counters.Counter private itemCounter; // We define a counter variable

    // Initializes the token variable of the contract.
    constructor(address _token){
        token = IERC20(_token);
    } 

    modifier ownerCheck(uint itmId) {  // We check the message sender of transaction. Because, message sender must be same with seller to manage the sale advert. 
        Item memory item = items[itmId];
        require(msg.sender == item.seller);
        _;
    }
    modifier buyerCheck(uint itmId) {  // We check the message sender of transaction. Because, message sender must be a buyer to can give star for any item. (not seller of item)
        Item memory item = items[itmId];
        require(msg.sender != item.seller);
        _;
    }
    modifier expireCheck(uint itmId) {
        Item memory item = items[itmId];
        require(item.dueDate >= block.timestamp, "The sale has expired!");  // We check the Due date of sale advert. Because, due date must be greater than now to can be cancel. 
        _;
    }
    modifier balanceCheck(uint itmId){
        Item memory item = items[itmId];
        require(item.price <= users[msg.sender].balance, "There is not enough balance in your account!"); // We check the balance of buyer. Because, balance must be greater than item price to buy. 
        _;
    }
    modifier listSizeCheck(){
        require(itemCounter.current() > 0, "There are no products to list yet!"); // We check the size of item list. Because, we should give informaton to user before use listing method.
        _;
    }
    modifier itemAvailabilityCheck(uint itmId){
        require(itmId <= itemCounter.current(), "There is no such item record!"); // We check the availability of item. Because, we should check item before give iformation about item to user.
        _;
    }

    event CreateSaleAdvert(   // We defined the CreateSaleAdvert event to monitor the status of Creating Sale Advert functions in the background and be informed through variables.
        uint id,
        uint price,
        string image,
        uint32 dueDate,
        uint star,
        address indexed seller
    );

    event GetEntireItems(   // We defined the GetEntireItems event to monitor the status of getting entire items functions in the background and be informed through variables.
        Item[] listOfItems,
        address indexed caller
    );

    event AddStar(   // We defined the AddStar event to monitor the status of adding star functions in the background and be informed through variables.
        uint itmId,
        uint itmStar,
        address indexed caller
    );

    event GetItemById(   // We defined the GetItemById event to monitor the status of grrting item by id functions in the background and be informed through variables.
        uint itmId,
        Item item,
        address indexed caller
    );

    event CancelSaleAdvert(   // We defined the CancelSaleAdvert event to monitor the status of canceling sale advert functions in the background and be informed through variables.
        uint itmId,
        address indexed caller
    );

    event Payment(   // We defined the Payment event to monitor the status of payment functions in the background and be informed through variables.
        uint itmId,
        address indexed caller,
        uint amount
    );

    event ReturnItem(   // We defined the ReturnItem event to monitor the returning item payment functions in the background and be informed through variables.
        uint itmId,
        address indexed caller,
        uint amount
    );

    // Users will be able to create a sale advert stating their own wish.
    function createSaleAdvert(uint itmPrice, string memory itmImage, uint32 itmDueDate) external{
        itemCounter.increment();// We increase the amount of item to use in creating process.
        items[itemCounter.current()] = Item({   // We transfer the item information to be created over the current item amount to items mapping with a struct.
            itemId:itemCounter.current(),
            price:itmPrice,
            itemImage:itmImage,
            dueDate:itmDueDate,
            star:0,
            seller:msg.sender
        });
        itemsOfUsers[itemCounter.current()][msg.sender] += 1;

        itemList.push(items[itemCounter.current()]);

        emit CreateSaleAdvert(itemCounter.current(),itmPrice,itmImage,itmDueDate,items[itemCounter.current()].star,msg.sender); // Here we use the CreateSaleAdvert event we created earlier to be aware of the status.
    }

    // The advert creator will be able to cancel advert.
    function cancelSaleAdvert(uint itmId) external expireCheck(itmId) ownerCheck(itmId){
        itemsOfUsers[itmId][msg.sender] -= 1;
        delete items[itmId];  // If the conditions are met, we delete the target item from mapping.
        emit CancelSaleAdvert(itmId,msg.sender); // Here we use the cancel sale advert event we created earlier to be aware of the status.
    }
    // Users will be able to purchase while the item advert is still going.
    function payment(uint itmId, uint amount) external expireCheck(itmId) balanceCheck(itmId) buyerCheck(itmId){
        Item storage item = items[itmId]; // We create item variable on storage to hold item informations which exist with given item id
        itemsOfUsers[itmId][msg.sender] += 1;  // We increase the item amount of the target item according to the function caller.
        itemsOfUsers[itmId][item.seller] -= 1;
        token.transferFrom(msg.sender, item.seller, amount);  // We transfer payment amount from caller to item seller address over the token.
    
        emit Payment(itmId, msg.sender, amount); // Here we use the payment event we created earlier to be aware of the status.
    }

    // Users will be able to return payment while the item advert is still going.
    function returnItem(uint itmId, uint amount) external expireCheck(itmId) buyerCheck(itmId){
        itemsOfUsers[itmId][msg.sender] -= 1;  // We decrease the item amount of the target item according to the function caller.
        itemsOfUsers[itmId][items[itmId].seller] += 1;
        token.transfer(msg.sender, amount);  // We transfer return payment amount to caller over the token.

        emit ReturnItem(itmId, msg.sender, amount);  // Here we use the return payment event we created earlier to be aware of the status.
    }

    // Users will be able to get all items.
    function getEntireItems() public listSizeCheck returns (Item[] memory) {
        emit GetEntireItems(itemList,msg.sender); // Here we use the GetEntireItems event we created earlier to be aware of the status.
        return itemList;
    }

    // Users will be able to give star to any item.
    function addStar(uint itmId) public buyerCheck(itmId) {
        items[itmId].star++;
        emit AddStar(itmId,items[itmId].star,msg.sender); // Here we use the AddStar event we created earlier to be aware of the status.
    }

    // Users will be able to get item by id.
    function getItemById(uint itmId) public itemAvailabilityCheck(itmId) returns (Item memory) {
        emit GetItemById(itmId,items[itmId],msg.sender); // Here we use the GetItemById event we created earlier to be aware of the status.
        return items[itmId];
    }
}