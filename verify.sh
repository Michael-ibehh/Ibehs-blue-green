#!/bin/bash
set -e

# Source the .env file to load environment variables
if [ -f .env ]; then
    echo "Sourcing .env file..."
    export $(grep -v '^#' .env | xargs)
    echo "RELEASE_ID_BLUE=$RELEASE_ID_BLUE"
    echo "RELEASE_ID_GREEN=$RELEASE_ID_GREEN"
else
    echo "Error: .env file not found"
    exit 1
fi

# Base URL and configuration
URL="http://localhost:8080/version"
BLUE_CHAOS="http://localhost:8081/chaos"
TIMEOUT=2
RETRIES=20
SUCCESS_COUNT=0
GREEN_COUNT=0

# Function to check response
check_response() {
    local url=$1
    local expected_pool=$2
    local expected_release=$3
    local response
    local headers
    local app_pool
    local release_id

    # Fetch response code and headers
    response=$(curl -s -o response.json -w "%{http_code}" --max-time "$TIMEOUT" "$url")
    headers=$(curl -s -I --max-time "$TIMEOUT" "$url")

    # Debug headers
    echo "Raw headers: $headers"

    # Extract headers
    app_pool=$(echo "$headers" | grep -i '^X-App-Pool:' | sed 's/^X-App-Pool: *\(.*\)$/\1/i' | tr -d '\r' || echo "")
    release_id=$(echo "$headers" | grep -i '^X-Release-Id:' | sed 's/^X-Release-Id: *\(.*\)$/\1/i' | tr -d '\r' || echo "")

    # Debug extracted values
    echo "Extracted X-App-Pool: '$app_pool'"
    echo "Extracted X-Release-Id: '$release_id'"
    echo "Expected X-App-Pool: '$expected_pool'"
    echo "Expected X-Release-Id: '$expected_release'"

    if [ "$response" != "200" ]; then
        echo "Error: Non-200 response ($response)"
        exit 1
    fi
    if [ -z "$app_pool" ] || [ "$app_pool" != "$expected_pool" ]; then
        echo "Error: Expected X-App-Pool: '$expected_pool', got '$app_pool'"
        exit 1
    fi
    if [ -z "$release_id" ] || [ "$release_id" != "$expected_release" ]; then
        echo "Error: Expected X-Release-Id: '$expected_release', got '$release_id'"
        exit 1
    fi
    echo "✅ Success: Status=200, X-App-Pool=$app_pool, X-Release-Id=$release_id"
}

# Step 1: Test baseline (Blue active)
echo "Testing baseline (Blue active)..."
for ((i=1; i<=5; i++)); do
    check_response "$URL" "blue" "$RELEASE_ID_BLUE"
done

# Step 2: Induce chaos on Blue
echo "Inducing chaos on Blue..."
curl -s -X POST --max-time "$TIMEOUT" "$BLUE_CHAOS/start?mode=error" || {
    echo "Error: Failed to induce chaos on Blue"
    exit 1
}

# Step 3: Test failover to Green
echo "Testing failover to Green..."
for ((i=1; i<=$RETRIES; i++)); do
    response=$(curl -s -o response.json -w "%{http_code}" --max-time "$TIMEOUT" "$URL")
    headers=$(curl -s -I --max-time "$TIMEOUT" "$URL")
    app_pool=$(echo "$headers" | grep -i '^X-App-Pool:' | sed 's/^X-App-Pool: *\(.*\)$/\1/i' | tr -d '\r' || echo "")
    release_id=$(echo "$headers" | grep -i '^X-Release-Id:' | sed 's/^X-Release-Id: *\(.*\)$/\1/i' | tr -d '\r' || echo "")

    if [ "$response" != "200" ]; then
        echo "Error: Non-200 response ($response) after chaos"
        exit 1
    fi
    if [ "$app_pool" = "green" ]; then
        ((GREEN_COUNT++))
    fi
    ((SUCCESS_COUNT++))
    echo "Request $i: Status=$response, X-App-Pool=$app_pool, X-Release-Id=$release_id"
done

# Step 4: Validate Green response rate
GREEN_PERCENT=$((GREEN_COUNT * 100 / SUCCESS_COUNT))
if [ $GREEN_COUNT -lt $((RETRIES * 95 / 100)) ]; then
    echo "Error: Green responses ($GREEN_PERCENT%) below 95%"
    exit 1
fi
echo "Success: $GREEN_PERCENT% responses from Green"

# Step 5: Stop chaos and verify Blue recovery
echo "Stopping chaos on Blue..."
curl -s -X POST --max-time "$TIMEOUT" "$BLUE_CHAOS/stop" || {
    echo "Error: Failed to stop chaos on Blue"
    exit 1
}
sleep 5 # Wait for fail_timeout (set to 5s in Nginx config)

echo "Testing Blue recovery..."
for ((i=1; i<=5; i++)); do
    check_response "$URL" "blue" "$RELEASE_ID_BLUE"
done

echo "All tests passed!"