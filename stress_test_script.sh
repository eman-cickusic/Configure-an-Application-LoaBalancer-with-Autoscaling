#!/bin/bash

# Stress Test Script for Application Load Balancer
# This script creates a stress test VM and runs load tests against the load balancer

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
PROJECT_ID=$(gcloud config get-value project)
STRESS_REGION="us-east1"
STRESS_ZONE="us-east1-b"

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Get load balancer IP
print_status "Getting load balancer IP address..."
LB_IPV4=$(gcloud compute forwarding-rules describe http-lb-ipv4 --global --format="value(IPAddress)" 2>/dev/null)

if [ -z "$LB_IPV4" ]; then
    print_error "Load balancer not found. Please run setup.sh first."
    exit 1
fi

echo -e "${BLUE}Load Balancer IPv4:${NC} $LB_IPV4"

# Check if load balancer is ready
print_status "Checking if load balancer is ready..."
RETRY_COUNT=0
MAX_RETRIES=30

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if curl -m 5 -s http://$LB_IPV4 | grep -q "Apache"; then
        print_status "Load balancer is ready!"
        break
    else
        print_warning "Load balancer not ready yet. Retrying in 10 seconds... ($((RETRY_COUNT+1))/$MAX_RETRIES)"
        sleep 10
        RETRY_COUNT=$((RETRY_COUNT+1))
    fi
done

if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
    print_error "Load balancer is not responding after $MAX_RETRIES attempts."
    exit 1
fi

# Create stress test VM
print_status "Creating stress test VM..."
gcloud compute instances create stress-test \
    --zone=$STRESS_ZONE \
    --machine-type=e2-medium \
    --network-interface=network-tier=PREMIUM,subnet=default \
    --maintenance-policy=MIGRATE \
    --provisioning-model=STANDARD \
    --image=mywebserver \
    --boot-disk-size=10GB \
    --boot-disk-type=pd-balanced \
    --boot-disk-device-name=stress-test

print_status "Installing Apache Bench on stress test VM..."
gcloud compute ssh stress-test --zone=$STRESS_ZONE --command="
    sudo apt-get update -y
    sudo apt-get install -y apache2-utils curl
    echo 'Apache Bench installed successfully'
"

# Run basic connectivity test
print_status "Testing basic connectivity from stress test VM..."
gcloud compute ssh stress-test --zone=$STRESS_ZONE --command="
    export LB_IP=$LB_IPV4
    echo \"Testing connection to load balancer at \$LB_IP\"
    curl -m 10 http://\$LB_IP | head -5
"

# Run stress test
print_status "Starting stress test..."
echo -e "${YELLOW}This will run a high-load test with 1000 concurrent connections and 500,000 total requests.${NC}"
echo -e "${YELLOW}The test may take 5-10 minutes to complete.${NC}"
echo ""

# Create the stress test command
STRESS_TEST_CMD="
export LB_IP=$LB_IPV4
echo \"Starting stress test against \$LB_IP\"
echo \"Test parameters: 500,000 requests with 1,000 concurrent connections\"
echo \"Start time: \$(date)\"

# Run the actual stress test
ab -n 500000 -c 1000 -g stress_test_results.tsv http://\$LB_IP/ > stress_test_output.txt 2>&1

echo \"\"
echo \"Stress test completed at: \$(date)\"
echo \"\"
echo \"=== Test Summary ===\"
grep -E 'Complete requests|Failed requests|Requests per second|Time per request' stress_test_output.txt
echo \"\"
echo \"=== Detailed Results ===\"
tail -20 stress_test_output.txt
"

# Execute the stress test
gcloud compute ssh stress-test --zone=$STRESS_ZONE --command="$STRESS_TEST_CMD"

# Monitor instance groups during the test
print_status "Checking instance group status..."
echo ""
echo -e "${BLUE}=== US-1-MIG Status ===${NC}"
gcloud compute instance-groups managed describe us-1-mig --region=us-central1 --format="table(name,targetSize,status.isStable,status.statefulPolicy)"

echo ""
echo -e "${BLUE}=== NOTUS-1-MIG Status ===${NC}"
gcloud compute instance-groups managed describe notus-1-mig --region=europe-west1 --format="table(name,targetSize,status.isStable,status.statefulPolicy)"

echo ""
echo -e "${BLUE}=== Instance Groups Overview ===${NC}"
gcloud compute instance-groups managed list --format="table(name,location,targetSize,instanceTemplate,creationTimestamp)"

# Show load balancer monitoring suggestions
echo ""
echo -e "${GREEN}=== Monitoring Suggestions ===${NC}"
echo -e "${YELLOW}To monitor the load balancer in real-time:${NC}"
echo "1. Go to Google Cloud Console → Network Services → Load Balancing"
echo "2. Click on 'http-lb'"
echo "3. Go to the 'Monitoring' tab"
echo "4. Observe 'Frontend Location (Total inbound traffic)'"
echo ""
echo -e "${YELLOW}To monitor instance groups:${NC}"
echo "1. Go to Compute Engine → Instance Groups"
echo "2. Click on 'us-1-mig' or 'notus-1-mig'"
echo "3. Go to the 'Monitoring' tab"
echo "4. Check 'Number of instances' and 'LB capacity'"
echo ""
echo -e "${YELLOW}Expected behavior:${NC}"
echo "- Initially, traffic goes to the closest backend (us-1-mig)"
echo "- As load increases, traffic distributes to both backends"
echo "- Instance groups should scale up automatically"
echo ""

# Offer to run additional tests
echo -e "${BLUE}=== Additional Test Options ===${NC}"
echo "Would you like to run additional tests? (y/n)"
read -r CONTINUE_TESTS

if [ "$CONTINUE_TESTS" = "y" ] || [ "$CONTINUE_TESTS" = "Y" ]; then
    print_status "Running continuous monitoring test..."
    
    MONITOR_CMD="
    export LB_IP=$LB_IPV4
    echo \"Starting continuous monitoring (press Ctrl+C to stop)\"
    
    while true; do
        RESPONSE=\$(curl -s -w '%{http_code} %{time_total}s' http://\$LB_IP/ -o /dev/null)
        TIMESTAMP=\$(date '+%Y-%m-%d %H:%M:%S')
        echo \"\$TIMESTAMP - Response: \$RESPONSE\"
        sleep 1
    done
    "
    
    echo -e "${YELLOW}Starting continuous monitoring. Press Ctrl+C to stop.${NC}"
    gcloud compute ssh stress-test --zone=$STRESS_ZONE --command="$MONITOR_CMD" || true
fi

print_status "Stress test completed!"
echo ""
echo -e "${GREEN}=== Test Summary ===${NC}"
echo -e "${BLUE}Load Balancer IP:${NC} $LB_IPV4"
echo -e "${BLUE}Stress Test VM:${NC} stress-test (in $STRESS_ZONE)"
echo ""
echo -e "${YELLOW}To clean up the stress test VM:${NC}"
echo "gcloud compute instances delete stress-test --zone=$STRESS_ZONE"
echo ""
echo -e "${YELLOW}To view detailed test results:${NC}"
echo "gcloud compute ssh stress-test --zone=$STRESS_ZONE --command='cat stress_test_output.txt'"