// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {ACMNTokenUpgradeable} from "./ACMNTokenUpgradeable.sol";

/**
 * @title ACMNTokenUpgradeableV2
 * @notice Demo V2 implementation for upgrade testing. Adds a simple version() function.
 *         Storage layout is preserved; no variables are removed or reordered.
 */
contract ACMNTokenUpgradeableV2 is ACMNTokenUpgradeable {
    function version() public pure returns (string memory) {
        return "V2";
    }
}
