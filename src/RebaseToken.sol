// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title RebaseToken
 * @author Gaurang Brdv
 * @notice This is cross-chain rebase token that rewards user to deposit into vault and gain interest in rewards.
 * @notice The interest rate in this contract can only decrease and eaxch user have their own interest rate that is the globel interest rate at the time of depositing.
 */
contract RebaseToken is ERC20, Ownable, AccessControl {
    error RebaseToken__InterestRateCanOnlyDecrease(uint256 newInterestRate, uint256 oldInterestRate);

    uint256 private s_interestRate = 5e10; // 5e10 / 1e18 = 5e-8 = 0.00000005 => 0.00000005 * 100 = 0.000005% => 0.000005% Imterest rate.
    uint256 private constant PRECISION_FACTOR = 1e18;
    bytes32 private constant MINT_AND_BURN_ROLE = keccak256("MINT_AND_BURN_ROLE");
    mapping(address => uint256) private s_userInterestRate;
    mapping(address => uint256) private s_userLastUpdatedTimestamp;

    event InterestRateChanged(uint256 indexed newInterestRate);
    constructor() ERC20("Rebase Token", "RBT") Ownable(msg.sender) {    

    }

    function grantMintAndBurnRole(address _account) external onlyOwner {
        _grantRole(MINT_AND_BURN_ROLE, _account);
    }

    /**
     * @notice This function is used to set the interest rate for the contract.
     * @param _newInterestRate The new interest rate that will be set for the contract.
     * @dev The interest rate can only decrease
     */
    function setInterestRate(uint256 _newInterestRate) external onlyOwner {
        //set the interest rate.
        if(_newInterestRate >= s_interestRate) {
            revert RebaseToken__InterestRateCanOnlyDecrease(_newInterestRate, s_interestRate);
        }
        s_interestRate = _newInterestRate;
        emit InterestRateChanged(_newInterestRate);
    }

    function principleBalanceOf(address _user) external view returns(uint256) {
        return super.balanceOf(_user);
    }

    function mint(address _to, uint256 _amount) external onlyRole(MINT_AND_BURN_ROLE) {
        _mintAccruedInterest(_to);
        s_userInterestRate[_to] = s_interestRate;
        _mint(_to, _amount);
    }

    /**
     * @notice Burn the tokens from the user when they withdraw from vault.
     * @param _from The user from the token to burn.
     * @param _amount the amount of tokens to burn.
     */
    function burn(address _from, uint256 _amount) external onlyRole(MINT_AND_BURN_ROLE) {
        if(_amount == type(uint256).max) {
            _amount = balanceOf(_from);
        }
        _mintAccruedInterest(_from);
        _burn(_from, _amount);
    }

    /**
     * @notice calculate the balance of the user including the interest.
     */
    function balanceOf(address _user) public view override returns(uint256) {
        //get the current principal balance of the user.(the numbers of thoken that have actually been minted to the user)
        //Multiply the principal balance by the interest rate.
        return super.balanceOf(_user) * _calculateUserAccumulatedInterestSinceLastUpdate(_user) / PRECISION_FACTOR;
    }

    function transfer(address _recipient, uint256 _amount) public override returns(bool) {
        _mintAccruedInterest(msg.sender);
        _mintAccruedInterest(_recipient);
        if(_amount == type(uint256).max) {
            _amount = balanceOf(msg.sender);
        }

        if(balanceOf(_recipient) == 0) {
            s_userInterestRate[_recipient] = s_userInterestRate[msg.sender];
        }
        return super.transfer(_recipient, _amount);
    }

    function transferFrom(address _sender, address _recipient, uint256 _amount) public override returns(bool) {
        _mintAccruedInterest(_sender);
        _mintAccruedInterest(_recipient);
        if(_amount == type(uint256).max) {
            _amount = balanceOf(_sender);
        }

        if(balanceOf(_recipient) == 0) {
            s_userInterestRate[_recipient] = s_userInterestRate[_sender];
        }
        return super.transferFrom(_sender, _recipient, _amount);
    }

    /**
     * @notice Calculate the interest that has accumulated since the last update.
     */
    function _calculateUserAccumulatedInterestSinceLastUpdate(address _user) internal view returns(uint256 linearInterest) {
        //we need to calculate the interest that has accumulated since the last update.
        //this is going to be linier growth with time.
        //1. calculate time since last update.
        //2. caculate the amount of linier growth.
        //(principal amount) + (principal amount * interest rate * time alaps)
        //deposit 10 tokens
        //interest rate = 0.5
        //time since last update = 2 seconds
        //10 + (10 * 0.5 * 2) = 10 + 10 = 20
        uint256 timeElapsed = block.timestamp - s_userLastUpdatedTimestamp[_user];
        linearInterest = PRECISION_FACTOR + (s_userInterestRate[_user] * timeElapsed);
    }

    /**
     * @notice Mint the accrued interest to the user since the last last time they interected with the protocol.
     */
    function _mintAccruedInterest(address _user) internal {
        //(1)find their current balance of rebase toens that have been minted to the user.
        uint256 previousPrincipalBalance = super.balanceOf(_user);
        //(2)calculate their current balance including the interest.
        uint256 currentBalance = balanceOf(_user);
        //calculate the number of tokens that needs to minted to the user -> [2] - [1].
        uint256 balanceIncreased = currentBalance - previousPrincipalBalance;
        //sets users last updated timestamp
        s_userLastUpdatedTimestamp[_user] = block.timestamp;
        //call the _mint to mint toknes to the user.
        _mint(_user, balanceIncreased);
    }

    function getUserInterestRate(address _user) external view returns(uint256) {
        return s_userInterestRate[_user];
    }

    function getInterestRate() external view returns(uint256) {
        return s_interestRate;
    }
}