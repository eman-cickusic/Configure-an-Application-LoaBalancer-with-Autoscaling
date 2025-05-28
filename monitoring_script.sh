#!/bin/bash

# Monitoring Script for Google Cloud Application Load Balancer
# This script provides real-time monitoring of the load balancer and instance groups

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
REGION1="us-central1"
REGION2="europe-west1"

print_header() {
    echo -e "${BLUE}=== $1 ===${NC}"
}

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to get load balancer IP
get_lb_ip() {
    LB_IPV4=$(gcloud compute forwarding-rules describe http-lb-ipv4 --global --format="value(IPAddress)" 2>/dev/null || echo "")
    LB_IPV6=$(gcloud compute forwarding-rules describe http-lb-ipv6 --global --format="value(IPAddress)" 2>/dev/null || echo "")
}

# Function to test load balancer connectivity
test_connectivity() {
    if [ -n "$LB_IPV4" ]; then
        RESPONSE=$(curl -s -w "%{http_code} %{time_total}s" -o /dev/null http://$LB_IPV4/ 2>/dev/null || echo "000 0.000s")
        HTTP_CODE=$(echo $RESPONSE | cut -d' ' -f1)
        RESPONSE_TIME=$(echo $RESPONSE | cut -d' ' -f2)
        
        if [ "$HTTP_CODE" = "200" ]; then
            echo -e "${GREEN}✓${NC} HTTP $HTTP_CODE - Response time: $RESPONSE_TIME"
        else
            echo -e "${RED}✗${NC} HTTP $HTTP_CODE - Response time: $RESPONSE_TIME"
        fi
    else
        echo -e "${RED}✗${NC} Load balancer IP not found"
    fi
}

# Function to show instance group status
show_instance_groups() {
    print_header "Instance Groups Status"
    
    # US-1-MIG Status
    echo -e "${CYAN}US-1-MIG (Region: $REGION1):${NC}"
    if gcloud compute instance-groups managed describe us-1-mig --region=$REGION1 >/dev/null 2>&1; then
        gcloud compute instance-groups managed describe us-1-mig --region=$REGION1 \
            --format="table(
                name,
                targetSize:label='TARGET_SIZE',
                status.isStable:label='STABLE',
                status.versionTarget.isReached:label='VERSION_REACHED'
            )"
        
        # List instances in the group
        echo -e "${YELLOW}Instances in us-1-mig:${NC}"
        gcloud compute instance-groups managed list-instances us-1-mig --region=$REGION1 \
            --format="table(
                name:label='INSTANCE_NAME',
                status:label='STATUS',
                instanceStatus:label='INSTANCE_STATUS',
                lastAttempt.errors.errors[0].message:label='LAST_ERROR'
            )"
    else
        echo -e "${RED}us-1-mig not found${NC}"
    fi
    
    echo ""
    
    # NOTUS-1-MIG Status
    echo -e "${CYAN}NOTUS-1-MIG (Region: $REGION2):${NC}"
    if gcloud compute instance-groups managed describe notus-1-mig --region=$REGION2 >/dev/null 2>&1; then
        gcloud compute instance-groups managed describe notus-1-mig --region=$REGION2 \
            --format="table(
                name,
                targetSize:label='TARGET_SIZE',
                status.isStable:label='STABLE',
                status.versionTarget.isReached:label='VERSION_REACHED'
            )"
        
        # List instances in the group
        echo -e "${YELLOW}Instances in notus-1-mig:${NC}"
        gcloud compute instance-groups managed list-instances notus-1-mig --region=$REGION2 \
            --format="table(
                name:label='INSTANCE_NAME',
                status:label='STATUS',
                instanceStatus:label='INSTANCE_STATUS',
                lastAttempt.errors.errors[0].message:label='LAST_ERROR'
            )"
    else
        echo -e "${RED}notus-1-mig not found${NC}"
    fi
}

# Function to show load balancer status
show_load_balancer_status() {
    print_header "Load Balancer Status"
    
    # Get IP addresses
    get_lb_ip
    
    if [ -n "$LB_IPV4" ]; then
        echo -e "${CYAN}IPv4 Address:${NC} $LB_IPV4"
    else
        echo -e "${RED}IPv4 Address: Not found${NC}"
    fi
    
    if [ -n "$LB_IPV6" ]; then
        echo -e "${CYAN}IPv6 Address:${NC} $LB_IPV6"
    else
        echo -e "${RED}IPv6 Address: Not found${NC}"
    fi
    
    echo ""
    echo -e "${CYAN}Connectivity Test:${NC}"
    test_connectivity
    
    echo ""
    echo -e "${CYAN}Backend Service Status:${NC}"
    if gcloud compute backend-services describe http-backend --global >/dev/null 2>&1; then
        gcloud compute backend-services describe http-backend --global \
            --format="table(
                name,
                protocol,
                healthChecks[0].basename():label='HEALTH_CHECK',
                timeoutSec:label='TIMEOUT',
                enableLogging:label='LOGGING'
            )"
        
        # Show backend health
        echo ""
        echo -e "${YELLOW}Backend Health Status:${NC}"
        gcloud compute backend-services get-health http-backend --global \
            --format="table(
                status.healthStatus[0].instance.basename():label='INSTANCE',
                status.healthStatus[0].healthState:label='HEALTH_STATE',
                status.healthStatus[0].port:label='PORT'
            )" 2>/dev/null || echo "Health status not available yet"
    else
        echo -e "${RED}Backend service not found${NC}"
    fi
}

# Function for continuous monitoring
continuous_monitoring() {
    print_status "Starting continuous monitoring (press Ctrl+C to stop)"
    echo ""
    
    get_lb_ip
    
    if [ -z "$LB_IPV4" ]; then
        print_error "Load balancer IP not found. Exiting."
        exit 1
    fi
    
    while true; do
        clear
        TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
        echo -e "${BLUE}=== Load Balancer Monitoring - $TIMESTAMP ===${NC}"
        echo ""
        
        # Quick connectivity test
        echo -e "${CYAN}Load Balancer ($LB_IPV4):${NC}"
        test_connectivity
        echo ""
        
        # Instance group summary
        echo -e "${CYAN}Instance Groups Summary:${NC}"
        
        # Get target sizes
        US_TARGET=$(gcloud compute instance-groups managed describe us-1-mig --region=$REGION1 --format="value(targetSize)" 2>/dev/null || echo "0")
        NOTUS_TARGET=$(gcloud compute instance-groups managed describe notus-1-mig --region=$REGION2 --format="value(targetSize)" 2>/dev/null || echo "0")
        
        echo -e "us-1-mig ($REGION1): ${GREEN}$US_TARGET${NC} instances"
        echo -e "notus-1-mig ($REGION2): ${GREEN}$NOTUS_TARGET${NC} instances"
        
        echo ""
        echo -e "${YELLOW}Press Ctrl+C to stop monitoring${NC}"
        
        sleep 5
    done
}

# Function to show help
show_help() {
    echo -e "${BLUE}Google Cloud Load Balancer Monitoring Script${NC}"
    echo ""
    echo "Usage: $0 [OPTION]"
    echo ""
    echo "Options:"
    echo "  -s, --status        Show current status of all components"
    echo "  -l, --loadbalancer  Show load balancer details only"
    echo "  -i, --instances     Show instance groups details only"
    echo "  -m, --monitor       Start continuous monitoring"
    echo "  -t, --test          Run connectivity tests"
    echo "  -h, --help          Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 --status         # Show complete status"
    echo "  $0 --monitor        # Start continuous monitoring"
    echo "  $0 --test           # Test load balancer connectivity"
}

# Function to run connectivity tests
run_tests() {
    print_header "Load Balancer Connectivity Tests"
    
    get_lb_ip
    
    if [ -z "$LB_IPV4" ]; then
        print_error "Load balancer IPv4 address not found"
        return 1
    fi
    
    echo -e "${CYAN}Testing IPv4 endpoint: $LB_IPV4${NC}"
    
    # Test 1: Basic connectivity
    echo -n "Basic connectivity: "
    test_connectivity
    
    # Test 2: Multiple requests
    echo ""
    echo -e "${CYAN}Running multiple requests (10 requests):${NC}"
    for i in {1..10}; do
        RESPONSE=$(curl -s -w "%{http_code} %{time_total}s" -o /dev/null http://$LB_IPV4/ 2>/dev/null || echo "000 0.000s")
        echo "Request $i: $RESPONSE"
        sleep 1
    done
    
    # Test 3: Response content check
    echo ""
    echo -e "${CYAN}Response content check:${NC}"
    CONTENT=$(curl -s http://$LB_IPV4/ 2>/dev/null || echo "")
    if echo "$CONTENT" | grep -q "Apache"; then
        echo -e "${GREEN}✓${NC} Apache default page detected"
    else
        echo -e "${RED}✗${NC} Unexpected response content"
    fi
}

# Main script logic
case "${1:-}" in
    -s|--status)
        show_load_balancer_status
        echo ""
        show_instance_groups
        ;;
    -l|--loadbalancer)
        show_load_balancer_status
        ;;
    -i|--instances)
        show_instance_groups
        ;;
    -m|--monitor)
        continuous_monitoring
        ;;
    -t|--test)
        run_tests
        ;;
    -h|--help)
        show_help
        ;;
    "")
        show_load_balancer_status
        echo ""
        show_instance_groups
        ;;
    *)
        echo -e "${RED}Unknown option: $1${NC}"
        echo ""
        show_help
        exit 1
        ;;
esac