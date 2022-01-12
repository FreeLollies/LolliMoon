// SPDX-License-Identifier: MIT

pragma solidity 0.8.7;


abstract contract Moonity {

   bool public HasLaunched;

   function balanceOf(address account) public virtual view returns (uint256);
   function TransferCrowdSaleTokens(address recipient, uint256 amount) public virtual returns(bool);
}