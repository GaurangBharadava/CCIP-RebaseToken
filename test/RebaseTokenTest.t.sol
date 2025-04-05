// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {RebaseToken} from "../src/RebaseToken.sol";
import {IRebaseToken} from "../src/interfaces/IRebaseToken.sol";
import {Vault} from "../src/Vault.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

contract RebaseTokenTest is Test {
    RebaseToken private rebaseToken;
    Vault private vault;

    address public owner = makeAddr("owner");
    address public user = makeAddr("user");

    function setUp() public {
        vm.startPrank(owner);
        rebaseToken = new RebaseToken();
        vault = new Vault(IRebaseToken(address(rebaseToken)));
        rebaseToken.grantMintAndBurnRole(address(vault));
        vm.stopPrank();
    }

    function addRewardsToTheVault(uint256 rewardAmount) public {
        (bool ok,) = payable(address(vault)).call{value: rewardAmount}("");
        require(ok);
    }

    function testInterestRateIsLinear(uint256 amount) public {
        amount = bound(amount, 1e5, type(uint96).max);
        //1. Deposite in the vault
        vm.startPrank(user);
        vm.deal(user, amount);
        vault.deposit{value: amount}();
        //2. check the balance of the user.
        uint256 startingBalance = rebaseToken.balanceOf(user);
        console.log("Timestamp: ", block.timestamp);
        console.log("Starting Balance: ", startingBalance);
        assertEq(startingBalance, amount);
        //3. warp the time and check the balance again.
        vm.warp(block.timestamp + 1 hours);
        uint256 middleBalance = rebaseToken.balanceOf(user);
        console.log("Middle Balance: ", middleBalance);
        assertGt(middleBalance, startingBalance);
        //4. warp the time and check the balance again.
        vm.warp(block.timestamp + 1 hours);
        uint256 endBalance = rebaseToken.balanceOf(user);
        console.log("block.timestamp", block.timestamp);
        console.log("endBalance", endBalance);
        assertGt(endBalance, middleBalance);

        assertApproxEqAbs(endBalance - middleBalance, middleBalance - startingBalance, 1);
        vm.stopPrank();
    }

    function testRedeemStraightAway(uint256 amount) public {
        amount = bound(amount, 1e5, type(uint96).max);
        //1. Deposite in the vault
        vm.startPrank(user);
        vm.deal(user, amount);
        vault.deposit{value: amount}();
        assertEq(rebaseToken.balanceOf(user), amount);
        //2. Redeem the amount
        vault.redeem(amount);
        assertEq(rebaseToken.balanceOf(user), 0);
        assertEq(address(user).balance, amount);
        vm.stopPrank();
    }

    function testRedeemAfterTimePassed(uint256 depositedAmount, uint256 time) public {
        time = bound(time, 1000, type(uint96).max);
        depositedAmount = bound(depositedAmount, 1e5, type(uint96).max);
        //1. Deposite in the vault
        vm.deal(user, depositedAmount);
        vm.prank(user);
        vault.deposit{value: depositedAmount}();
        assertEq(rebaseToken.balanceOf(user), depositedAmount);
        //2. warp the time
        vm.warp(block.timestamp + time);
        console.log("balance of user: ", rebaseToken.balanceOf(user));
        uint256 balanceAfterSomeTime = rebaseToken.balanceOf(user);
        vm.deal(owner, balanceAfterSomeTime);
        vm.prank(owner);
        addRewardsToTheVault(balanceAfterSomeTime - depositedAmount);
        //3. Redeem the amount
        vm.prank(user);
        vault.redeem(type(uint256).max);
        uint256 ethAmountBalance = address(user).balance;

        assertEq(ethAmountBalance, balanceAfterSomeTime);
        assertEq(address(user).balance, balanceAfterSomeTime);
    }

    function testTransfer(uint256 amount, uint256 amountToSend) public {
        amount = bound(amount, 1e5 + 1e5, type(uint96).max);
        amountToSend = bound(amountToSend, 1e5, amount - 1e5);
        //1. Deposite in the vault
        vm.deal(user, amount);
        vm.prank(user);
        vault.deposit{value: amount}();

        address user2 = makeAddr("user2");
        uint256 userBalance = rebaseToken.balanceOf(user);
        uint256 user2Balance = rebaseToken.balanceOf(user2);
        assertEq(userBalance, amount);
        assertEq(user2Balance, 0);

        // owner reduces the interest rate
        vm.prank(owner);
        rebaseToken.setInterestRate(4e10);
        //2. Transfer the amount
        vm.prank(user);
        rebaseToken.transfer(user2, amountToSend);
        uint256 userBalanceAfterTransfer = rebaseToken.balanceOf(user);
        uint256 user2BalanceAfterTransfer = rebaseToken.balanceOf(user2);

        assertEq(userBalanceAfterTransfer, userBalance - amountToSend);
        assertEq(user2BalanceAfterTransfer, amountToSend);

        assertEq(rebaseToken.getUserInterestRate(user), 5e10);
        assertEq(rebaseToken.getUserInterestRate(user2), 5e10);
    }

    function testNonOwnerCannotChangeInterestRate(uint256 interestRate) public {
        interestRate = bound(interestRate, 1e10, 5e10);
        vm.prank(user);
        vm.expectPartialRevert(Ownable.OwnableUnauthorizedAccount.selector);
        rebaseToken.setInterestRate(interestRate);
    }

    function testCannotCallMintAndBurn() public {
        vm.prank(user);
        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        rebaseToken.mint(user, 100, rebaseToken.getInterestRate());
        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        rebaseToken.burn(user, 100);
    }

    function testGetPrincipleAmount(uint256 amount) public {
        amount = bound(amount, 1e5, type(uint96).max);
        //1. Deposite in the vault
        vm.deal(user, amount);
        vm.prank(user);
        vault.deposit{value: amount}();
        assertEq(rebaseToken.principleBalanceOf(user), amount);

        vm.warp(block.timestamp + 1 hours);
        assertEq(rebaseToken.principleBalanceOf(user), amount);
        assertGt(rebaseToken.balanceOf(user), amount);
    }

    function testCanNotSetInterestRateHigherThenPrevious() public {
        uint256 interestRate = rebaseToken.getInterestRate();
        vm.prank(owner);
        vm.expectPartialRevert(RebaseToken.RebaseToken__InterestRateCanOnlyDecrease.selector);
        rebaseToken.setInterestRate(interestRate + 1);
    }
}
