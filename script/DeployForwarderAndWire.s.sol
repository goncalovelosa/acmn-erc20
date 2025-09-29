// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2 as console} from "forge-std/Script.sol";
import {ERC2771ForwarderUpgradeable as OZForwarder} from "openzeppelin-contracts-upgradeable/contracts/metatx/ERC2771ForwarderUpgradeable.sol";
import {ACMNTokenUpgradeable} from "src/ACMNTokenUpgradeable.sol";

/**
 * @title DeployForwarderAndWire
 * @notice Deploys an OpenZeppelin ERC2771ForwarderUpgradeable and wires it to an existing
 *         ACMNTokenUpgradeable proxy by calling setTrustedForwarder.
 *
 * Env vars:
 * - PRIVATE_KEY          (deployer/admin)
 * - PROXY_ADDR           (address of deployed token proxy)
 *
 * Notes:
 * - The forwarder name is set to "ACMN Forwarder" (EIP-712 domain name); change here if needed.
 */
contract DeployForwarderAndWire is Script {
    function run() external returns (address forwarderAddr) {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address proxyAddr = vm.envAddress("PROXY_ADDR");

        vm.startBroadcast(pk);

        // 1) Deploy and initialize the forwarder (upgradeable-style contract used directly)
        OZForwarder fwd = new OZForwarder();
        fwd.initialize("ACMN Forwarder");
        forwarderAddr = address(fwd);

        // 2) Wire token to trust this forwarder
        ACMNTokenUpgradeable token = ACMNTokenUpgradeable(payable(proxyAddr));
        token.setTrustedForwarder(forwarderAddr);

        console.log("ERC2771ForwarderUpgradeable:", forwarderAddr);
        console.log("Token proxy wired (trusted forwarder set):", proxyAddr);

        vm.stopBroadcast();
    }
}
