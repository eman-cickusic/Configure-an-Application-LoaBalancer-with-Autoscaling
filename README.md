# Configure an Application Load Balancer with Autoscaling

This project demonstrates how to configure an Application Load Balancer (HTTP/HTTPS) with autoscaling on Google Cloud Platform. The setup includes global load balancing, managed instance groups, and stress testing to verify proper traffic distribution.

## Video

https://youtu.be/l3Kme6kLYb4

## Overview

Application Load Balancing (HTTP/HTTPS) is implemented at the edge of Google's network in Google's points of presence (POP) around the world. User traffic directed to an Application Load Balancer enters the POP closest to the user and is then load-balanced over Google's global network to the closest backend that has sufficient available capacity.

## Architecture Diagram

```
[Internet] → [Global Load Balancer] → [Backend Services]
                                    ↙                ↘
                         [Region 1 MIG]        [Region 2 MIG]
                         (us-1-mig)           (notus-1-mig)
                         Min: 1, Max: 2       Min: 1, Max: 2
```

## Objectives

This lab teaches you how to perform the following tasks:

- ✅ Create a health check firewall rule
- ✅ Create a NAT configuration using Cloud Router
- ✅ Create a custom image for a web server
- ✅ Create an instance template based on the custom image
- ✅ Create two managed instance groups
- ✅ Configure an Application Load Balancer (HTTP) with IPv4 and IPv6
- ✅ Stress test an Application Load Balancer (HTTP)

## Prerequisites

- Google Cloud Platform account
- Basic understanding of networking concepts
- Familiarity with Google Cloud Console

## Setup Instructions

### Task 1: Configure Health Check Firewall Rule

Health checks determine which instances can receive new connections. The health check probes come from specific IP ranges that must be allowed through firewall rules.

1. Navigate to **VPC network > Firewall** in the Google Cloud Console
2. Click **Create Firewall Rule**
3. Configure the following settings:

```
Name: fw-allow-health-checks
Network: default
Targets: Specified target tags
Target tags: allow-health-checks
Source filter: IPv4 ranges
Source IPv4 ranges: 130.211.0.0/22, 35.191.0.0/16
Protocols and ports: TCP port 80
```

### Task 2: Create NAT Configuration

VM instances without external IP addresses need Cloud NAT for outbound internet connectivity.

1. Navigate to **Network Services > Cloud NAT**
2. Click **Get started** to configure a NAT gateway
3. Configure the following:

```
Gateway name: nat-config
Network: default
Region: [Your Region 1]
Cloud Router: Create new router
Router name: nat-router-us1
```

### Task 3: Create Custom Web Server Image

Create a custom image with Apache web server pre-installed.

1. **Create VM Instance:**
```
Name: webserver
Region: [Region 1]
Zone: [Zone 1]
OS: Keep boot disk enabled
Network tags: allow-health-checks
External IP: None
```

2. **Install and Configure Apache:**
```bash
sudo apt-get update
sudo apt-get install -y apache2
sudo service apache2 start
sudo update-rc.d apache2 enable
```

3. **Test Installation:**
```bash
curl localhost
sudo service apache2 status
```

4. **Create Custom Image:**
   - Delete the VM instance (keeping the boot disk)
   - Navigate to **Compute Engine > Images**
   - Create image from the webserver disk

### Task 4: Configure Instance Template and Groups

Create instance templates and managed instance groups for load balancing.

1. **Instance Template Configuration:**
```
Name: mywebserver-template
Location: Global
Series: E2
Machine type: e2-micro
Boot disk: Custom image (mywebserver)
Network tags: allow-health-checks
External IP: None
```

2. **Health Check Configuration:**
```
Name: http-health-check
Protocol: TCP
Port: 80
```

3. **Managed Instance Groups:**

**Group 1 (Region 1):**
```
Name: us-1-mig
Instance template: mywebserver-template
Location: Multiple zones
Region: [Region 1]
Autoscaling: Min 1, Max 2
Signal type: HTTP load balancing utilization
Target utilization: 80%
Health check: http-health-check
Initial delay: 60 seconds
```

**Group 2 (Region 2):**
```
Name: notus-1-mig
Instance template: mywebserver-template
Location: Multiple zones
Region: [Region 2]
Autoscaling: Min 1, Max 2
Signal type: HTTP load balancing utilization
Target utilization: 80%
Health check: http-health-check
Initial delay: 60 seconds
```

### Task 5: Configure Application Load Balancer

Set up the HTTP load balancer with both IPv4 and IPv6 support.

1. **Load Balancer Configuration:**
```
Type: Application Load Balancer (HTTP/HTTPS)
Facing: Public facing (external)
Deployment: Global workloads
Generation: Global external Application Load Balancer
Name: http-lb
```

2. **Frontend Configuration:**
   - **IPv4 Frontend:** HTTP, Port 80, Ephemeral IP
   - **IPv6 Frontend:** HTTP, Port 80, Auto-allocate IP

3. **Backend Configuration:**
```
Backend Service Name: http-backend
Backend 1: us-1-mig (Rate: 50 RPS, Capacity: 100%)
Backend 2: notus-1-mig (Utilization: 80%, Capacity: 100%)
Health Check: http-health-check
Logging: Enabled (Sample rate: 1)
```

### Task 6: Stress Test the Load Balancer

Verify traffic distribution and autoscaling behavior.

1. **Check Load Balancer Status:**
```bash
LB_IP=[Your_LB_IPv4_Address]
while [ -z "$RESULT" ] ;
do
  echo "Waiting for Load Balancer";
  sleep 5;
  RESULT=$(curl -m1 -s $LB_IP | grep Apache);
done
```

2. **Create Stress Test VM:**
```
Name: stress-test
Region: [Closer to Region 1]
Machine type: e2-micro
Image: mywebserver (custom image)
```

3. **Run Load Test:**
```bash
export LB_IP=<Your_LB_IPv4_Address>
echo $LB_IP
ab -n 500000 -c 1000 http://$LB_IP/
```

## Monitoring and Verification

### Expected Behavior

1. **Initial Traffic:** Traffic should be directed to the closest backend (us-1-mig if testing from a region closer to Region 1)
2. **High Load:** As RPS increases beyond the configured limits, traffic will be distributed across both backends
3. **Autoscaling:** Instance groups will automatically scale up to handle increased load
4. **Health Checks:** Unhealthy instances will be automatically replaced

### Monitoring Points

- **Load Balancer Monitoring:** Frontend location traffic distribution
- **Instance Group Monitoring:** Number of instances and LB capacity
- **Individual Instance Monitoring:** CPU utilization and request handling

## Key Features Demonstrated

- **Global Load Balancing:** Traffic routed to closest available backend
- **Autoscaling:** Automatic scaling based on HTTP load balancing utilization
- **Health Checks:** Automatic instance replacement for unhealthy backends
- **Dual Stack Support:** Both IPv4 and IPv6 frontend configuration
- **Rate Limiting:** Different balancing modes (Rate vs Utilization)

## Cleanup

To avoid ongoing charges, remember to delete the following resources:
- Load balancer (http-lb)
- Backend services
- Instance groups (us-1-mig, notus-1-mig)
- Instance template (mywebserver-template)
- Custom image (mywebserver)
- NAT gateway and Cloud Router
- Firewall rule (fw-allow-health-checks)
- Any remaining VM instances

## Troubleshooting

### Common Issues

1. **Health Check Failures:** Ensure firewall rule allows traffic from health check IP ranges
2. **Instance Group Not Scaling:** Check autoscaling policies and initial delay settings
3. **Load Balancer Not Responding:** Verify backend services are healthy and properly configured
4. **SSH Connection Issues:** Use Cloud Identity-Aware Proxy if direct SSH fails

### Verification Commands

```bash
# Check if Apache is running
sudo service apache2 status

# Test local web server
curl localhost

# Monitor load balancer logs
gcloud logging read "resource.type=http_load_balancer"
```

## Best Practices

1. **Security:** Use minimal necessary firewall rules and remove external IPs where possible
2. **Monitoring:** Enable logging and set up appropriate alerting
3. **Scaling:** Configure appropriate scaling policies based on expected traffic patterns
4. **Testing:** Always test load balancer behavior under various load conditions
5. **Documentation:** Maintain clear documentation of configurations and dependencies

## Additional Resources

- [Google Cloud Load Balancing Documentation](https://cloud.google.com/load-balancing/docs)
- [Managed Instance Groups Documentation](https://cloud.google.com/compute/docs/instance-groups)
- [Application Load Balancer Best Practices](https://cloud.google.com/load-balancing/docs/https/application-load-balancer-best-practices)

---

*This project demonstrates enterprise-grade load balancing and autoscaling capabilities available in Google Cloud Platform.*
