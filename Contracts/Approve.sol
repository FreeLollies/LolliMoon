// SPDX-License-Identifier: MIT

pragma solidity 0.8.7;

import "./Context.sol";
import "./Ownable.sol";

/**
 * @dev 
 */
abstract contract Approve is Context, Ownable {
    address private _approver;
    bool public isApproved;

     event NewApprover(address indexed previousApprover, address indexed newApprover);

    /**
    * @dev Throws if approval is not given or sender is not owner
    */
    modifier onlyOwnerWithApproval() {
        require(isApproved, "No approval given");
        require(owner() == _msgSender(), "Caller is not the owner");
        _;
        isApproved = false;
    }

    /**
    * @dev Throws if sender is not appover
    */
    modifier onlyApprover() {
        require(_approver == _msgSender(), "Caller is not the approver");
        _;
    }

    /**
     * @dev Initializes the contract 
     */
    constructor() {
        address msgSender = _msgSender();
        _approver = msgSender;
    }

    /**
     * @dev Returns the address of the current approver.
     */
    function approver() public view returns (address) {
        return _approver;
    }
    
   /**
     * @dev Approve
     */
    function grantApproval() public {
      require(_msgSender() == _approver, "Not allowed to approve");
       require(!isApproved, "Approval already given");
       isApproved = true;
    }

    /**
     * @dev Remove approval
     */
    function removeApproval() public {
      require(_msgSender() == _approver, "Not allowed to approve");
       require(isApproved, "No approval given");
       isApproved = false;
    }

    /**
     * @dev Transfers approver of the contract to a new account (`newApprover`).
     * Can only be called by the current owner.
     */
    function transferApprover(address newApprover) public onlyApprover {
        _transferApprover(newApprover);
    }

    /**
     * @dev Transfers approver of the contract to a new account (`newApprover`).
     */
    function _transferApprover(address newApprover) internal {
        require(newApprover != address(0), 'New approver is the zero address');
        emit NewApprover(_approver, newApprover);
        _approver = newApprover;
    }
}