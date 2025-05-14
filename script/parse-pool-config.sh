#!/bin/bash
# filepath: /Users/tqcuong/Projects/KyberNetwork/kyber-exclusive-amm-sc/script/parse-pool-config.sh

# Pool Config Generator for UniswapV4 / PancakeInfinity CL pools
# This script generates configuration parameters for CreatePoolAndMintLiquidity.s.sol
# Requires: curl, jq

set -e  # Exit on any error

# ======== Constants ========
MIN_TICK=-887272
MAX_TICK=887272
Q96_VALUE="79228162514264337593543950336"  # 2^96
ADDRESS_ZERO="0x0000000000000000000000000000000000000000"

# ======== CONFIGURATION ========
# Set your pool parameters here
TOKEN0_ADDRESS="0x0000000000000000000000000000000000000000"  
TOKEN1_ADDRESS="0x55d398326f99059fF775485246999027B3197955"  

# RPC URL for fetching token info
RPC_URL="https://bsc-rpc.publicnode.com"

FEE=3000           # 0.3%
TICK_SPACING=100    # Tick spacing for the pool

PRICE="650"        # Price of token0 in terms of token1
LOWER_PRICE="500"  # Lower price bound
UPPER_PRICE="800"  # Upper price bound

TOKEN0_AMOUNT="0.5" 
TOKEN1_AMOUNT="500" 

# ======== Helper Functions ========

# Function to call ERC20 methods via RPC
fetch_from_rpc() {
  local address=$1
  local method=$2
  local hex_method=""
  
  # Native token (address zero) special handling
  local address_lower=$(echo "$address" | tr '[:upper:]' '[:lower:]')
  local zero_lower=$(echo "$ADDRESS_ZERO" | tr '[:upper:]' '[:lower:]')
  if [ "$address_lower" == "$zero_lower" ]; then
    if [ "$method" == "decimals" ]; then
      echo "18"  # Native has 18 decimals
    elif [ "$method" == "symbol" ]; then
      echo "NATIVE"  # Use NATIVE as symbol
    fi
    return
  fi
  
  # Prepare method signatures
  if [ "$method" == "decimals" ]; then
    hex_method="0x313ce567"  # keccak256("decimals()")
  elif [ "$method" == "symbol" ]; then
    hex_method="0x95d89b41"  # keccak256("symbol()")
  else
    echo "Unknown method: $method" >&2
    return
  fi
  
  # Call the contract
  local response=$(curl -s -X POST -H "Content-Type: application/json" --data '{
    "jsonrpc":"2.0",
    "method":"eth_call",
    "params":[{"to":"'"$address"'", "data":"'"$hex_method"'"}, "latest"],
    "id":1
  }' "$RPC_URL")
  
  # Extract result
  local result=$(echo "$response" | jq -r '.result')
  
  if [ "$method" == "decimals" ]; then
    # Parse decimals (uint8)
    echo $((16#${result:2}))
  elif [ "$method" == "symbol" ]; then
    echo "$result" | xxd -r -p | tr -d '\0'
  fi
}

# Function to fetch token decimals
fetch_token_decimals() {
  local address=$1
  fetch_from_rpc "$address" "decimals"
}

# Function to fetch token symbol
fetch_token_symbol() {
  local address=$1
  fetch_from_rpc "$address" "symbol"
}

# Log base 1.0001 calculation needed for tick conversion
log_base_1_0001() {
  local x=$1
  # log(x) / log(1.0001) using bc
  echo "scale=20; l($x) / l(1.0001)" | bc -l
}

# Function to convert price to tick
price_to_tick() {
  local price=$1
  local token0_decimals=$2
  local token1_decimals=$3
  
  # Calculate decimal adjustment
  local decimal_adjustment=$(bc -l <<< "10^($token1_decimals - $token0_decimals)")
  local adjusted_price=$(bc -l <<< "$price * $decimal_adjustment")
  
  # Calculate tick using log base 1.0001
  local tick=$(log_base_1_0001 "$adjusted_price")
  tick=$(printf "%.0f" "$(bc -l <<< "$tick")")
  
  # Ensure tick is within bounds
  if (( tick < MIN_TICK )); then
    tick=$MIN_TICK
  elif (( tick > MAX_TICK )); then
    tick=$MAX_TICK
  fi
  
  echo "$tick"
}

# Function to calculate sqrtPriceX96
price_to_sqrt_price_x96() {
  local price=$1
  local token0_decimals=$2
  local token1_decimals=$3
  
  # Calculate decimal adjustment
  local decimal_adjustment=$(bc -l <<< "10^($token1_decimals - $token0_decimals)")
  local adjusted_price=$(bc -l <<< "$price * $decimal_adjustment")
  
  # Calculate sqrt(price) * 2^96
  local sqrt_price=$(bc -l <<< "sqrt($adjusted_price)")
  local sqrt_price_x96=$(bc -l <<< "$sqrt_price * $Q96_VALUE")
  
  # Truncate to integer
  sqrt_price_x96=$(printf "%.0f" "$sqrt_price_x96")
  
  echo "$sqrt_price_x96"
}

# Function to normalize an address
normalize_address() {
  local address="$1"
  # Use tr command instead of Bash-specific lowercase syntax for better compatibility
  echo "$address" | tr '[:upper:]' '[:lower:]'
}

# Function to check if token is native (address zero)
is_native_token() {
  local address="$1"
  local address_lower=$(echo "$address" | tr '[:upper:]' '[:lower:]')
  if [ "$address_lower" == "$(echo "$ADDRESS_ZERO" | tr '[:upper:]' '[:lower:]')" ]; then
    return 0  # true in bash
  else
    return 1  # false in bash
  fi
}

# Function to format token amount with correct decimals
format_token_amount() {
  local amount="$1"
  local decimals="$2"
  
  # Convert to wei (amount * 10^decimals)
  local result=$(bc -l <<< "$amount * 10^$decimals")
  # Remove decimal part
  result=$(printf "%.0f" "$result")
  echo "$result"
}

# Function to round tick to valid tick spacing
round_tick_to_spacing() {
  local tick="$1"
  local spacing="$2"
  local direction="$3"  # "down" or "up"
  
  if [ "$direction" = "down" ]; then
    # Floor division to round down
    echo $(( (tick / spacing) * spacing ))
  else
    # Ceiling division to round up
    echo $(( ((tick + spacing - 1) / spacing) * spacing ))
  fi
}

# ======== Main Script ========

echo "Generating pool configuration..."

# Normalize addresses
TOKEN0_ADDRESS=$(normalize_address "$TOKEN0_ADDRESS")
TOKEN1_ADDRESS=$(normalize_address "$TOKEN1_ADDRESS")

# Check if token addresses need to be swapped based on byte order
TOKENS_SWAPPED="false"
if [[ "$TOKEN0_ADDRESS" > "$TOKEN1_ADDRESS" ]]; then
  echo "Swapping token order to follow Uniswap convention (token0 < token1)"
  
  # Swap token addresses
  temp="$TOKEN0_ADDRESS"
  TOKEN0_ADDRESS="$TOKEN1_ADDRESS"
  TOKEN1_ADDRESS="$temp"
  
  # Also swap token amounts
  temp="$TOKEN0_AMOUNT"
  TOKEN0_AMOUNT="$TOKEN1_AMOUNT"
  TOKEN1_AMOUNT="$temp"
  
  TOKENS_SWAPPED="true"
fi

# Fetch token information from RPC
echo "Fetching token information from RPC..."
TOKEN0_DECIMALS=$(fetch_token_decimals "$TOKEN0_ADDRESS")
TOKEN1_DECIMALS=$(fetch_token_decimals "$TOKEN1_ADDRESS")
TOKEN0_SYMBOL=$(fetch_token_symbol "$TOKEN0_ADDRESS")
TOKEN1_SYMBOL=$(fetch_token_symbol "$TOKEN1_ADDRESS")

echo "Token0: $TOKEN0_SYMBOL ($TOKEN0_DECIMALS decimals)"
echo "Token1: $TOKEN1_SYMBOL ($TOKEN1_DECIMALS decimals)"

# Adjust price if tokens were swapped
if [ "$TOKENS_SWAPPED" = "true" ]; then
  echo "Adjusting prices after token swap..."
  PRICE=$(bc -l <<< "1/$PRICE")
  temp="$LOWER_PRICE"
  LOWER_PRICE=$(bc -l <<< "1/$UPPER_PRICE")
  UPPER_PRICE=$(bc -l <<< "1/$temp")
fi

echo "Calculating sqrtPriceX96..."
# Calculate sqrtPriceX96
SQRT_PRICE_X96=$(price_to_sqrt_price_x96 "$PRICE" "$TOKEN0_DECIMALS" "$TOKEN1_DECIMALS")

echo "Calculating position ticks..."
# Calculate ticks from prices
LOWER_TICK=$(price_to_tick "$LOWER_PRICE" "$TOKEN0_DECIMALS" "$TOKEN1_DECIMALS")
UPPER_TICK=$(price_to_tick "$UPPER_PRICE" "$TOKEN0_DECIMALS" "$TOKEN1_DECIMALS")

# Round ticks to valid spacing
LOWER_TICK=$(round_tick_to_spacing "$LOWER_TICK" "$TICK_SPACING" "down")
UPPER_TICK=$(round_tick_to_spacing "$UPPER_TICK" "$TICK_SPACING" "up")

echo "Formatting token amounts..."
# Format token amounts with correct decimals
TOKEN0_AMOUNT_WEI=$(format_token_amount "$TOKEN0_AMOUNT" "$TOKEN0_DECIMALS")
TOKEN1_AMOUNT_WEI=$(format_token_amount "$TOKEN1_AMOUNT" "$TOKEN1_DECIMALS")

# Replace the file output section (lines ~280-300) with this:
echo "Generating Solidity configuration..."

# Generate and output Solidity configuration directly to stdout
echo "// Pool and Liquidity Configuration"
echo "// Generated at: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
echo ""
echo "// Pool Configuration"
echo "// ${TOKEN0_SYMBOL} (${TOKEN0_DECIMALS} decimals) - ${TOKEN1_SYMBOL} (${TOKEN1_DECIMALS} decimals)"
echo "IERC20 token0 = IERC20(${TOKEN0_ADDRESS});"
echo "IERC20 token1 = IERC20(${TOKEN1_ADDRESS});"
echo "uint24 lpFee = ${FEE};"
echo "int24 tickSpacing = ${TICK_SPACING};"
echo "uint160 startingPrice = ${SQRT_PRICE_X96}; // sqrtPriceX96 from price: ${PRICE}"
echo ""
echo "// Liquidity Position Configuration"
echo "uint256 token0Amount = ${TOKEN0_AMOUNT_WEI}; // ${TOKEN0_AMOUNT} ${TOKEN0_SYMBOL}"
echo "uint256 token1Amount = ${TOKEN1_AMOUNT_WEI}; // ${TOKEN1_AMOUNT} ${TOKEN1_SYMBOL}"
echo "int24 tickLower = ${LOWER_TICK}; // from price: ${LOWER_PRICE}"
echo "int24 tickUpper = ${UPPER_TICK}; // from price: ${UPPER_PRICE}"

echo ""
echo "Done!"