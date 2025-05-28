#!/bin/bash

# Cleanup Script for Google Cloud Application Load Balancer Lab
# This script removes all resources created during the lab to avoid ongoing charges

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

echo -e "${BLUE}=== Google Cloud Application Load Balancer Cleanup ===${NC}"
echo -e "${RED}This will delete ALL resources created during the lab.${NC}"
echo -e "${YELLOW}Are you sure you want to continue? (y/N)${NC}"
read -r CONFIRM

if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
    echo "Cleanup cancelled."
    exit 0
fi

# Configuration
REGION1="us-central1"
REGION2="europe-west1"
STRESS_REGION="us-east1"
STRESS_ZONE="us-east1-b"

# Delete stress test VM if it exists
print_status "Checking for stress test VM..."
if gcloud compute instances describe stress-test --zone=$STRESS_ZONE >/dev/null 2>&1; then
    print_status "Deleting stress test VM..."
    gcloud compute instances delete stress-test --zone=$STRESS_ZONE --quiet
else
    print_warning "Stress test VM not found, skipping..."
fi

# Delete forwarding rules (Load Balancer frontends)
print_status "Deleting global forwarding rules..."
gcloud compute forwarding-rules delete http-lb-ipv4 --global --quiet || print_warning "IPv4 forwarding rule not found"
gcloud compute forwarding-rules delete http-lb-ipv6 --global --quiet || print_warning "IPv6 forwarding rule not found"

# Delete target HTTP proxy
print_status "Deleting target HTTP proxy..."
gcloud compute target-http-proxies delete http-lb-proxy --quiet || print_warning "HTTP proxy not found"

# Delete URL map
print_status "Deleting URL map..."
gcloud compute url-maps delete http-lb --quiet || print_warning "URL map not found"

# Delete backend service
print_status "Deleting backend service..."
gcloud compute backend-services delete http-backend --global --quiet || print_warning "Backend service not found"

# Delete managed instance groups (this will also delete the instances)
print_status "Deleting managed instance groups..."
gcloud compute instance-groups managed delete us-1-mig --region=$REGION1 --quiet || print_warning "us-1-mig not found"
gcloud compute instance-groups managed delete notus-1-mig --region=$REGION2 --quiet || print_warning "notus-1-mig not found"

# Wait for instance groups to be fully deleted
print_status "Waiting for instance groups to be fully deleted..."
sleep 30

# Delete health check
print_status "Deleting health check..."
gcloud compute health-checks delete http-health-check --quiet || print_warning "Health check not found"

# Delete instance template
print_status "Deleting instance template..."
gcloud compute instance-templates delete mywebserver-template --quiet || print_warning "Instance template not found"

# Delete custom image
print_status "Deleting custom image..."
gcloud compute images delete mywebserver --quiet || print_warning "Custom image not found"

# Delete Cloud NAT
print_status "Deleting Cloud NAT..."
gcloud compute routers nats delete nat-config --router=nat-router-us1 --region=$REGION1 --quiet || print_warning "Cloud NAT not found"

# Delete Cloud Router
print_status "Deleting Cloud Router..."
gcloud compute routers delete nat-router-us1 --region=$REGION1 --quiet || print_warning "Cloud Router not found"

# Delete firewall rule
print_status "Deleting firewall rule..."
gcloud compute firewall-rules delete fw-allow-health-checks --quiet || print_warning "Firewall rule not found"

# Check for any remaining instances that might have been created manually
print_status "Checking for any remaining instances..."
REMAINING_INSTANCES=$(gcloud compute instances list --format="value(name,zone)" --filter="name~'(webserver|stress|mig)'" || echo "")

if [ -n "$REMAINING_INSTANCES" ]; then
    print_warning "Found remaining instances:"
    echo "$REMAINING_INSTANCES"
    echo ""
    echo -e "${YELLOW}Do you want to delete these instances as well? (y/N)${NC}"
    read -r DELETE_REMAINING
    
    if [ "$DELETE_REMAINING" = "y" ] || [ "$DELETE_REMAINING" = "Y" ]; then
        while IFS=\t' read -r INSTANCE_NAME INSTANCE_ZONE; do
            if [ -n "$INSTANCE_NAME" ] && [ -n "$INSTANCE_ZONE" ]; then
                print_status "Deleting instance: $INSTANCE_NAME in $INSTANCE_ZONE"
                gcloud compute instances delete "$INSTANCE_NAME" --zone="$INSTANCE_ZONE" --quiet
            fi
        done <<< "$REMAINING_INSTANCES"
    fi
fi

# Check for any remaining disks
print_status "Checking for any remaining disks..."
REMAINING_DISKS=$(gcloud compute disks list --format="value(name,zone)" --filter="name~'(webserver|stress)'" || echo "")

if [ -n "$REMAINING_DISKS" ]; then
    print_warning "Found remaining disks:"
    echo "$REMAINING_DISKS"
    echo ""
    echo -e "${YELLOW}Do you want to delete these disks as well? (y/N)${NC}"
    read -r DELETE_DISKS
    
    if [ "$DELETE_DISKS" = "y" ] || [ "$DELETE_DISKS" = "Y" ]; then
        while IFS=\t' read -r DISK_NAME DISK_ZONE; do
            if [ -n "$DISK_NAME" ] && [ -n "$DISK_ZONE" ]; then
                print_status "Deleting disk: $DISK_NAME in $DISK_ZONE"
                gcloud compute disks delete "$DISK_NAME" --zone="$DISK_ZONE" --quiet
            fi
        done <<< "$REMAINING_DISKS"
    fi
fi

echo ""
echo -e "${GREEN}=== Cleanup Complete! ===${NC}"
echo ""
echo -e "${BLUE}Deleted resources:${NC}"
echo "✓ Global Load Balancer (IPv4 and IPv6)"
echo "✓ Backend Services"
echo "✓ Managed Instance Groups"
echo "✓ Instance Template"
echo "✓ Custom Image"
echo "✓ Health Check"
echo "✓ Cloud NAT and Router"
echo "✓ Firewall Rules"
echo "✓ Any remaining instances and disks (if selected)"
echo ""
echo -e "${YELLOW}Note:${NC} It may take a few minutes for all resources to be fully removed from the Google Cloud Console."
echo ""
echo -e "${GREEN}Your Google Cloud project should now be clean of lab resources.${NC}"

# Optional: Show remaining compute resources
echo ""
echo -e "${BLUE}=== Verification ===${NC}"
echo -e "${YELLOW}Remaining compute instances:${NC}"
gcloud compute instances list --format="table(name,zone,status)" || echo "No instances found"

echo ""
echo -e "${YELLOW}Remaining load balancers:${NC}"
gcloud compute forwarding-rules list --global --format="table(name,target)" || echo "No global forwarding rules found"

echo ""
echo -e "${YELLOW}Remaining instance groups:${NC}"
gcloud compute instance-groups managed list --format="table(name,location,targetSize)" || echo "No managed instance groups found"