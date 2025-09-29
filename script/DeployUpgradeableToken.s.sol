// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2 as console} from "forge-std/Script.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ACMNTokenUpgradeable} from "src/ACMNTokenUpgradeable.sol";

/**
 * @title DeployUpgradeableTokenScript
 * @notice Deploys ACMNTokenUpgradeable behind an ERC1967Proxy using UUPS pattern.
 *
 * Env vars:
 * - PRIVATE_KEY
 * - TOKEN_NAME (e.g., "ACMN Token")
 * - TOKEN_SYMBOL (e.g., "ACMN")
 * - TOKEN_DECIMALS (e.g., 18)
 * - TOKEN_CAP (e.g., 1000000e18)
 * - TOKEN_INITIAL_SUPPLY (e.g., 100000e18)
 * - TRUSTED_FORWARDER (e.g., 0x0000000000000000000000000000000000000000 to disable)
 */
contract DeployUpgradeableTokenScript is Script {
    function run() external returns (address proxyAddr, address implAddr) {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        string memory name_ = vm.envString("TOKEN_NAME");
        string memory symbol_ = vm.envString("TOKEN_SYMBOL");
        uint8 decimals_ = uint8(vm.envUint("TOKEN_DECIMALS"));
        uint256 cap_ = vm.envUint("TOKEN_CAP");
        uint256 initialSupply_ = vm.envUint("TOKEN_INITIAL_SUPPLY");
        address admin_ = vm.addr(pk);
        address trustedForwarder_ = vm.envAddress("TRUSTED_FORWARDER");

        vm.startBroadcast(pk);
        // 1) Deploy implementation
        ACMNTokenUpgradeable impl = new ACMNTokenUpgradeable();
        implAddr = address(impl);

        // 2) Prepare initializer call data
        bytes memory initData = abi.encodeCall(
            ACMNTokenUpgradeable.initialize,
            (name_, symbol_, decimals_, cap_, initialSupply_, admin_, trustedForwarder_)
        );

        // 3) Deploy proxy pointing to implementation
        ERC1967Proxy proxy = new ERC1967Proxy(implAddr, initData);
        proxyAddr = address(proxy);

        console.log("ACMNTokenUpgradeable Impl:", implAddr);
        console.log("ACMNTokenUpgradeable Proxy:", proxyAddr);
        console.log("Admin/Deployer:", admin_);
        vm.stopBroadcast();
    }
}
