// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2 as console} from "forge-std/Script.sol";
import {ACMNToken} from "src/ACMNToken.sol";

/**
 * @title DemoActions
 * @notice A friendly script that demonstrates common actions for workshops/demos:
 *         set a community wallet, reward a learner, tip someone, donate, and
 *         freeze/unfreeze transfers.
 *
 * Required env vars:
 * - PRIVATE_KEY: admin/minter/pauser key (typically the deployer)
 * - TOKEN_ADDR: deployed ACMNToken address
 *
 * Optional env vars:
 * - COMMUNITY_WALLET: address to receive donations (defaults to an address derived from the PK if not set)
 * - LEARNER_ADDR: learner address to reward (defaults to a deterministic demo address)
 */
contract DemoActions is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address tokenAddr = vm.envAddress("TOKEN_ADDR");
        ACMNToken token = ACMNToken(tokenAddr);

        address admin = vm.addr(pk);

        // Defaults for convenience in demos
        address learner;
        try vm.envAddress("LEARNER_ADDR") returns (address l) {
            learner = l;
        } catch {
            // Deterministic learner address for demo
            learner = vm.addr(uint256(keccak256("demo-learner")));
        }

        address community;
        try vm.envAddress("COMMUNITY_WALLET") returns (address cw) {
            community = cw;
        } catch {
            // Default to an address derived from the admin key for demo
            community = vm.addr(uint256(keccak256("demo-community")));
        }

        vm.startBroadcast(pk);

        // 1) Set community wallet (admin-only)
        token.setCommunityWallet(community);
        console.log("Community wallet set:", community);

        // 2) Reward a learner (minter-only)
        token.reward(learner, 50e18);
        console.log("Rewarded learner:", learner, "with 50 tokens");

        // 3) Ensure admin has some balance to tip and donate
        token.mint(admin, 10e18);

        // 4) Tip the learner (from admin balance)
        token.tip(learner, 2e18);
        console.log("Tipped learner:", learner, "with 2 tokens");

        // 5) Donate to the community wallet
        token.donate(1e18);
        console.log("Donated 1 token to community wallet");

        // 6) Freeze and unfreeze transfers (pauser-only)
        token.freezeTransfers();
        console.log("Transfers frozen");
        token.unfreezeTransfers();
        console.log("Transfers unfrozen");

        vm.stopBroadcast();

        // Read balances
        uint256 learnerBal = token.balanceOf(learner);
        uint256 adminBal = token.balanceOf(admin);
        uint256 communityBal = token.balanceOf(community);
        console.log("Balances:");
        console.log("  Learner:", learnerBal);
        console.log("  Admin:", adminBal);
        console.log("  Community:", communityBal);
    }
}
