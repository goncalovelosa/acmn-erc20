// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2 as console} from "forge-std/Script.sol";
import {ACMNToken} from "src/ACMNToken.sol";

/**
 * @title DeployTokenScript
 * @notice Foundry script to deploy `ACMNToken` using environment variables.
 *
 * Required environment variables:
 * - PRIVATE_KEY: Deployer's private key (hex or decimal). The deployer will hold DEFAULT_ADMIN_ROLE, MINTER_ROLE, and PAUSER_ROLE.
 * - TOKEN_NAME: ERC20 name, e.g. "ACMN Token".
 * - TOKEN_SYMBOL: ERC20 symbol, e.g. "ACMN".
 * - TOKEN_DECIMALS: ERC20 decimals, e.g. 18.
 * - TOKEN_CAP: Max supply in smallest units, e.g. 1000000e18.
 * - TOKEN_INITIAL_SUPPLY: Initial supply to mint to the initial admin (deployer) in smallest units.
 */
contract DeployTokenScript is Script {
    function run() external returns (ACMNToken token) {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        string memory name_ = vm.envString("TOKEN_NAME");
        string memory symbol_ = vm.envString("TOKEN_SYMBOL");
        uint8 decimals_ = uint8(vm.envUint("TOKEN_DECIMALS"));
        uint256 cap_ = vm.envUint("TOKEN_CAP");
        uint256 initialSupply_ = vm.envUint("TOKEN_INITIAL_SUPPLY");

        address admin_ = vm.addr(pk);

        vm.startBroadcast(pk);
        token = new ACMNToken(name_, symbol_, decimals_, cap_, initialSupply_, admin_);
        vm.stopBroadcast();

        console.log("ACMNToken deployed at:", address(token));
        console.log("Admin/Deployer:", admin_);
    }
}
