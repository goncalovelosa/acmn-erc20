// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2 as console} from "forge-std/Script.sol";
import {ACMNTokenUpgradeable} from "src/ACMNTokenUpgradeable.sol";
import {ACMNTokenUpgradeableV2} from "src/ACMNTokenUpgradeableV2.sol";

/**
 * @title UpgradeUpgradeableTokenScript
 * @notice Upgrades a deployed UUPS proxy of ACMNTokenUpgradeable to V2.
 *
 * Env vars:
 * - PRIVATE_KEY
 * - PROXY_ADDR (address of deployed ERC1967Proxy pointing to ACMNTokenUpgradeable)
 */
contract UpgradeUpgradeableTokenScript is Script {
    function run() external returns (address newImpl) {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address proxyAddr = vm.envAddress("PROXY_ADDR");

        vm.startBroadcast(pk);
        // 1) Deploy new implementation (V2)
        ACMNTokenUpgradeableV2 v2 = new ACMNTokenUpgradeableV2();
        newImpl = address(v2);

        // 2) Call upgradeToAndCall on the proxy (delegatecall into implementation)
        ACMNTokenUpgradeable proxy = ACMNTokenUpgradeable(payable(proxyAddr));
        proxy.upgradeToAndCall(newImpl, "");

        console.log("Upgraded proxy to V2:", proxyAddr);
        console.log("New implementation:", newImpl);
        vm.stopBroadcast();
    }
}
