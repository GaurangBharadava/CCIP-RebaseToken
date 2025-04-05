// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IRebaseToken} from "./interfaces/IRebaseToken.sol";

contract Vault {
    // we have to pass the token address to this contract constructor.
    // create the deposit function that deposit Eth and mint tokens to the user
    // create withdraw function that will withdraw ETH and burn all the tokens of the user.
    // create a way to add rewards to the vault

    error Vault__redeemFailed();

    IRebaseToken private immutable i_rebaseToken;

    event Deposited(address indexed user, uint256 amount);
    event Redeemed(address indexed user, uint256 amount);

    constructor(IRebaseToken _rebaseToken) {
        i_rebaseToken = _rebaseToken;
    }

    receive() external payable {}

    function deposit() external payable {
        // 1. we need to use the amount of ETH the user has sent to mint the token to the user.
        // call get interest rate function to get interestRate.
        uint256 interestRate = i_rebaseToken.getInterestrate();
        i_rebaseToken.mint(msg.sender, msg.value, interestRate);
        emit Deposited(msg.sender, msg.value);
    }

    function redeem(uint256 _amount) external {
        if (_amount == type(uint256).max) {
            _amount = i_rebaseToken.balanceOf(msg.sender);
        }
        //1. burn the token from the user.
        i_rebaseToken.burn(msg.sender, _amount);
        //2. send the user ETH.
        (bool success,) = payable(msg.sender).call{value: _amount}("");
        if (!success) {
            revert Vault__redeemFailed();
        }
        emit Redeemed(msg.sender, _amount);
    }

    function getRebaseTokenAddress() external view returns (address) {
        return address(i_rebaseToken);
    }
}
