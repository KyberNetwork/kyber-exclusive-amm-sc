// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC1155} from 'openzeppelin-contracts/contracts/token/ERC1155/IERC1155.sol';
import {IERC20} from 'openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol';
import {IERC721} from 'openzeppelin-contracts/contracts/token/ERC721/IERC721.sol';

/**
 * @title IKEMHook
 * @notice Common interface for the KEMHook contracts
 */
interface IKEMHook {
  /// @notice Thrown when trying to update with zero address
  error InvalidAddress();

  /// @notice Thrown when trying to claim tokens by non-claimable account
  error NonClaimableAccount(address account);

  /// @notice Thrown when trying to swap by non-whitelisted account
  error NonWhitelistedAccount(address account);

  /// @notice Thrown when trying to swap in exact output mode
  error ExactOutputDisabled();

  /**
   * @notice Thrown when the signature is expired
   * @param expiryTime the expiry time
   * @param currentTime the current time
   */
  error ExpiredSignature(uint256 expiryTime, uint256 currentTime);

  /// @notice Thrown when the signature is invalid
  error InvalidSignature();

  /**
   * @notice Thrown when the input amount exceeds the maximum amount
   * @param maxAmountIn the maximum input amount
   * @param amountIn the actual input amount
   */
  error ExceededMaxAmountIn(int256 maxAmountIn, int256 amountIn);

  /// @notice Thrown when the lengths of the arrays are mismatched
  error MismatchedArrayLengths();

  /// @notice Emitted when the claimable status of an account is updated
  event UpdateClaimable(address indexed account, bool status);

  /// @notice Emitted when the whitelisted status of an account is updated
  event UpdateWhitelisted(address indexed account, bool status);

  /// @notice Emitted when the quote signer is updated
  event UpdateQuoteSigner(address indexed quoteSigner);

  /// @notice Emitted when the equilibrium-gain recipient is updated
  event UpdateEgRecipient(address indexed egRecipient);

  /// @notice Emitted when a equilibrium-gain token is absorbed
  event AbsorbEgToken(bytes32 indexed poolId, address indexed token, int256 amount);

  /// @notice Emitted when some of equilibrium-gain tokens are claimed
  event ClaimEgTokens(address indexed egRecipient, address[] tokens, uint256[] amounts);

  /// @notice Emitted when some of ERC20 tokens are rescued
  event RescueERC20s(IERC20[] tokens, uint256[] amounts, address recipient);

  /// @notice Emitted when some of ERC721 tokens are rescued
  event RescueERC721s(IERC721[] tokens, uint256[] tokenIds, address recipient);

  /// @notice Emitted when some of ERC1155 tokens are rescued
  event RescueERC1155s(IERC1155[] tokens, uint256[] tokenIds, uint256[] amounts, address recipient);

  /// @notice Return the claimable status of an account
  function claimable(address) external view returns (bool);

  /// @notice Return the whitelisted status of an account
  function whitelisted(address) external view returns (bool);

  /// @notice Return the address responsible for signing the quote
  function quoteSigner() external view returns (address);

  /// @notice Return the address of the equilibrium-gain recipient
  function egRecipient() external view returns (address);

  /**
   * @notice Update the claimable status of some accounts
   * @notice Can only be called by the current owner
   * @param accounts the addresses of the accounts to update
   * @param newStatus the new status for the accounts
   */
  function updateClaimable(address[] calldata accounts, bool newStatus) external;

  /**
   * @notice Update the whitelisted status of some accounts
   * @notice Can only be called by the current owner
   * @param accounts the addresses of the accounts to update
   * @param newStatus the new status for the accounts
   */
  function updateWhitelisted(address[] calldata accounts, bool newStatus) external;

  /**
   * @notice Update the quote signer
   * @notice Can only be called by the current owner
   * @param newSigner the address of the new quote signer
   */
  function updateQuoteSigner(address newSigner) external;

  /**
   * @notice Update the equilibrium-gain recipient
   * @notice Can only be called by the current owner
   * @param newRecipient the address of the new equilibrium-gain recipient
   */
  function updateEgRecipient(address newRecipient) external;

  /**
   * @notice Claim some of equilibrium-gain tokens accrued by the hook
   * @notice Can only be called by the claimable accounts
   * @param tokens the addresses of the tokens to claim
   * @param amounts the amounts of the tokens to claim, set to 0 to claim all
   */
  function claimEgTokens(address[] calldata tokens, uint256[] calldata amounts) external;

  /**
   * @notice Rescue some of ERC20 tokens stuck in the contract
   * @notice Can only be called by the current owner
   * @param tokens the addresses of the tokens to rescue
   * @param amounts the amounts of the tokens to rescue, set to 0 to rescue all
   * @param recipient the address to send the tokens to
   */
  function rescueERC20s(
    IERC20[] calldata tokens,
    uint256[] memory amounts,
    address payable recipient
  ) external;

  /**
   * @notice Rescue some of ERC721 tokens stuck in the contract
   * @notice Can only be called by the current owner
   * @param tokens the addresses of the tokens to rescue
   * @param tokenIds the IDs of the tokens to rescue
   * @param recipient the address to send the tokens to
   */
  function rescueERC721s(IERC721[] calldata tokens, uint256[] calldata tokenIds, address recipient)
    external;

  /**
   * @notice Rescue some of ERC1155 tokens stuck in the contract
   * @notice Can only be called by the current owner
   * @param tokens the addresses of the tokens to rescue
   * @param tokenIds the IDs of the tokens to rescue
   * @param amounts the amounts of the tokens to rescue, set to 0 to rescue all
   * @param recipient the address to send the tokens to
   */
  function rescueERC1155s(
    IERC1155[] calldata tokens,
    uint256[] calldata tokenIds,
    uint256[] memory amounts,
    address recipient
  ) external;
}
