// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

// OpenZeppelin Imports (v5.1.0)
import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {ERC20Permit} from "openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {ERC20Pausable} from "openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Pausable.sol";
import {ERC20Capped} from "openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Capped.sol";
import {AccessControl} from "openzeppelin-contracts/contracts/access/AccessControl.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

// ---- Custom Errors (gas-optimized reverts) ----
error OwnerZeroAddress();
error LengthMismatch();
error CommunityZeroAddress();
error CommunityNotSet();
error RescueSelf();
error RescueZeroRecipient();

/**
 * @title ACMNToken (Educational ERC20 Demo)
 * @notice Friendly, demo-focused token designed for workshops and community sessions (e.g., ACMN).
 *         It keeps the strong security foundations from OpenZeppelin while exposing
 *         easy-to-understand actions like "reward", "tip", "donate", and "freeze".
 *
 * What you can do:
 * - Reward someone (mint new tokens to say "thanks" or "great job").
 * - Tip friends or supporters using your balance.
 * - Donate to a community wallet.
 * - Pause (freeze) and unpause (unfreeze) the token in case of emergencies.
 *
 * Under the hood (short version):
 * - Standard ERC20 (name, symbol, decimals), capped supply, burnable, and permit (gasless approvals).
 * - Roles control who can mint and who can pause (MINTER_ROLE, PAUSER_ROLE, DEFAULT_ADMIN_ROLE).
 * - Built with OpenZeppelin v5.
 */
contract ACMNToken is ERC20, ERC20Burnable, ERC20Permit, ERC20Pausable, ERC20Capped, AccessControl {
    /// @notice Role that allows minting new tokens.
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    /// @notice Role that allows pausing and unpausing transfers.
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /// @dev Token decimals value (ERC20 default is 18). Stored immutably and returned by `decimals()`.
    uint8 private immutable _tokenDecimals;

    /// @notice Optional community wallet for donations (set by admin).
    address public communityWallet;

    /// @notice Emitted when a learner/supporter is rewarded (minted tokens).
    event LearnerRewarded(address indexed to, uint256 amount);
    /// @notice Emitted when someone tips another user (transfer).
    event Tipped(address indexed from, address indexed to, uint256 amount);
    /// @notice Emitted on each recipient in a batch tip.
    event BatchTipped(address indexed from, address indexed to, uint256 amount);
    /// @notice Emitted when someone donates to the community wallet.
    event Donated(address indexed from, address indexed to, uint256 amount);
    /// @notice Emitted when the community wallet is updated by an admin.
    event CommunityWalletUpdated(address indexed previous, address indexed current);
    /// @notice Emitted when unrelated tokens are rescued by an admin.
    event TokensRescued(address indexed token, address indexed to, uint256 amount);

    /**
     * @notice Deploy the token.
     * @param name_ Token name.
     * @param symbol_ Token symbol.
     * @param decimals_ Token decimals for UI/UX representation (does not affect math besides display).
     * @param cap_ Max total supply (in smallest units, respecting `decimals_`). Cannot be 0.
     * @param initialSupply Initial supply to mint to `initialOwner` (in smallest units). Can be 0.
     * @param initialOwner The account that will receive the initial supply and be set as contract owner.
     *
     * Recommendations:
     * - Keep `cap_` >= `initialSupply`.
     * - Treat `initialSupply` and `cap_` as smallest units considering `decimals_`.
     */
    constructor(
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        uint256 cap_,
        uint256 initialSupply,
        address initialOwner
    ) ERC20(name_, symbol_) ERC20Permit(name_) ERC20Capped(cap_) {
        if (initialOwner == address(0)) revert OwnerZeroAddress();

        _tokenDecimals = decimals_;

        // Set up roles: initial admin also receives MINTER and PAUSER roles.
        _grantRole(DEFAULT_ADMIN_ROLE, initialOwner);
        _grantRole(MINTER_ROLE, initialOwner);
        _grantRole(PAUSER_ROLE, initialOwner);

        if (initialSupply > 0) {
            // Mint initial supply to the owner. This is subject to the cap via _update/Cap check.
            _mint(initialOwner, initialSupply);
        }
    }

    // ======== Role-Gated Admin Functions ========

    /// @notice Pause all token transfers.
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /// @notice Unpause all token transfers.
    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    /// @notice Freeze token transfers (same as pause) with a friendlier name for demos.
    function freezeTransfers() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /// @notice Unfreeze token transfers (same as unpause) with a friendlier name for demos.
    function unfreezeTransfers() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    /// @notice Mint new tokens to an address. Respects the total supply `cap`.
    /// @param to Recipient address.
    /// @param amount Amount to mint (smallest units).
    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }

    /// @notice Mint tokens to many recipients in one transaction. Respects the `cap`.
    /// @dev Gas usage grows linearly with array length. Consider keeping batches small to avoid hitting block gas limits.
    /// @param recipients Array of recipient addresses.
    /// @param amounts Array of amounts (smallest units). Must match recipients length.
    function airdropMint(address[] calldata recipients, uint256[] calldata amounts) external onlyRole(MINTER_ROLE) {
        uint256 len = recipients.length;
        if (len != amounts.length) revert LengthMismatch();
        for (uint256 i = 0; i < len; i++) {
            _mint(recipients[i], amounts[i]);
        }
    }

    /// @notice Reward multiple learners at once (alias of airdropMint) — educational name.
    /// @dev Gas usage grows linearly with array length. Consider keeping batches small to avoid hitting block gas limits.
    function airdropToClass(address[] calldata recipients, uint256[] calldata amounts) external onlyRole(MINTER_ROLE) {
        uint256 len = recipients.length;
        if (len != amounts.length) revert LengthMismatch();
        for (uint256 i = 0; i < len; i++) {
            _mint(recipients[i], amounts[i]);
        }
    }

    /// @notice Reward a learner or community member with fresh tokens (mint).
    function reward(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        _mint(to, amount);
        emit LearnerRewarded(to, amount);
    }

    // ======== User Convenience Functions ========

    /// @notice Transfer tokens to many recipients from the caller in one transaction.
    /// @dev Uses standard ERC20 `transfer` under the hood. Gas usage grows linearly with array length; prefer small batches.
    /// @param recipients Array of recipient addresses.
    /// @param amounts Array of amounts (smallest units). Must match recipients length.
    function airdropTransfer(address[] calldata recipients, uint256[] calldata amounts) external {
        uint256 len = recipients.length;
        if (len != amounts.length) revert LengthMismatch();
        for (uint256 i = 0; i < len; i++) {
            transfer(recipients[i], amounts[i]);
        }
    }

    /// @notice Approve many spenders with the same allowance from the caller in one transaction.
    /// @param spenders Array of spender addresses.
    /// @param amount Allowance amount to set (smallest units).
    function batchApprove(address[] calldata spenders, uint256 amount) external {
        uint256 len = spenders.length;
        for (uint256 i = 0; i < len; i++) {
            _approve(_msgSender(), spenders[i], amount);
        }
    }

    /// @notice Tip someone using your existing balance.
    function tip(address to, uint256 amount) external {
        transfer(to, amount);
        emit Tipped(_msgSender(), to, amount);
    }

    /// @notice Tip many people at once using your existing balance.
    /// @dev Gas usage grows linearly with array length; prefer small batches to stay within block limits.
    function batchTip(address[] calldata recipients, uint256[] calldata amounts) external {
        uint256 len = recipients.length;
        if (len != amounts.length) revert LengthMismatch();
        for (uint256 i = 0; i < len; i++) {
            transfer(recipients[i], amounts[i]);
            emit BatchTipped(_msgSender(), recipients[i], amounts[i]);
        }
    }

    /// @notice Set a community wallet that can receive donations from anyone.
    function setCommunityWallet(address newWallet) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newWallet == address(0)) revert CommunityZeroAddress();
        emit CommunityWalletUpdated(communityWallet, newWallet);
        communityWallet = newWallet;
    }

    /// @notice Donate some of your tokens to the community wallet.
    function donate(uint256 amount) external {
        if (communityWallet == address(0)) revert CommunityNotSet();
        transfer(communityWallet, amount);
        emit Donated(_msgSender(), communityWallet, amount);
    }

    /// @notice Rescue arbitrary ERC20 tokens accidentally sent to this contract (not this token).
    /// @dev Common admin pattern; avoids locking tokens.
    /// @param token Address of the token to rescue.
    /// @param to Recipient of rescued tokens.
    /// @param amount Amount to transfer.
    function rescueTokens(address token, address to, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (token == address(this)) revert RescueSelf();
        if (to == address(0)) revert RescueZeroRecipient();
        SafeERC20.safeTransfer(IERC20(token), to, amount);
        emit TokensRescued(token, to, amount);
    }

    // ======== Views ========

    /// @inheritdoc ERC20
    function decimals() public view override returns (uint8) {
        return _tokenDecimals;
    }

    // ======== Internal Overrides ========

    /// @dev Compose behaviors from Pausable and Capped using OZ v5's `_update` hook.
    function _update(address from, address to, uint256 value) internal override(ERC20, ERC20Pausable, ERC20Capped) {
        super._update(from, to, value);
    }
}
