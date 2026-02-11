// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {SToken} from "../src/SToken.sol";

contract STokenTest is Test {
    SToken public stoken;

    address public pool;
    address public alice;
    address public bob;

    uint256 constant ALICE_PRIVATE_KEY = 0x1;
    uint256 constant BOB_PRIVATE_KEY = 0x2;

    uint64 constant MARKET_ID = 0;

    function setUp() public {
        pool = address(this); // test contract acts as LendingPool for mint/burn
        alice = vm.addr(ALICE_PRIVATE_KEY);
        bob = vm.addr(BOB_PRIVATE_KEY);

        stoken = new SToken(
            pool,
            MARKET_ID,
            "DorkFi sUSDC",
            "sUSDC",
            6
        );
    }

    // --- Metadata ---

    function test_ConstructorSetsMetadata() public view {
        assertEq(stoken.name(), "DorkFi sUSDC");
        assertEq(stoken.symbol(), "sUSDC");
        assertEq(stoken.decimals(), 6);
        assertEq(stoken.lendingPool(), pool);
        assertEq(stoken.marketId(), MARKET_ID);
        assertEq(stoken.totalSupply(), 0);
    }

    function test_DomainSeparatorSet() public view {
        assertTrue(stoken.DOMAIN_SEPARATOR() != bytes32(0));
    }

    // --- Mint (only LendingPool) ---

    function test_Mint_OnlyPoolCanMint() public {
        stoken.mint(alice, 1000e6);
        assertEq(stoken.balanceOf(alice), 1000e6);
        assertEq(stoken.totalSupply(), 1000e6);
    }

    function test_Mint_NonPoolReverts() public {
        vm.prank(alice);
        vm.expectRevert(SToken.Unauthorized.selector);
        stoken.mint(alice, 1000e6);
    }

    function test_Mint_ZeroAmountNoOp() public {
        stoken.mint(alice, 0);
        assertEq(stoken.balanceOf(alice), 0);
        assertEq(stoken.totalSupply(), 0);
    }

    function test_Mint_EmitsTransferAndMint() public {
        vm.expectEmit(true, true, true, true);
        emit SToken.Mint(alice, 500e6);
        vm.expectEmit(true, true, true, true);
        emit SToken.Transfer(address(0), alice, 500e6);
        stoken.mint(alice, 500e6);
    }

    // --- BurnFrom (only LendingPool) ---

    function test_BurnFrom_OnlyPoolCanBurn() public {
        stoken.mint(alice, 1000e6);
        stoken.burnFrom(alice, 300e6);
        assertEq(stoken.balanceOf(alice), 700e6);
        assertEq(stoken.totalSupply(), 700e6);
    }

    function test_BurnFrom_NonPoolReverts() public {
        stoken.mint(alice, 1000e6);
        vm.prank(bob);
        vm.expectRevert(SToken.Unauthorized.selector);
        stoken.burnFrom(alice, 300e6);
    }

    function test_BurnFrom_ZeroAmountNoOp() public {
        stoken.mint(alice, 1000e6);
        stoken.burnFrom(alice, 0);
        assertEq(stoken.balanceOf(alice), 1000e6);
        assertEq(stoken.totalSupply(), 1000e6);
    }

    function test_BurnFrom_EmitsBurnAndTransfer() public {
        stoken.mint(alice, 500e6);
        vm.expectEmit(true, true, true, true);
        emit SToken.Burn(alice, 200e6);
        vm.expectEmit(true, true, true, true);
        emit SToken.Transfer(alice, address(0), 200e6);
        stoken.burnFrom(alice, 200e6);
    }

    // --- ERC-20 transfer ---

    function test_Transfer() public {
        stoken.mint(alice, 1000e6);
        vm.prank(alice);
        bool ok = stoken.transfer(bob, 400e6);
        assertTrue(ok);
        assertEq(stoken.balanceOf(alice), 600e6);
        assertEq(stoken.balanceOf(bob), 400e6);
        assertEq(stoken.totalSupply(), 1000e6);
    }

    function test_Transfer_EmitsTransfer() public {
        stoken.mint(alice, 100e6);
        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit SToken.Transfer(alice, bob, 50e6);
        stoken.transfer(bob, 50e6);
    }

    // --- ERC-20 approve / transferFrom ---

    function test_ApproveAndAllowance() public {
        vm.prank(alice);
        stoken.approve(bob, 500e6);
        assertEq(stoken.allowance(alice, bob), 500e6);
    }

    function test_TransferFrom() public {
        stoken.mint(alice, 1000e6);
        vm.prank(alice);
        stoken.approve(bob, 400e6);
        vm.prank(bob);
        bool ok = stoken.transferFrom(alice, bob, 400e6);
        assertTrue(ok);
        assertEq(stoken.balanceOf(alice), 600e6);
        assertEq(stoken.balanceOf(bob), 400e6);
        assertEq(stoken.allowance(alice, bob), 0);
    }

    function test_TransferFrom_EmitsTransfer() public {
        stoken.mint(alice, 100e6);
        vm.prank(alice);
        stoken.approve(bob, 100e6);
        vm.prank(bob);
        vm.expectEmit(true, true, true, true);
        emit SToken.Transfer(alice, bob, 100e6);
        stoken.transferFrom(alice, bob, 100e6);
    }

    // --- Permit (EIP-2612) ---

    function test_Permit_UpdatesAllowance() public {
        uint256 deadline = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(alice, bob, 300e6, deadline, ALICE_PRIVATE_KEY);
        stoken.permit(alice, bob, 300e6, deadline, v, r, s);
        assertEq(stoken.allowance(alice, bob), 300e6);
        assertEq(stoken.nonces(alice), 1);
    }

    function test_Permit_ThenTransferFrom() public {
        stoken.mint(alice, 1000e6);
        uint256 deadline = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(alice, bob, 250e6, deadline, ALICE_PRIVATE_KEY);
        stoken.permit(alice, bob, 250e6, deadline, v, r, s);
        vm.prank(bob);
        stoken.transferFrom(alice, bob, 250e6);
        assertEq(stoken.balanceOf(alice), 750e6);
        assertEq(stoken.balanceOf(bob), 250e6);
    }

    function test_Permit_ExpiredReverts() public {
        uint256 deadline = block.timestamp - 1;
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(alice, bob, 100e6, deadline, ALICE_PRIVATE_KEY);
        vm.expectRevert("Permit expired");
        stoken.permit(alice, bob, 100e6, deadline, v, r, s);
    }

    function test_Permit_InvalidSignatureReverts() public {
        uint256 deadline = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(alice, bob, 100e6, deadline, BOB_PRIVATE_KEY); // wrong signer
        vm.expectRevert("Invalid signature");
        stoken.permit(alice, bob, 100e6, deadline, v, r, s);
    }

    function test_Permit_NonceIncrements() public {
        uint256 deadline = block.timestamp + 1 hours;
        (uint8 v1, bytes32 r1, bytes32 s1) = _signPermit(alice, bob, 100e6, deadline, ALICE_PRIVATE_KEY);
        stoken.permit(alice, bob, 100e6, deadline, v1, r1, s1);
        assertEq(stoken.nonces(alice), 1);
        (uint8 v2, bytes32 r2, bytes32 s2) = _signPermit(alice, bob, 200e6, deadline, ALICE_PRIVATE_KEY); // nonce 1 used in sig
        stoken.permit(alice, bob, 200e6, deadline, v2, r2, s2);
        assertEq(stoken.nonces(alice), 2);
        assertEq(stoken.allowance(alice, bob), 200e6);
    }

    function _signPermit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint256 privateKey
    ) internal view returns (uint8 v, bytes32 r, bytes32 s) {
        uint256 nonce = stoken.nonces(owner);
        bytes32 structHash = keccak256(
            abi.encode(
                stoken.PERMIT_TYPEHASH(),
                owner,
                spender,
                value,
                nonce,
                deadline
            )
        );
        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", stoken.DOMAIN_SEPARATOR(), structHash)
        );
        (v, r, s) = vm.sign(privateKey, digest);
    }
}
