pragma solidity ^0.4.23;
// import './trans.sol';
// import './models.sol';

contract MarketPlace{ 
    //owner of the main contract which is platform contract
    address owner;
    //to hold all parties data
    mapping  (address => Party) public parties; 
    //to hold all parties related transaction contracts addresses
    mapping  (address => address[]) public partyTransAddrs;
    //addresses of all  parties to iterate though
    address[] public partyAccounts;
    //addresses of all transaction contracts to iterate though
    address[] public transAccounts;
    //intital escrow. default is comtract owner is the escrow
    address public escrow; 
    //default is 1%, should be able to change this over a period
    uint platformFeePerCent = 1;
    
    enum PartyType{
        Trader,
        Transporter,
        Assessor
    }   
    //a system participant data structure
    struct Party{
        string name;
        string addrss;
        uint balance;
        PartyType partyType;
    }
    //an event triggers and notifies the callers when they add participant
    event Registered(address _address, string name, string addr,uint256 balance,uint partyType);

    //an event triggers and notifies the callers when a transaction creted by the caller
    event TransAdded(
        address contractadr,address seller, address buyer, uint status,uint256 transValue, 
        uint256 platformFee, string product, uint256 qty, uint256 unitprice
    );

    //an event triggers and notifies the callers when a transaction creted by the caller
    event TransStatusChanged(uint fromStatus,uint toStatus);

    //deploy platform contract with the percentage of fee in transaction value
    constructor(uint _platformFeePerCent) public {
        owner = escrow = msg.sender;         
        platformFeePerCent = _platformFeePerCent;
    }
    function string_tostring(string s) public pure returns (string){
        string memory b3 = string(s);
        return b3;
    }
    //to register a participant
    function Register(address _address, string name, string addr,uint balance,uint partyType) public {
        require(_address != address(0),"");
        parties[_address].name = string_tostring(name);
        parties[_address].addrss = string_tostring(addr); 
        parties[_address].balance = balance;
        parties[_address].partyType = PartyType(partyType);      
        partyAccounts.push(_address);
        emit Registered(_address,parties[_address].name,parties[_address].addrss,balance,partyType);
    }
    //to get a participant by etherem address
    function getParty(address _address)public view returns(address , string, string,uint256,uint) {
        require(_address != address(0),"error");
        return (_address,parties[_address].name,
                parties[_address].addrss,
                parties[_address].balance,
                uint(parties[_address].partyType)
        );
    }    
     //to get a transaction detail by etherem contract deployed address
    function getTranDetail1(address addr)public view returns(string selr, string buyr, string assr, 
        string tranprtr,uint st,string prod)  {
        Trans tr = Trans(addr);
        address _seller;
        address _buyer;
        address _assessor;
        address _transporter;
        ( _seller,_buyer,_assessor,_transporter,st,
        , , prod,,,,) = tr.getTransDetail();
        return (parties[_seller].name, parties[_buyer].name, parties[_assessor].name, parties[_transporter].name,
        st, prod);       
    }
     //to get a transaction detail by etherem contract deployed address
    function getTranDetail2(address addr)public view returns(uint256 val, uint256 shipChrg, uint256 qty, uint256 prce
    ,uint transStartDt,uint TransEndDt) {
        Trans tr = Trans(addr);
        (,,,,,val,shipChrg,, qty, prce,transStartDt,TransEndDt) = tr.getTransDetail();
        return (val, shipChrg,  qty, prce, transStartDt,  TransEndDt);
    }
    //to get all party related transaction contract addresses
    function getPartyTransList(address partyAddrss)public view returns(address[]){
        return partyTransAddrs[partyAddrss];
    }
    //adding a transaction. normally by the buyer
    function AddTransaction(
        address seller, address buyer,uint256 transValue, uint256 platformFee, 
        string product,uint256 qty,uint256 unitPrice) public payable returns(address){   
        require(seller != address(0),"wrong address");        
        require(buyer != address(0),"wrong address");
        require(seller != buyer,"buyer and seller cannot be same");
        require(transValue != (qty*unitPrice)*2,"Invalid transaction value, It has to be double to the (unitprice x qty)");  

        Trans transItem = (new Trans).value(msg.value)(address(this),seller,buyer, transValue, 
        platformFee, product, qty,unitPrice);
        partyTransAddrs[seller].push(address(transItem));
        partyTransAddrs[buyer].push(address(transItem));
        transAccounts.push(address(transItem));
        emit TransAdded(address(transItem),seller, buyer,0, transValue, platformFee, product, qty,unitPrice);
        return address(transItem);
    }

}

contract Trans{
    address platform;
    address seller;
    address buyer;
    address assessor;
    address transporter;    
    TransStatus status;
    uint256 transValue;
    uint256 shippingCharges;
    uint256 platformFee;
    string product;
    uint256 qty;
    uint256 unitPrice;

    uint TransStartDt;
    uint transPickupDt;
    uint buyerConfirmDeliveryDt;
    uint TransEndDt;
    //multiple transaction statuses that a transaction goes through 
    enum TransStatus{
        BuyerOrdered,
        SellerAccepted,
        TransporterAccepted,
        TransporterPickedup,
        TransporterDelivered,
        BuyerConfirmedDelivery,
        Completed
    }
    event transaporterSet(address, address);
    event assessorSet(address, address);
    event statusChanged(address, address);

    constructor(address _platform,address _seller, address _buyer,
        uint256 _transValue,uint256 _platformFee, 
        string _product,uint256 _qty,uint256 _unitPrice) public payable{
        platform = _platform;
        seller = _seller;
        buyer = _buyer;
        status = TransStatus.BuyerOrdered;
        transValue = _transValue;
        platformFee = _platformFee;
        product = _product;
        qty = _qty;
        unitPrice = _unitPrice;
        TransStartDt=now;
    }
    modifier mustBeAMember(){
        require(            
            msg.sender != seller && msg.sender != buyer && msg.sender != assessor && msg.sender != transporter, 
            "Only members can access the transaction");
        _;
    }
    modifier isOk(bool _condition){
        isValid(_condition);
        _;
    }
    modifier isValidParty(address party){
        isValid(msg.sender == party);
        _;
    }
    //seller / buyer can assessor
    function setAssessor(address _assessor) 
        public 
        isOk(msg.sender==seller || msg.sender==buyer) payable {
        assessor = _assessor;     
        emit assessorSet(_assessor, msg.sender);
    }
    //seller / buyer can Transporter
    function setTransporter(address _transporter) 
    public 
    isOk(msg.sender==seller || msg.sender==buyer) payable {
        transporter = _transporter;
        shippingCharges = msg.value;
        emit transaporterSet(_transporter,msg.sender);
    }
    function isValid(bool _condition) public pure {
        require(_condition,"Invalid action");
    }

    modifier isValidState(TransStatus _status){
        isValid(status == _status);
        _;
    }
    function getTransDetail() public view mustBeAMember returns (
        address, address, address, address, uint, uint256, uint256, string, uint256,uint256,
        uint, uint) {
        return (seller,buyer,assessor,transporter,
            uint(status),transValue, shippingCharges, product, 
            qty, unitPrice,TransStartDt, TransEndDt);
    }   

    function sellerAccepted() 
        public 
        isValidParty(seller) 
        isValidState(TransStatus.BuyerOrdered)
	{
        status = TransStatus.SellerAccepted;
    }
    //transporter accepts the pickup of produce
    function transporterAccepted() 
        public 
        isValidParty(transporter) 
        isValidState(TransStatus.SellerAccepted)
	{
        status = TransStatus.TransporterAccepted;
    }
    function transporterPickedup() 
        public 
        isValidParty(transporter) 
        isValidState(TransStatus.TransporterAccepted)
	{
        status = TransStatus.TransporterPickedup;
        transPickupDt = now;
    }   
    function transporterDelivered() 
        public 
        isValidParty(transporter) 
        isValidState(TransStatus.TransporterPickedup)
	{
        status = TransStatus.TransporterDelivered;
    }
    //after buyer confirmed the delivery of product, payment will be done for all parties
    function buyerConfirmedDelivery() 
        public 
        isValidParty(buyer) 
        isValidState(TransStatus.TransporterDelivered)
    {   
        status = TransStatus.BuyerConfirmedDelivery;
        buyerConfirmDeliveryDt = now;             
        PayParties();
    }
    function PayParties() 
        public 
        isValidParty(buyer) 
        isValidState(TransStatus.BuyerConfirmedDelivery)
    {
        uint256 actualtransvalue = transValue/2;
        uint256 sellerpercentage = 100-platformFee;  
        buyer.transfer(actualtransvalue);
        platform.transfer(actualtransvalue*platformFee/100);        
        seller.transfer(actualtransvalue*sellerpercentage/100);
        transporter.transfer(shippingCharges);
        TransEndDt = now;
        status = TransStatus.Completed;
    }
}