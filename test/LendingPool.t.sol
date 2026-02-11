// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {LendingPoolETH} from "../src/LendingPoolETH.sol";
import {LendingPoolBase} from "../src/LendingPoolBase.sol";

contract LendingPoolTest is Test {
    LendingPoolETH public pool;

    address public alice = address(0x1);
    address public bob = address(0x2);

    function setUp() public {
        pool = new LendingPoolETH();
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
    }

    function test_Deposit() public {
        vm.prank(alice);
        pool.deposit{value: 10 ether}();

        assertEq(pool.supplyBalance(alice), 10 ether);
        assertEq(pool.totalSupply(), 10 ether);
        assertEq(address(pool).balance, 10 ether);
    }

    function test_Withdraw() public {
        vm.prank(alice);
        pool.deposit{value: 10 ether}();

        vm.prank(alice);
        pool.withdraw(5 ether);

        assertEq(pool.supplyBalance(alice), 5 ether);
        assertEq(pool.totalSupply(), 5 ether);
        assertEq(alice.balance, 95 ether);
    }

    function test_Borrow() public {
        vm.prank(alice);
        pool.deposit{value: 10 ether}();

        vm.prank(alice);
        pool.borrow(5 ether); // 80% of 10 = 8 max

        assertEq(pool.borrowBalance(alice), 5 ether);
        assertEq(pool.totalBorrowed(), 5 ether);
        assertEq(alice.balance, 95 ether);
    }

    function test_Repay() public {
        vm.prank(alice);
        pool.deposit{value: 10 ether}();

        vm.prank(alice);
        pool.borrow(5 ether);

        vm.prank(alice);
        pool.repay{value: 3 ether}();

        assertEq(pool.borrowBalance(alice), 2 ether);
        assertEq(pool.totalBorrowed(), 2 ether);
    }

    function test_CannotBorrowMoreThanCollateral() public {
        vm.prank(alice);
        pool.deposit{value: 10 ether}();

        vm.prank(alice);
        vm.expectRevert(LendingPoolBase.InsufficientCollateral.selector);
        pool.borrow(9 ether); // 80% of 10 = 8 max
    }

    function test_CannotWithdrawMoreThanSupply() public {
        vm.prank(alice);
        pool.deposit{value: 10 ether}();

        vm.prank(alice);
        pool.borrow(5 ether);

        vm.prank(alice);
        vm.expectRevert(LendingPoolBase.InsufficientLiquidity.selector);
        pool.withdraw(6 ether); // only 5 ether available
    }

    function testFuzz_DepositWithdraw(uint256 depositAmount, uint256 withdrawAmount) public {
        depositAmount = bound(depositAmount, 1, 50 ether);
        vm.prank(alice);
        pool.deposit{value: depositAmount}();

        withdrawAmount = bound(withdrawAmount, 1, depositAmount);
        vm.prank(alice);
        pool.withdraw(withdrawAmount);

        assertEq(pool.supplyBalance(alice), depositAmount - withdrawAmount);
        assertEq(alice.balance, 100 ether - depositAmount + withdrawAmount);
    }
}
