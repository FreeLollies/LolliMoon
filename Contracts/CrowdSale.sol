// SPDX-License-Identifier: MIT

pragma solidity 0.8.7;

import "../Contracts/Approve.sol";
import "../Contracts/Context.sol";
import "../Interfaces/IBEP20.sol";
import "../Libraries/SafeMath.sol";
import "../Contracts/Address.sol";
import "../Interfaces/IMoonity.sol";

/**
 * @dev Read Docs/CrowdSale.md
 */
contract CrowdSale is Context, IBEP20, Approve {

    using SafeMath for uint256;
    using Address for address;

    // Phases
    enum Phases{ CREATED, VIPSALE, VIPSALE_ENDED, SEEDSALE, SEEDSALE_ENDED, PRIVATESALE, PRIVATESALE_ENDED }

        // Token name and symbol
    string private constant TOKEN_NAME = "LM*VIP*";
    string private constant TOKEN_SYMBOL = "LM*VIP*";
    
    Phases private _salePhase;

    uint256 private T_TOTAL = 10000 * 10**6 * 10**9;

    // The maximum amount of tokens an investor can buy during a sale phase
    uint256 public constant TOKENBUYLIMIT = 2000000 * 10**9; // 9 decimals

    uint256 public TokenPriceInBNB = 2393146029771; // 18 decimals 
                                     
    bool private ContractsLinked;

    // Whitelists
    mapping (address => bool) private _isWhitelistedVIPSale;
    mapping (address => bool) private _isWhitelistedSeedSale;
    mapping (address => bool) private _isWhitelistedPrivateSale;  

    // Balances
    mapping (address => uint256) private _tOwnedVIPSale;
    mapping (address => uint256) private _tOwnedSeedSale;
    mapping (address => uint256) private _tOwnedPrivateSale;

    mapping (address => uint256) private _tOwnedVIPTokens;

    // Total amount of sold tokens
    uint256 public tokensSoldVIP;
    uint256 public tokensSoldSeed;
    uint256 public tokensSoldPrivate;

    // Timelock 
    uint256 public timeLock;

    address[] private _VIPTokenTransfer;
    address[] private _admin;


    Moonity public MoonityToken;

    // Modifiers
    /**
     * @dev Throws if called by any account other than an admin
     */
    modifier onlyAdmin() {
        require(isAdmin(_msgSender()), "Caller is not admin.");
        _;
    }
       
    // Events

    /**
     * @dev Emitted when the CrowdSale phase has changed
     */
    event CrowdSalePhaseChanged(Phases);

     /**
     * @dev Emitted when an address has been whitelisted
     */
    event AddressWhitelisted(address, Phases);

     /**
     * @dev Emitted when an address has been removed from whitelist
     */
    event AddressRemovedFromWhitelist(address, Phases);

    /**
     * @dev Emitted when the price of the token has been updated (daily actual BNB price)
     */
    event TokenPriceUpdated(uint256 price);


     /**
     * @dev Initializes the contract
     */
    constructor() {
        _salePhase = Phases.CREATED;
        _tOwnedVIPSale[msg.sender] = 0;
        _admin.push(_msgSender());
        emit Transfer(address(0), _msgSender(), 0);
    }

     /**
     * @dev IBEP20 interface: Returns the token name
     */
    function name() public pure override returns (string memory) {
        return TOKEN_NAME;
    }
      
    /**
     * @dev IBEP20 interface: Returns the smart-contract owner
     */
    function getOwner() external override view returns (address) {
        return owner();
    }
    
    /**
     * @dev IBEP20 interface: Returns the token symbol
     */
    function symbol() public pure override returns (string memory) {
        return TOKEN_SYMBOL;
    }

    /**
     * @dev IBEP20 interface: Returns the token decimals
     */
    function decimals() public pure override returns (uint8) {
        return 9;
    }

    /**
     * @dev IBEP20 interface: Returns the amount of tokens in existence
     */
    function totalSupply() public view override returns (uint256) {
        return T_TOTAL;
    }

    /**
     * @dev IBEP20 interface: Returns the amount of *VIP* tokens owned by `account`.
     */
    function balanceOf(address account) public view override returns (uint256) {
            return _tOwnedVIPTokens[account];   
    }

    function transfer(address /*receiver*/, uint256 /*numTokens*/) public override pure returns (bool) {
        return false;
    }

    function approve(address /*delegate*/, uint256 /*numTokens*/) public override pure returns (bool) {
        return false;
    }

    function allowance(address /*owner*/, address /*delegate*/) public override pure returns (uint) {
        return 0;
    }

    function transferFrom(address /*owner*/, address /*buyer*/, uint256 /*numTokens*/) public override pure returns (bool) {
        return false;
    }
   

    /**
     * @dev receive BNB
     */
     /* UNTRUSTED FUNCTION */
     /* Re-entrancy protection: Transfer tokens after refunding */
    receive() external payable {

        require(currentPhase() == Phases.VIPSALE || currentPhase() == Phases.SEEDSALE || currentPhase() == Phases.PRIVATESALE, "CrowdSale not active");
        
        uint256 SenderBalance = _getSenderBalance();
        require(SenderBalance < TOKENBUYLIMIT, "Max buy limit reached");

        (uint256 TransferTokens, uint256 RefundAmount) = _calculateTransferTokens(SenderBalance);

        _increaseSenderBalance(TransferTokens);

        // Only transfer during seedsale and privatesale. NOT VIPsale
        // VIPs get VIP tokens
        // VIPs will get their final tokens when the VIP sale has ended
        if(currentPhase() == Phases.SEEDSALE || currentPhase() == Phases.PRIVATESALE) {
            bool transferred = MoonityToken.TransferCrowdSaleTokens(_msgSender(), TransferTokens); // TRUSTED EXTERNAL CALL
            require(transferred, "Token transfer failed");  
        }
        
        if(RefundAmount > 0) {
            // Refund overpaid BNB
            (bool sent, ) = _msgSender().call{value: RefundAmount}("");
            require(sent, "Refunding failed");
        }       
    }

     /**
     * @dev Get the token balance of an address from VIPSale
     */
    function balanceOfVIPSale(address account) public view returns(uint256) {
        return _tOwnedVIPSale[account];
    }


     /**
     * @dev Get the token balance of an address from SeedSale
     */
    function balanceOfSeedSale(address account) public view returns(uint256) {
        return _tOwnedSeedSale[account];
    }

    /**
     * @dev Get the token balance of an address from PrivateSale
     */
    function balanceOfPrivateSale(address account) public view returns(uint256) {
        return _tOwnedPrivateSale[account];
    }

     /**
     * @dev Set the timelock 
     */
    function setTimeLock() public {
        require(ContractsLinked, "Contracts not linked");
        require(_msgSender() == address(MoonityToken), "Access denied");
        require(_salePhase == Phases.PRIVATESALE_ENDED, "Wrong order");
        require(timeLock == 0, "Already timelocked");
        timeLock = block.timestamp;
    }

    /**
     * @dev Get the locked token balance of an address
     * Up to 45 days after launch: Entire CrowdSale balance is locked
     * After 45 days: Unlock 2% every day.
     * After 95 days: Everything is unlocked
     */
    function lockedBalance(address account) public view returns(uint256) {
        uint256 Balance = 0;
        if(_isWhitelistedVIPSale[account]) {
            Balance = _tOwnedVIPSale[account];
        } else if(_isWhitelistedSeedSale[account]) {
            Balance = _tOwnedSeedSale[account];
        } else if(_isWhitelistedPrivateSale[account]) {
            Balance = _tOwnedPrivateSale[account];
        }

        if(timeLock == 0 || block.timestamp < timeLock.add(45 days)) { // Timer not started or not 45 days over
            return Balance; // Entire balance is timelocked
        } else if(block.timestamp <= timeLock.add(95 days)) { // More than 45 days but less than 95 days
            uint256 DaysOver45 = block.timestamp.sub(timeLock.add(45 days)); // How many days are over 45 days after launch (in seconds)
            uint256 PercentSeconds = 0;

             if(DaysOver45 <= 50 days) { // check underflow case
                 PercentSeconds = uint256(100 days).sub(DaysOver45.mul(2));
             }
                       
            return Balance.mul(PercentSeconds).div(100 days);
        } 

        // Nothing is locked anymore
        return 0;
    }


     /**
     * @dev withdraw BNB from contract
     * Can only be used by the owner of this contract
     */
    function withdraw (uint256 amount) public onlyOwnerWithApproval returns(bool res) {
        require(amount <= address(this).balance, "Balance not sufficient");
        payable(owner()).transfer(amount);
        return true;
    }

     /**
     * @dev withdraw all BNB from contract
     * Can only be used by the owner of this contract
     */
    function withdrawAll () public onlyOwnerWithApproval returns(bool res) {
        payable(owner()).transfer(address(this).balance);
        return true;
    }

     /**
     * @dev Update the token price manually
     * Due to daily fluctuation in BNB prices, the token price in BNB needs to be updated
     * Can only be used by the owner of this contract
     */
    function setTokenPriceInBNB (uint256 price) public onlyOwnerWithApproval {
        TokenPriceInBNB = price;
        emit TokenPriceUpdated(price);
    }

    /**
     * @dev Change phase of this token
     * Can only be used by the owner of this contract
     * Emits an CrowdSalePhaseChanged event
     */ 
    function changeCrowdSalePhase(Phases phase) public onlyOwnerWithApproval {
        
    	if(phase == Phases.VIPSALE)
        {
            require(_salePhase == Phases.CREATED, "Wrong order");
            _salePhase = Phases.VIPSALE;
            emit CrowdSalePhaseChanged(phase);
        }
        else
        {
            require(ContractsLinked,"Contracts not linked");

            if(phase == Phases.SEEDSALE) {
                require(_VIPTokenTransfer.length == 0, "Not all VIP tokens transferred");
            }
                      
            // Check if the correct previous phase is enabled
            require(uint(_salePhase) == uint(phase).sub(1), "Wrong order");

            _salePhase = phase;
            emit CrowdSalePhaseChanged(phase);
        }
    }

    /**
     * @dev Returns the current CrowdSale phase
     */
    function currentPhase() public view returns (Phases) {
        return _salePhase;
    }

     /**
     * @dev Adds a list of addresses to the whitelist. Only whitelisted addresses can buy tokens.
     * An account can only be whitelisted in one sale pahse
     * Can only be used by the owner of this contract
     */
    function AddToWhitelist(address[] memory Addresses, Phases ToWhitelist) public onlyAdmin() {
        require(ToWhitelist == Phases.VIPSALE || ToWhitelist == Phases.SEEDSALE || ToWhitelist == Phases.PRIVATESALE, "Wrong phase"); 
        for (uint i = 0; i < Addresses.length; i++) {
            if(Addresses[i] != owner())
            {
                if(!_isWhitelistedVIPSale[Addresses[i]] && !_isWhitelistedSeedSale[Addresses[i]] && !_isWhitelistedPrivateSale[Addresses[i]]) {
                   
                    if(ToWhitelist == Phases.VIPSALE)
                    {
                        _isWhitelistedVIPSale[Addresses[i]] = true;
                        _VIPTokenTransfer.push(Addresses[i]);   
                    } 
                    else if(ToWhitelist == Phases.SEEDSALE)
                    {
                        _isWhitelistedSeedSale[Addresses[i]] = true;   
                    } 
                    else 
                    {          
                        _isWhitelistedPrivateSale[Addresses[i]] = true;           
                    }

                    emit AddressWhitelisted(Addresses[i], ToWhitelist);
                }    
            }  
        } 
    }

     /**
     * @dev Removes a list of addresses from whitelist
     * Can only be used by the owner of this contract
     */
    function RemoveFromWhitelist(address[] memory Addresses , Phases FromWhitelist) public onlyAdmin() {
        require(FromWhitelist == Phases.VIPSALE || FromWhitelist == Phases.SEEDSALE || FromWhitelist == Phases.PRIVATESALE, "Wrong phase"); 
        for (uint i = 0; i < Addresses.length; i++) {

            if(FromWhitelist == Phases.VIPSALE){
                if(_tOwnedVIPSale[Addresses[i]] == 0){
                     _isWhitelistedVIPSale[Addresses[i]] = false;
                     _removeFrom_VIPs(Addresses[i]);
                }
            } else if(FromWhitelist == Phases.SEEDSALE){
                 if(_tOwnedSeedSale[Addresses[i]] == 0) {
                     _isWhitelistedSeedSale[Addresses[i]] = false;
                 }
            } else {
                 if(_tOwnedPrivateSale[Addresses[i]] == 0) {
                     _isWhitelistedPrivateSale[Addresses[i]] = false;
                 }
            }

            emit AddressRemovedFromWhitelist(Addresses[i], FromWhitelist);
        }
        
    }

    /**
     * @dev Returns true, if the address is whitelisted for the VIP sale
     */
    function isWhitelistedForVIPSale (address account) public view returns(bool) { 
        return _isWhitelistedVIPSale[account];
    }

    /**
     * @dev Returns true, if the address is whitelisted for the seed sale
     */
    function isWhitelistedForSeedSale (address account) public view returns(bool) { 
        return _isWhitelistedSeedSale[account];
    }

     /**
     * @dev Returns true, if the address is whitelisted for the private sale
     */
    function isWhitelistedForPrivateSale (address account) public view returns(bool) { 
        return _isWhitelistedPrivateSale[account];
    }

     /**
     * @dev Return the amount of VIPs
     */
    function VIPCount () public view returns(uint256) { 
        return _VIPTokenTransfer.length;
    }

    /**
     * @dev Links this contract with the token contract
     * Can only be used by the owner of this contract
     * TRUSTED
     */
    function linkMoonityContract(address ContractAddress) public onlyOwnerWithApproval {
        require(!ContractsLinked, "Already linked");
        MoonityToken = Moonity(ContractAddress);  // TRUSTED EXTERNAL CALL
        ContractsLinked = true;
    }

     /**
     * @dev Sends the final tradeable tokens to VIPs
     * To save gas charges, the number of accounts can be passed as a parameter. 
     * The function must be called repeatedly until all VIP tokens have been transferred.
     * Can only be used by the owner of this contract
     * TRUSTED
     */
    function distributeVIPTokens(uint256 count) public onlyOwnerWithApproval {
        require(ContractsLinked, "Contracts not linked");
        require(_salePhase == Phases.VIPSALE_ENDED, "Wrong order");

        uint256 counter = count;
        if(_VIPTokenTransfer.length < count) { counter = _VIPTokenTransfer.length; }
        
        for (uint i = 0; i < counter; i++) {
            uint256 VIPBalance = _tOwnedVIPSale[_VIPTokenTransfer[0]];
            if(VIPBalance > 0){
                _tOwnedVIPTokens[_VIPTokenTransfer[0]] = 0;
                bool transferred = MoonityToken.TransferCrowdSaleTokens(_VIPTokenTransfer[0], VIPBalance);  // TRUSTED EXTERNAL CALL
                require(transferred, "Token transfer failed");  
            }
            
            _removeFrom_VIPs(_VIPTokenTransfer[0]); 
        } 
    }

     /**
     * @dev Unlinks this contract from the token contract
     * Can only be used by the owner of this contract
     */
    function UnlinkContracts() public onlyOwnerWithApproval {
        require(ContractsLinked, "Already unlinked");
        require(_salePhase == Phases.CREATED || _salePhase == Phases.VIPSALE, "Not possible anymore");
        ContractsLinked = false;
    }

    /**
     * @dev Once the CrowdSale is finished, this contract may be destroyed
     * There is no further purpose for this contract
     * Can only be used by the owner
     * TRUSTED
     */
    function DestroyContract() public onlyOwnerWithApproval() {

        require(_salePhase == Phases.PRIVATESALE_ENDED, "Wrong order");

         // Token Contract
        require(MoonityToken.HasLaunched(), "Token not lauched, yet");  // TRUSTED EXTERNAL CALL

        // Send remaining BNB to owner's wallet and then selfdestruct
        selfdestruct(payable(owner()));
    }


    /**
     * @dev Get the token balance of an address from CrowdSale
     */
    function _getSenderBalance() private view returns(uint256) {
        if(currentPhase() == Phases.VIPSALE) {
            require(_isWhitelistedVIPSale[_msgSender()], "Not whitelisted");
            return _tOwnedVIPSale[_msgSender()];
        }
        else if(currentPhase() == Phases.SEEDSALE) {
            require(_isWhitelistedSeedSale[_msgSender()], "Not whitelisted");
            return _tOwnedSeedSale[_msgSender()];
        }
        else if(currentPhase() == Phases.PRIVATESALE) {
            require(_isWhitelistedPrivateSale[_msgSender()], "Not whitelisted");
             return _tOwnedPrivateSale[_msgSender()];
        } else {
            return TOKENBUYLIMIT;
        }

    }

     /**
     * @dev Add bought tokens to sender's balance
     */
    function _increaseSenderBalance(uint256 TransferTokens) private {
       if(currentPhase() == Phases.VIPSALE) {
             _tOwnedVIPSale[_msgSender()] = _tOwnedVIPSale[_msgSender()].add(TransferTokens);
             _tOwnedVIPTokens[_msgSender()] = _tOwnedVIPTokens[_msgSender()].add(TransferTokens);
             tokensSoldVIP = tokensSoldVIP.add(TransferTokens);
             emit Transfer(address(0), _msgSender(), TransferTokens);
        }
        else if(currentPhase() == Phases.SEEDSALE) {
             _tOwnedSeedSale[_msgSender()] = _tOwnedSeedSale[_msgSender()].add(TransferTokens);
             tokensSoldSeed = tokensSoldSeed.add(TransferTokens);
        }
        else if(currentPhase() == Phases.PRIVATESALE) {
            _tOwnedPrivateSale[_msgSender()] = _tOwnedPrivateSale[_msgSender()].add(TransferTokens);
            tokensSoldPrivate = tokensSoldPrivate.add(TransferTokens);
        }
    }

     /**
     * @dev Calculates how many tokens the address can get and how many BNB should be refunded
     */
     function _calculateTransferTokens(uint256 SenderBalance) private returns(uint256, uint256) {

        uint256 TokensAvailable;

        if(SenderBalance >= TOKENBUYLIMIT) { 
            TokensAvailable = 0; 
        } else {
            TokensAvailable = TOKENBUYLIMIT.sub(SenderBalance);
        }

        uint256 BNBforAllTokens = TokensAvailable.mul(TokenPriceInBNB).div(10**9); // in wei
        uint256 BNBReceived = msg.value; // in wei
        uint256 TransferTokens;
        uint256 TransferTokensCeil;
        uint256 RefundAmount;

        // More BNB received than needed?
        if(BNBReceived > BNBforAllTokens) {
            RefundAmount = BNBReceived.sub(BNBforAllTokens);
            TransferTokens = TokensAvailable;

        } else {
            // calculate how many tokens we want to buy
            TransferTokens = BNBReceived.mul(10**9).div(TokenPriceInBNB);  
        }

        // Round token count to the nearest whole number
        TransferTokensCeil = ((TransferTokens + 1000000000 - 1) / 1000000000) * 1000000000;

        return (TransferTokensCeil, RefundAmount);
     }
    

    /**
     * @dev Removes a VIP account
     */
    function _removeFrom_VIPs(address account) private {

        for (uint256 i = 0; i < _VIPTokenTransfer.length; i++) {
            if (_VIPTokenTransfer[i] == account) {
                _VIPTokenTransfer[i] = _VIPTokenTransfer[_VIPTokenTransfer.length - 1]; // Copy last element and overwrite account's position
                _VIPTokenTransfer.pop(); // remove last element
                break;
            }
        }
    }

     /**
     * @dev Returns true if sender is an admin
     */
    function isAdmin(address account) view public returns (bool){
      for (uint i; i< _admin.length;i++){
          if (_admin[i]==account) {
            return true;
          }          
      }
      return false;
    }

    /**
     * @dev Promote accounts to admin
     */
    function promoteAdmin(address account) public onlyOwnerWithApproval() {
      require(!isAdmin(account), "Already admin");
      _admin.push(account);
    }

    /**
     * @dev Removes accounts from admin
     */
    function removeAdmin(address account) public onlyOwnerWithApproval() {
      require(isAdmin(account), "Account is not an admin");
       for (uint i; i< _admin.length;i++){
          if (_admin[i]==account) {
              _admin[i] = _admin[_admin.length - 1];  // Copy last element and overwrite account's position
              _admin.pop(); // Remove last element
                break;
          }    
      }
    }

}
