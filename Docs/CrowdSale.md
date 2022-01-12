# Crowdsale Description

This contract performs the crowdsale processing.

There are three phases. 
* VIP
* SeedSale
* PrivateSale

Wallets have to be whitelisted, in order to participate.
In all phases, the same maximum purchase amount of tokens applies. A wallet can only participate in one of these phases. 

* Purchased tokens cannot be refunded. 
* Tokens can be purchased up to the maximum purchase amount.


## Owner permissions:
The owner of the contract has the following permissions:
* Change the selling price of the token
* Whithdraw BNB balance
* Change the phase of the crowdsale campaign
* Add addresses to the whitelist
* Remove addresses from the whitelist
* Link crowdsale contract with token contract
* Destroy the contract after the final token has launched



