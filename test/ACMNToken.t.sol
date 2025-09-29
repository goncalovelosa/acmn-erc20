// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {console2 as console} from "forge-std/console2.sol";
import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {ERC20Capped} from "openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Capped.sol";
import {Pausable} from "openzeppelin-contracts/contracts/utils/Pausable.sol";
import {AccessControl} from "openzeppelin-contracts/contracts/access/AccessControl.sol";
import {IAccessControl} from "openzeppelin-contracts/contracts/access/IAccessControl.sol";
import {IERC20Errors} from "openzeppelin-contracts/contracts/interfaces/draft-IERC6093.sol";

import {ACMNToken, LengthMismatch, CommunityZeroAddress, CommunityNotSet, RescueSelf, RescueZeroRecipient} from "src/ACMNToken.sol";

uint8 constant DECIMALS = 18;
uint256 constant CAP = 1_000_000e18; // 1,000,000 tokens
uint256 constant INITIAL_SUPPLY = 100_000e18; // 100,000 tokens

contract MockERC20 is ERC20 {
    constructor() ERC20("Mock", "MOCK") {}

    function mint(address to, uint256 amt) external {
        _mint(to, amt);
    }
}

contract ACMNTokenTest is Test {
    ACMNToken token;

    address owner;
    address alice;
    address bob;
    address carol;

    event LearnerRewarded(address indexed to, uint256 amount);
    event Tipped(address indexed from, address indexed to, uint256 amount);
    event BatchTipped(address indexed from, address indexed to, uint256 amount);
    event Donated(address indexed from, address indexed to, uint256 amount);
    event CommunityWalletUpdated(address indexed previous, address indexed current);
    event TokensRescued(address indexed token, address indexed to, uint256 amount);

    // For permit tests
    uint256 userPk;
    address user;
    address spender;

    function setUp() public {
        owner = address(this);
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        carol = makeAddr("carol");

        token = new ACMNToken("ACMN Token", "ACMN", DECIMALS, CAP, INITIAL_SUPPLY, owner);

        // Setup keys for permit
        userPk = uint256(keccak256("user_private_key"));
        user = vm.addr(userPk);
        spender = makeAddr("spender");

        // Provide some tokens to user and alice for various tests
        token.mint(user, 10_000e18);
        token.mint(alice, 1_000e18);
    }

    function testInitialConfig() public {
        assertEq(token.name(), "ACMN Token");
        assertEq(token.symbol(), "ACMN");
        assertEq(token.decimals(), DECIMALS);
        assertEq(token.totalSupply(), INITIAL_SUPPLY + 11_000e18); // initial + minted to user + alice
        assertEq(token.cap(), CAP);
        // Roles: deployer should have admin, minter, and pauser roles
        assertTrue(token.hasRole(token.DEFAULT_ADMIN_ROLE(), owner));
        assertTrue(token.hasRole(token.MINTER_ROLE(), owner));
        assertTrue(token.hasRole(token.PAUSER_ROLE(), owner));
    }

    function testMintOnlyMinter() public {
        uint256 beforeBal = token.balanceOf(bob);
        token.mint(bob, 123);
        assertEq(token.balanceOf(bob), beforeBal + 123);

        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, alice, token.MINTER_ROLE()));
        token.mint(bob, 1);
        vm.stopPrank();
    }

    function testCapEnforced() public {
        uint256 remaining = CAP - token.totalSupply();
        token.mint(bob, remaining);
        assertEq(token.totalSupply(), CAP);

        vm.expectRevert(abi.encodeWithSelector(ERC20Capped.ERC20ExceededCap.selector, CAP + 1, CAP));
        token.mint(bob, 1);
    }

    function testPauseUnpauseBlocksTransfers() public {
        token.pause();
        vm.expectRevert(Pausable.EnforcedPause.selector);
        vm.prank(alice);
        token.transfer(bob, 1);

        token.unpause();
        vm.prank(alice);
        token.transfer(bob, 1);
        assertEq(token.balanceOf(bob), 1);
    }

    function testBurnAndBurnFrom() public {
        uint256 start = token.balanceOf(alice);
        vm.prank(alice);
        token.burn(100);
        assertEq(token.balanceOf(alice), start - 100);

        // Approve and burnFrom
        vm.prank(alice);
        token.approve(bob, 200);

        vm.prank(bob);
        token.burnFrom(alice, 150);
        assertEq(token.balanceOf(alice), start - 100 - 150);
        assertEq(token.allowance(alice, bob), 50);
    }

    function testBatchApprove() public {
        address[] memory spenders = new address[](2);
        spenders[0] = bob;
        spenders[1] = carol;

        vm.prank(alice);
        token.batchApprove(spenders, 777);

        assertEq(token.allowance(alice, bob), 777);
        assertEq(token.allowance(alice, carol), 777);
    }

    function testAirdropMint() public {
        address[] memory recips = new address[](2);
        uint256[] memory amts = new uint256[](2);
        recips[0] = bob;
        amts[0] = 5;
        recips[1] = carol;
        amts[1] = 7;

        uint256 totalBefore = token.totalSupply();
        token.airdropMint(recips, amts);
        assertEq(token.balanceOf(bob), 5);
        assertEq(token.balanceOf(carol), 7);
        assertEq(token.totalSupply(), totalBefore + 12);
    }

    function testAirdropMintRevertsOnLengthMismatch() public {
        address[] memory recips = new address[](2);
        uint256[] memory amts = new uint256[](1);
        recips[0] = bob;
        recips[1] = carol;
        amts[0] = 5;

        vm.expectRevert(LengthMismatch.selector);
        token.airdropMint(recips, amts);
    }

    function testAirdropTransfer() public {
        // Alice transfers to bob and carol
        address[] memory recips = new address[](2);
        uint256[] memory amts = new uint256[](2);
        recips[0] = bob;
        amts[0] = 10;
        recips[1] = carol;
        amts[1] = 20;

        uint256 startAlice = token.balanceOf(alice);
        vm.prank(alice);
        token.batchTip(recips, amts);

        assertEq(token.balanceOf(bob), 10);
        assertEq(token.balanceOf(carol), 20);
        assertEq(token.balanceOf(alice), startAlice - 30);
    }

    function testAirdropTransferRevertsOnLengthMismatch() public {
        address[] memory recips = new address[](2);
        uint256[] memory amts = new uint256[](1);
        recips[0] = bob;
        recips[1] = carol;
        amts[0] = 10;

        vm.prank(alice);
        vm.expectRevert(LengthMismatch.selector);
        token.batchTip(recips, amts);
    }

    function testRescueTokens() public {
        // Send an unrelated token to the MyToken contract, then rescue it
        MockERC20 other = new MockERC20();
        other.mint(address(token), 1000);
        uint256 before = other.balanceOf(bob);
        vm.expectEmit(true, true, false, true, address(token));
        emit TokensRescued(address(other), bob, 1000);
        token.rescueTokens(address(other), bob, 1000);
        assertEq(other.balanceOf(bob), before + 1000);
    }

    function testRescueTokensRevertsOnSelf() public {
        vm.expectRevert(RescueSelf.selector);
        token.rescueTokens(address(token), bob, 1);
    }

    function testRescueTokensRevertsOnZeroTo() public {
        MockERC20 other = new MockERC20();
        other.mint(address(token), 1);
        vm.expectRevert(RescueZeroRecipient.selector);
        token.rescueTokens(address(other), address(0), 1);
    }

    function testPermitSetsAllowanceAndTransferFromWorks() public {
        // Prepare permit data
        uint256 nonce = token.nonces(user);
        uint256 value = 1234;
        uint256 deadline = block.timestamp + 1 days;

        bytes32 PERMIT_TYPEHASH =
            keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
        bytes32 structHash = keccak256(abi.encode(PERMIT_TYPEHASH, user, spender, value, nonce, deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", token.DOMAIN_SEPARATOR(), structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPk, digest);

        // Call permit
        token.permit(user, spender, value, deadline, v, r, s);
        assertEq(token.allowance(user, spender), value);

        // Spend part of it
        token.mint(user, 10_000); // ensure user has funds
        vm.prank(spender);
        token.transferFrom(user, spender, 1000);
        assertEq(token.balanceOf(spender), 1000);
        assertEq(token.allowance(user, spender), value - 1000);
    }

    function testGrantRoleEnablesMint() public {
        // alice initially lacks MINTER_ROLE
        assertFalse(token.hasRole(token.MINTER_ROLE(), alice));

        // Admin grants MINTER_ROLE to alice
        token.grantRole(token.MINTER_ROLE(), alice);
        assertTrue(token.hasRole(token.MINTER_ROLE(), alice));

        // Alice can now mint
        uint256 beforeBal = token.balanceOf(bob);
        vm.prank(alice);
        token.mint(bob, 42);
        assertEq(token.balanceOf(bob), beforeBal + 42);
    }

    function testRevokeRolePreventsMint() public {
        // Grant then revoke MINTER_ROLE to alice
        token.grantRole(token.MINTER_ROLE(), alice);
        assertTrue(token.hasRole(token.MINTER_ROLE(), alice));
        token.revokeRole(token.MINTER_ROLE(), alice);
        assertFalse(token.hasRole(token.MINTER_ROLE(), alice));

        // Alice can no longer mint
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, alice, token.MINTER_ROLE()));
        token.mint(bob, 1);
        vm.stopPrank();
    }

    function testRenounceRoleRemovesPrivileges() public {
        // Grant MINTER_ROLE to alice
        token.grantRole(token.MINTER_ROLE(), alice);
        assertTrue(token.hasRole(token.MINTER_ROLE(), alice));

        // Alice renounces her own role
        bytes32 role = token.MINTER_ROLE();
        vm.startPrank(alice);
        token.renounceRole(role, alice);
        vm.stopPrank();
        assertFalse(token.hasRole(token.MINTER_ROLE(), alice));

        // Alice can no longer mint
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, alice, token.MINTER_ROLE()));
        token.mint(bob, 1);
        vm.stopPrank();
    }

    function testGrantPauserRoleAllowsPause() public {
        // Ensure alice cannot pause initially
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, alice, token.PAUSER_ROLE()));
        token.pause();
        vm.stopPrank();

        // Grant PAUSER_ROLE to alice and pause/unpause
        token.grantRole(token.PAUSER_ROLE(), alice);
        assertTrue(token.hasRole(token.PAUSER_ROLE(), alice));

        vm.prank(alice);
        token.pause();
        assertTrue(token.paused());

        vm.prank(alice);
        token.unpause();
        assertFalse(token.paused());
    }

    // ===== New educational feature tests =====

    function testRewardMintsAndIncreasesBalance() public {
        uint256 before = token.balanceOf(bob);
        vm.expectEmit(true, true, false, true, address(token));
        emit LearnerRewarded(bob, 55);
        token.reward(bob, 55);
        assertEq(token.balanceOf(bob), before + 55);
    }

    function testTipTransfersFromCaller() public {
        // Give Alice tokens to tip from
        token.mint(alice, 200);
        uint256 beforeA = token.balanceOf(alice);
        uint256 beforeB = token.balanceOf(bob);
        vm.prank(alice);
        vm.expectEmit(true, true, false, true, address(token));
        emit Tipped(alice, bob, 60);
        token.tip(bob, 60);
        assertEq(token.balanceOf(alice), beforeA - 60);
        assertEq(token.balanceOf(bob), beforeB + 60);
    }

    function testBatchTipTransfersToMany() public {
        // Fund Alice
        token.mint(alice, 1000);
        address[] memory recips = new address[](2);
        uint256[] memory amts = new uint256[](2);
        recips[0] = bob; amts[0] = 100;
        recips[1] = carol; amts[1] = 200;
        uint256 beforeA = token.balanceOf(alice);
        vm.prank(alice);
        vm.expectEmit(true, true, false, true, address(token));
        emit BatchTipped(alice, bob, 100);
        vm.expectEmit(true, true, false, true, address(token));
        emit BatchTipped(alice, carol, 200);
        token.batchTip(recips, amts);
        assertEq(token.balanceOf(bob), 100);
        assertEq(token.balanceOf(carol), 200);
        assertEq(token.balanceOf(alice), beforeA - 300);
    }

    function testDonateRequiresCommunityWallet() public {
        vm.expectRevert(CommunityNotSet.selector);
        token.donate(1);
    }

    function testSetCommunityWalletAndDonate() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit CommunityWalletUpdated(address(0), carol);
        token.setCommunityWallet(carol);
        token.mint(alice, 500);
        uint256 beforeC = token.balanceOf(carol);
        vm.prank(alice);
        vm.expectEmit(true, true, false, true, address(token));
        emit Donated(alice, carol, 120);
        token.donate(120);
        assertEq(token.balanceOf(carol), beforeC + 120);
    }

    function testFreezeUnfreezeSynonyms() public {
        // Pause
        token.pause();
        vm.prank(alice);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        token.transfer(bob, 1);
        // Unpause
        token.unpause();
        vm.prank(alice);
        token.transfer(bob, 1);
        assertEq(token.balanceOf(bob), 1);
    }

    function testFreezeUnfreezeUnauthorizedReverts() public {
        // Unauthorized pause
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, alice, token.PAUSER_ROLE()));
        token.pause();
        vm.stopPrank();

        // Unauthorized unpause
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, alice, token.PAUSER_ROLE()));
        token.unpause();
        vm.stopPrank();
    }

    function testAirdropToClassMintsToMany() public {
        address[] memory recips = new address[](2);
        uint256[] memory amts = new uint256[](2);
        recips[0] = bob; amts[0] = 11;
        recips[1] = carol; amts[1] = 22;
        uint256 totalBefore = token.totalSupply();
        token.airdropMint(recips, amts);
        assertEq(token.balanceOf(bob), 11);
        assertEq(token.balanceOf(carol), 22);
        assertEq(token.totalSupply(), totalBefore + 33);
    }

    function testSetCommunityWalletZeroAddressReverts() public {
        vm.expectRevert(CommunityZeroAddress.selector);
        token.setCommunityWallet(address(0));
    }

    function testTipInsufficientBalanceReverts() public {
        // Carol has zero balance in fresh fixture
        vm.startPrank(carol);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, carol, 0, 1));
        token.tip(bob, 1);
        vm.stopPrank();
    }

    function testTipRevertsWhenPaused() public {
        token.mint(alice, 100);
        token.pause();
        vm.startPrank(alice);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        token.tip(bob, 1);
        vm.stopPrank();
    }

    function testDonateRevertsWhenPaused() public {
        token.setCommunityWallet(carol);
        token.mint(alice, 100);
        token.pause();
        vm.startPrank(alice);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        token.donate(1);
        vm.stopPrank();
    }

    function testFuzzAirdropMintWithinCap(address[] memory recipientsSeed, uint256[] memory amountsSeed) public {
        uint256 capRemaining = token.cap() - token.totalSupply();
        vm.assume(capRemaining > 0);

        uint256 len = bound(recipientsSeed.length, 1, 16);
        address[] memory recipients = new address[](len);
        uint256[] memory amounts = new uint256[](len);

        uint256 totalToMint;
        for (uint256 i = 0; i < len; i++) {
            address seed = i < recipientsSeed.length
                ? recipientsSeed[i]
                : address(uint160(uint256(keccak256(abi.encodePacked("recip", i, recipientsSeed.length)))));
            if (seed == address(0)) {
                seed = address(uint160(i + 1));
            }
            recipients[i] = seed;

            uint256 budgetLeft = capRemaining - totalToMint;
            if (budgetLeft == 0) {
                amounts[i] = 0;
                continue;
            }

            uint256 amountSeed = i < amountsSeed.length
                ? amountsSeed[i]
                : uint256(keccak256(abi.encodePacked("amt", i, amountsSeed.length)));
            uint256 bounded = amountSeed % (budgetLeft + 1);
            amounts[i] = bounded;
            totalToMint += bounded;
        }

        if (totalToMint == 0) {
            amounts[0] = 1;
            totalToMint = 1;
        }

        uint256 beforeSupply = token.totalSupply();
        token.airdropMint(recipients, amounts);
        assertEq(token.totalSupply(), beforeSupply + totalToMint);
    }

    function testFuzzBatchTransferMatchesSum(uint96 mintAmountSeed, uint8 countSeed) public {
        uint256 count = bound(uint256(countSeed), 1, 8);
        uint256 capRemaining = token.cap() - token.totalSupply();
        vm.assume(capRemaining > 0);

        uint256 totalToDistribute = bound(uint256(mintAmountSeed), count, capRemaining);

        address[] memory recips = new address[](count);
        uint256[] memory amts = new uint256[](count);

        uint256 baseAmount = totalToDistribute / count;
        uint256 remainder = totalToDistribute % count;

        for (uint256 i = 0; i < count; i++) {
            address derived = address(uint160(uint256(keccak256(abi.encodePacked("recipient", i, mintAmountSeed, countSeed)))));
            if (derived == address(0)) {
                derived = address(uint160(i + 1));
            }
            recips[i] = derived;

            amts[i] = baseAmount;
            if (remainder > 0) {
                amts[i] += 1;
                remainder -= 1;
            }
        }

        uint256 expectedTotal;
        for (uint256 i = 0; i < count; i++) {
            expectedTotal += amts[i];
        }

        token.mint(alice, expectedTotal);
        vm.prank(alice);
        token.batchTip(recips, amts);

        uint256 distributed;
        for (uint256 i = 0; i < count; i++) {
            distributed += token.balanceOf(recips[i]);
        }

        assertEq(distributed, expectedTotal);
    }
}

contract ACMNTokenInvariantTest is StdInvariant, Test {
    ACMNToken public token;
    BatchHandler public handler;

    function setUp() public {
        token = new ACMNToken("ACMN Token", "ACMN", DECIMALS, CAP, INITIAL_SUPPLY, address(this));
        handler = new BatchHandler(token);
        token.grantRole(token.MINTER_ROLE(), address(handler));
        targetContract(address(handler));
    }

    function invariant_totalSupplyNeverExceedsCap() public {
        assertLe(token.totalSupply(), token.cap());
    }

    function invariant_balancesSumEqualsTotalSupply() public{
        // Sum balances of all addresses that can hold tokens in our invariant scenario
        // - address(this) (admin / deployer)
        // - handler (mints to self before distributing)
        // - recipients A, B, C
        // - community wallet if set (we set recipientC as community wallet in handler)
        uint256 sum;
        sum += token.balanceOf(address(this));
        sum += token.balanceOf(address(handler));
        sum += token.balanceOf(handler.recipientA());
        sum += token.balanceOf(handler.recipientB());
        sum += token.balanceOf(handler.recipientC());
        address cw = token.communityWallet();
        if (cw != address(0)) {
            sum += token.balanceOf(cw);
        }
        assertEq(sum, token.totalSupply());
    }
}

contract BatchHandler {
    ACMNToken public token;

    address public constant recipientA = address(0xA11CE);
    address public constant recipientB = address(0xB0B);
    address public constant recipientC = address(0xCAFE);

    constructor(ACMNToken _token) {
        token = _token;
    }

    function doAirdropMint(uint128 amountSeed) external {
        uint256 capRemaining = token.cap() - token.totalSupply();
        if (capRemaining == 0) {
            return;
        }

        uint256 amount = uint256(amountSeed) % (capRemaining + 1);
        if (amount == 0) {
            return;
        }

        address[] memory recips = new address[](3);
        uint256[] memory amts = new uint256[](3);

        recips[0] = recipientA;
        recips[1] = recipientB;
        recips[2] = recipientC;

        uint256 perRecipient = amount / 3;
        uint256 remainder = amount - (perRecipient * 3);

        amts[0] = perRecipient + (remainder > 0 ? 1 : 0);
        amts[1] = perRecipient + (remainder > 1 ? 1 : 0);
        amts[2] = perRecipient;

        token.airdropMint(recips, amts);
    }

    function doBatchTip(uint112 amountSeed) external {
        uint256 capRemaining = token.cap() - token.totalSupply();
        if (capRemaining == 0) {
            return;
        }

        uint256 amount = uint256(amountSeed) % (capRemaining + 1);
        if (amount == 0) {
            return;
        }

        token.mint(address(this), amount);

        address[] memory recips = new address[](2);
        uint256[] memory amts = new uint256[](2);

        recips[0] = recipientA;
        recips[1] = recipientB;

        amts[0] = amount / 2;
        amts[1] = amount - amts[0];

        token.batchTip(recips, amts);
    }

    function doDonate(uint104 amountSeed) external {
        uint256 capRemaining = token.cap() - token.totalSupply();
        if (capRemaining == 0) {
            return;
        }

        uint256 amount = uint256(amountSeed) % (capRemaining + 1);
        if (amount == 0) {
            return;
        }

        if (token.communityWallet() == address(0)) {
            token.setCommunityWallet(recipientC);
        }

        token.mint(address(this), amount);
        token.donate(amount);
    }
}
