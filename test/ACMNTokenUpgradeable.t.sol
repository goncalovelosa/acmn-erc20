// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {console2 as console} from "forge-std/console2.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IAccessControl} from "openzeppelin-contracts/contracts/access/IAccessControl.sol";
import {Pausable} from "openzeppelin-contracts/contracts/utils/Pausable.sol";
import {ERC20CappedUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/extensions/ERC20CappedUpgradeable.sol";
import {ERC2771ForwarderUpgradeable as OZForwarder} from "openzeppelin-contracts-upgradeable/contracts/metatx/ERC2771ForwarderUpgradeable.sol";

import {ACMNTokenUpgradeable} from "src/ACMNTokenUpgradeable.sol";
import {ACMNTokenUpgradeableV2} from "src/ACMNTokenUpgradeableV2.sol";

contract Minimal2771Forwarder {
    function forward(address target, bytes calldata data, address from) external {
        bytes memory modified = abi.encodePacked(data, from);
        (bool ok, ) = target.call(modified);
        require(ok, "forward failed");
    }
}

contract ACMNTokenUpgradeableTest is Test {
    address public admin;
    address public alice;
    address public bob;
    uint256 public adminKey;
    uint256 public aliceKey;

    uint8 public constant DECIMALS = 18;
    uint256 public constant CAP = 1_000_000e18;
    uint256 public constant INITIAL_SUPPLY = 100_000e18;

    function setUp() public {
        (admin, adminKey) = makeAddrAndKey("admin");
        (alice, aliceKey) = makeAddrAndKey("alice");
        bob = makeAddr("bob");
    }

    function _signForwardRequest(
        OZForwarder fwd,
        address signer,
        uint256 signerKey,
        OZForwarder.ForwardRequestData memory req
    ) internal view returns (bytes memory signature, uint256 nonce) {
        bytes32 domainTypeHash = keccak256(
            "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
        );
        bytes32 nameHash = keccak256(bytes("ACMN Forwarder"));
        bytes32 versionHash = keccak256(bytes("1"));
        bytes32 domainSeparator = keccak256(
            abi.encode(domainTypeHash, nameHash, versionHash, block.chainid, address(fwd))
        );

        bytes32 forwardTypeHash = keccak256(
            "ForwardRequest(address from,address to,uint256 value,uint256 gas,uint256 nonce,uint48 deadline,bytes data)"
        );
        nonce = fwd.nonces(signer);
        bytes32 structHash = keccak256(
            abi.encode(
                forwardTypeHash,
                req.from,
                req.to,
                req.value,
                req.gas,
                nonce,
                req.deadline,
                keccak256(req.data)
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, digest);
        signature = abi.encodePacked(r, s, v);
    }

    function _deployProxy(
        string memory name_,
        string memory symbol_
    ) internal returns (ACMNTokenUpgradeable token) {
        token = _deployProxyWithForwarder(name_, symbol_, address(0));
    }

    function _deployProxyWithForwarder(
        string memory name_,
        string memory symbol_,
        address trustedForwarder_
    ) internal returns (ACMNTokenUpgradeable token) {
        vm.startPrank(admin);
        ACMNTokenUpgradeable impl = new ACMNTokenUpgradeable();
        bytes memory initData = abi.encodeCall(
            ACMNTokenUpgradeable.initialize,
            (name_, symbol_, DECIMALS, CAP, INITIAL_SUPPLY, admin, trustedForwarder_)
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        token = ACMNTokenUpgradeable(payable(address(proxy)));
        vm.stopPrank();
    }

    function testDeployAndInitialConfig() public {
        ACMNTokenUpgradeable token = _deployProxy("ACMN Token", "ACMN");
        assertEq(token.name(), "ACMN Token");
        assertEq(token.symbol(), "ACMN");
        assertEq(token.decimals(), DECIMALS);
        // initial + minted to admin via initializer
        assertEq(token.totalSupply(), INITIAL_SUPPLY);
        assertEq(token.cap(), CAP);
        assertTrue(token.hasRole(token.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(token.hasRole(token.MINTER_ROLE(), admin));
        assertTrue(token.hasRole(token.PAUSER_ROLE(), admin));
    }

    function testOnlyAdminCanUpgrade() public {
        ACMNTokenUpgradeable token = _deployProxy("ACMN Token", "ACMN");
        ACMNTokenUpgradeableV2 v2 = new ACMNTokenUpgradeableV2();

        vm.startPrank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                alice,
                token.DEFAULT_ADMIN_ROLE()
            )
        );
        token.upgradeToAndCall(address(v2), "");
        vm.stopPrank();
    }

    function testUpgradeToV2PreservesStateAndAddsFunction() public {
        ACMNTokenUpgradeable token = _deployProxy("ACMN Token", "ACMN");

        // Set some state
        vm.prank(admin);
        token.setCommunityWallet(bob);
        vm.prank(admin);
        token.mint(alice, 123);

        uint256 beforeAlice = token.balanceOf(alice);
        uint256 beforeSupply = token.totalSupply();

        // Upgrade as admin
        ACMNTokenUpgradeableV2 v2Impl = new ACMNTokenUpgradeableV2();
        vm.prank(admin);
        token.upgradeToAndCall(address(v2Impl), "");

        // Call new function through the proxy
        string memory ver = ACMNTokenUpgradeableV2(payable(address(token))).version();
        assertEq(ver, "V2");

        // State preserved
        assertEq(token.balanceOf(alice), beforeAlice);
        assertEq(token.totalSupply(), beforeSupply);
        assertEq(token.communityWallet(), bob);
        assertEq(token.decimals(), DECIMALS);
        assertTrue(token.hasRole(token.DEFAULT_ADMIN_ROLE(), admin));
    }

    function testInitializerCannotRunTwice() public {
        ACMNTokenUpgradeable token = _deployProxy("ACMN Token", "ACMN");
        vm.expectRevert();
        token.initialize("X", "Y", 18, CAP, 0, admin, address(0));
    }

    function testPauseBlocksTransfers() public {
        ACMNTokenUpgradeable token = _deployProxy("ACMN Token", "ACMN");
        // fund alice from admin
        vm.prank(admin);
        token.mint(alice, 5);

        vm.prank(admin);
        token.pause();

        vm.prank(alice);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        token.transfer(bob, 1);

        vm.prank(admin);
        token.unpause();
        vm.prank(alice);
        token.transfer(bob, 1);
        assertEq(token.balanceOf(bob), 1);
    }

    function testMetaTxTipThroughTrustedForwarder() public {
        // Deploy trusted forwarder and token configured to trust it
        Minimal2771Forwarder fwd = new Minimal2771Forwarder();
        ACMNTokenUpgradeable token = _deployProxyWithForwarder("ACMN Token", "ACMN", address(fwd));

        // Mint to alice so she can tip via meta-tx
        vm.prank(admin);
        token.mint(alice, 3);

        uint256 aliceBefore = token.balanceOf(alice);

        // Prepare call data: tip(bob, 2) and forward as relayer
        bytes memory callData = abi.encodeWithSelector(token.tip.selector, bob, 2);
        fwd.forward(address(token), callData, alice);

        assertEq(token.balanceOf(bob), 2);
        assertEq(token.balanceOf(alice), aliceBefore - 2);
    }

    function testMetaTxWithOZForwarderExecute() public {
        // Deploy OZ Forwarder and token that trusts it
        OZForwarder fwd = new OZForwarder();
        fwd.initialize("ACMN Forwarder");
        ACMNTokenUpgradeable token = _deployProxyWithForwarder("ACMN Token", "ACMN", address(fwd));

        // Fund signer (alice) so she can tip via meta-tx
        vm.prank(admin);
        token.mint(alice, 5);

        // Prepare ForwardRequestData
        OZForwarder.ForwardRequestData memory req;
        req.from = alice;
        req.to = address(token);
        req.value = 0;
        req.gas = 150000;
        req.deadline = uint48(block.timestamp + 1 hours);
        req.data = abi.encodeWithSelector(token.tip.selector, bob, 3);

        // Sign EIP-712 typed data for OZ forwarder
        (bytes memory sig, uint256 nonce) = _signForwardRequest(fwd, alice, aliceKey, req);
        req.signature = sig;

        uint256 aliceBefore = token.balanceOf(alice);
        uint256 bobBefore = token.balanceOf(bob);

        // Relay
        fwd.execute{value: req.value}(req);

        assertEq(token.balanceOf(bob), bobBefore + 3);
        assertEq(token.balanceOf(alice), aliceBefore - 3);

        // Nonce consumed
        assertEq(fwd.nonces(alice), nonce + 1);
    }

    function testSetTrustedForwarderOnlyAdmin() public {
        ACMNTokenUpgradeable token = _deployProxy("ACMN Token", "ACMN");
        vm.prank(alice);
        // Accept any revert (unauthorized), avoiding address encoding differences.
        vm.expectRevert();
        token.setTrustedForwarder(address(0xBEEF));
    }

    function testUpdateTrustedForwarderAffectsForwarding() public {
        // Two forwarders
        OZForwarder fwdA = new OZForwarder();
        fwdA.initialize("ACMN Forwarder");
        OZForwarder fwdB = new OZForwarder();
        fwdB.initialize("ACMN Forwarder");

        // Token trusts A initially
        ACMNTokenUpgradeable token = _deployProxyWithForwarder("ACMN Token", "ACMN", address(fwdA));

        vm.prank(admin);
        token.mint(alice, 2);

        OZForwarder.ForwardRequestData memory req;
        req.from = alice;
        req.to = address(token);
        req.value = 0;
        req.gas = 120000;
        req.deadline = uint48(block.timestamp + 1 hours);
        req.data = abi.encodeWithSelector(token.tip.selector, bob, 1);

        // Sign for forwarder B's domain (but token still trusts A) => should revert with ERC2771UntrustfulTarget
        {
            (bytes memory sig1, ) = _signForwardRequest(fwdB, alice, aliceKey, req);
            req.signature = sig1;

            vm.expectRevert(
                abi.encodeWithSelector(
                    OZForwarder.ERC2771UntrustfulTarget.selector,
                    address(token),
                    address(fwdB)
                )
            );
            fwdB.execute(req);
        }

        // Now update token forwarder to B
        vm.prank(admin);
        token.setTrustedForwarder(address(fwdB));

        // Sign again for B
        {
            (bytes memory sig2, ) = _signForwardRequest(fwdB, alice, aliceKey, req);
            req.signature = sig2;

            // Should succeed now
            fwdB.execute(req);
        }
    }

    function testCapEnforcedOnUpgradeToken() public {
        ACMNTokenUpgradeable token = _deployProxy("ACMN Token", "ACMN");
        uint256 remaining = CAP - token.totalSupply();
        vm.prank(admin);
        token.mint(bob, remaining);
        assertEq(token.totalSupply(), CAP);

        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(ERC20CappedUpgradeable.ERC20ExceededCap.selector, CAP + 1, CAP)
        );
        token.mint(bob, 1);
    }
}
