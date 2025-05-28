#!/bin/bash

# Google Cloud Application Load Balancer with Autoscaling Setup Script
# This script automates the setup process for the load balancer lab

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration variables
PROJECT_ID=$(gcloud config get-value project)
REGION1="us-central1"
REGION2="europe-west1"
ZONE1="us-central1-c"
ZONE2="europe-west1-c"

echo -e "${BLUE}=== Google Cloud Application Load Balancer Setup ===${NC}"
echo "Project ID: $PROJECT_ID"
echo "Region 1: $REGION1"
echo "Region 2: $REGION2"
echo ""

# Function to print status
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Enable required APIs
print_status "Enabling required APIs..."
gcloud services enable compute.googleapis.com
gcloud services enable logging.googleapis.com

# Task 1: Create health check firewall rule
print_status "Creating health check firewall rule..."
gcloud compute firewall-rules create fw-allow-health-checks \
    --direction=INGRESS \
    --priority=1000 \
    --network=default \
    --action=ALLOW \
    --rules=tcp:80 \
    --source-ranges=130.211.0.0/22,35.191.0.0/16 \
    --target-tags=allow-health-checks

# Task 2: Create Cloud Router and NAT
print_status "Creating Cloud Router..."
gcloud compute routers create nat-router-us1 \
    --network=default \
    --region=$REGION1

print_status "Creating Cloud NAT..."
gcloud compute routers nats create nat-config \
    --router=nat-router-us1 \
    --region=$REGION1 \
    --nat-all-subnet-ip-ranges \
    --auto-allocate-nat-external-ips

# Task 3: Create and configure web server VM
print_status "Creating web server VM..."
gcloud compute instances create webserver \
    --zone=$ZONE1 \
    --machine-type=e2-micro \
    --network-interface=network-tier=PREMIUM,subnet=default,no-address \
    --maintenance-policy=MIGRATE \
    --provisioning-model=STANDARD \
    --tags=allow-health-checks \
    --image=debian-11-bullseye-v20231115 \
    --image-project=debian-cloud \
    --boot-disk-size=10GB \
    --boot-disk-type=pd-balanced \
    --boot-disk-device-name=webserver \
    --no-shielded-secure-boot \
    --shielded-vtpm \
    --shielded-integrity-monitoring \
    --reservation-affinity=any

print_status "Configuring Apache on web server..."
gcloud compute ssh webserver --zone=$ZONE1 --command="
    sudo apt-get update -y
    sudo apt-get install -y apache2  
    sudo systemctl start apache2
    sudo systemctl enable apache2
    echo 'Web server configured successfully'
"

print_status "Testing Apache installation..."
gcloud compute ssh webserver --zone=$ZONE1 --command="curl -s localhost | head -5"

print_status "Stopping and creating custom image..."
gcloud compute instances stop webserver --zone=$ZONE1

# Wait for instance to stop
sleep 30

gcloud compute images create mywebserver \
    --source-disk=webserver \
    --source-disk-zone=$ZONE1 \
    --family=webserver-family

print_status "Deleting temporary webserver instance..."
gcloud compute instances delete webserver --zone=$ZONE1 --quiet

# Task 4: Create health check
print_status "Creating health check..."
gcloud compute health-checks create tcp http-health-check \
    --port=80

# Create instance template
print_status "Creating instance template..."
gcloud compute instance-templates create mywebserver-template \
    --machine-type=e2-micro \
    --network-interface=network-tier=PREMIUM,subnet=default,no-address \
    --maintenance-policy=MIGRATE \
    --provisioning-model=STANDARD \
    --tags=allow-health-checks \
    --image=mywebserver \
    --boot-disk-size=10GB \
    --boot-disk-type=pd-balanced \
    --boot-disk-device-name=instance-template-1

# Create managed instance groups
print_status "Creating managed instance group in $REGION1..."
gcloud compute instance-groups managed create us-1-mig \
    --template=mywebserver-template \
    --size=1 \
    --region=$REGION1

print_status "Setting autoscaling for us-1-mig..."
gcloud compute instance-groups managed set-autoscaling us-1-mig \
    --region=$REGION1 \
    --max-num-replicas=2 \
    --min-num-replicas=1 \
    --target-load-balancing-utilization=0.8 \
    --cool-down-period=60s

print_status "Setting autohealing for us-1-mig..."
gcloud compute instance-groups managed set-autohealing us-1-mig \
    --region=$REGION1 \
    --health-check=http-health-check \
    --initial-delay=60s

print_status "Creating managed instance group in $REGION2..."
gcloud compute instance-groups managed create notus-1-mig \
    --template=mywebserver-template \
    --size=1 \
    --region=$REGION2

print_status "Setting autoscaling for notus-1-mig..."
gcloud compute instance-groups managed set-autoscaling notus-1-mig \
    --region=$REGION2 \
    --max-num-replicas=2 \
    --min-num-replicas=1 \
    --target-load-balancing-utilization=0.8 \
    --cool-down-period=60s

print_status "Setting autohealing for notus-1-mig..."
gcloud compute instance-groups managed set-autohealing notus-1-mig \
    --region=$REGION2 \
    --health-check=http-health-check \
    --initial-delay=60s

print_status "Waiting for instance groups to be ready..."
sleep 60

# Task 5: Create load balancer
print_status "Creating backend service..."
gcloud compute backend-services create http-backend \
    --protocol=HTTP \
    --port-name=http \
    --health-checks=http-health-check \
    --global \
    --enable-logging \
    --logging-sample-rate=1.0

print_status "Adding backends to backend service..."
gcloud compute backend-services add-backend http-backend \
    --instance-group=us-1-mig \
    --instance-group-region=$REGION1 \
    --balancing-mode=RATE \
    --max-rate-per-instance=50 \
    --capacity-scaler=1.0 \
    --global

gcloud compute backend-services add-backend http-backend \
    --instance-group=notus-1-mig \
    --instance-group-region=$REGION2 \
    --balancing-mode=UTILIZATION \
    --max-utilization=0.8 \
    --capacity-scaler=1.0 \
    --global

print_status "Creating URL map..."
gcloud compute url-maps create http-lb \
    --default-service=http-backend

print_status "Creating HTTP proxy..."
gcloud compute target-http-proxies create http-lb-proxy \
    --url-map=http-lb

print_status "Creating global forwarding rule (IPv4)..."
gcloud compute forwarding-rules create http-lb-ipv4 \
    --global \
    --target-http-proxy=http-lb-proxy \
    --ports=80

print_status "Creating global forwarding rule (IPv6)..."
gcloud compute forwarding-rules create http-lb-ipv6 \
    --global \
    --target-http-proxy=http-lb-proxy \
    --ports=80 \
    --ip-version=IPV6

print_status "Getting load balancer IP addresses..."
LB_IPV4=$(gcloud compute forwarding-rules describe http-lb-ipv4 --global --format="value(IPAddress)")
LB_IPV6=$(gcloud compute forwarding-rules describe http-lb-ipv6 --global --format="value(IPAddress)")

echo ""
echo -e "${GREEN}=== Setup Complete! ===${NC}"
echo -e "${BLUE}Load Balancer IPv4:${NC} $LB_IPV4"
echo -e "${BLUE}Load Balancer IPv6:${NC} $LB_IPV6"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "1. Wait 5-10 minutes for the load balancer to be fully ready"
echo "2. Test the load balancer: curl http://$LB_IPV4"
echo "3. Run the stress test using the stress_test.sh script"
echo ""
echo -e "${YELLOW}To clean up resources, run:${NC} ./cleanup.sh"