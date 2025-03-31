// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IAccessControl} from 'openzeppelin-contracts/contracts/access/IAccessControl.sol';
import {IERC1155} from 'openzeppelin-contracts/contracts/token/ERC1155/IERC1155.sol';
import {IERC20} from 'openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol';
import {IERC721} from 'openzeppelin-contracts/contracts/token/ERC721/IERC721.sol';

/**
 * @title IKEMHook
 * @notice Common interface for the KEMHook contracts
 */
interface IKEMHook is IAccessControl {
  /// @notice Thrown when the new address to be updated is the zero address
  error InvalidAddress();

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

  /// @notice Emitted when the signer is updated
  event UpdateQuoteSigner(address indexed quoteSigner);

  /// @notice Emitted when the equilibrium-gain recipient is updated
  event UpdateEgRecipient(address indexed egRecipient);

  /// @notice Emitted when the equilibrium-gain token is absorbed
  event AbsorbEgToken(bytes32 indexed poolId, address indexed token, int256 amount);

  /// @notice Emitted when the equilibrium-gain tokens are claimed
  event ClaimEgTokens(address indexed egRecipient, address[] tokens, uint256[] amounts);

  /// @notice Emitted when ERC20 tokens are rescued
  event RescueERC20s(IERC20[] tokens, uint256[] amounts, address recipient);

  /// @notice Emitted when ERC721 tokens are rescued
  event RescueERC721s(IERC721[] tokens, uint256[] tokenIds, address recipient);

  /// @notice Emitted when ERC1155 tokens are rescued
  event RescueERC1155s(IERC1155[] tokens, uint256[] tokenIds, uint256[] amounts, address recipient);

  /// @notice Return the role identifier for those allowed to claim equilibrium-gain tokens
  function CLAIM_ROLE() external view returns (bytes32);

  /// @notice Return the role identifier for those allowed to swap tokens
  function SWAP_ROLE() external view returns (bytes32);

  /// @notice Return the address of the signer responsible for signing the quote
  function quoteSigner() external view returns (address);

  /// @notice Return the address of the equilibrium-gain recipient
  function egRecipient() external view returns (address);

  /**
   * @notice Update the quote signer
   * @notice This function can only be called by the address with the DEFAULT_ADMIN_ROLE
   * @param newSigner the new signer
   */
  function updateQuoteSigner(address newSigner) external;

  /**
   * @notice Update the equilibrium-gain recipient
   * @notice This function can only be called by the address with the DEFAULT_ADMIN_ROLE
   * @param newRecipient the new equilibrium-gain recipient
   */
  function updateEgRecipient(address newRecipient) external;

  /**
   * @notice Claim equilibrium-gain tokens accrued by the hook
   * @notice This function can only be called by the address with the CLAIM_ROLE
   * @param tokens the addresses of the tokens to claim
   * @param amounts the amounts of the tokens to claim, set to 0 to claim all
   */
  function claimEgTokens(address[] calldata tokens, uint256[] calldata amounts) external;

  /**
   * @notice Rescue ERC20 tokens that are stuck in the contract
   * @notice This function can only be called by the address with the DEFAULT_ADMIN_ROLE
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
   * @notice Rescue ERC721 tokens that are stuck in the contract
   * @notice This function can only be called by the address with the DEFAULT_ADMIN_ROLE
   * @param tokens the addresses of the tokens to rescue
   * @param tokenIds the IDs of the tokens to rescue
   * @param recipient the address to send the tokens to
   */
  function rescueERC721s(IERC721[] calldata tokens, uint256[] calldata tokenIds, address recipient)
    external;

  /**
   * @notice Rescue ERC1155 tokens that are stuck in the contract
   * @notice This function can only be called by the address with the DEFAULT_ADMIN_ROLE
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
