# US West Linux ALB — Project Notes

## Deployment
- Used Terraform to deploy 17 AWS resources in us-west-2.
- Created Linux1 and Linux2 in separate Availability Zones.
- Installed and enabled Apache automatically through EC2 user data.
- Configured each server with its required welcome message.
- Created an Application Load Balancer and registered both servers.
- Created security groups allowing public HTTP to the load balancer
  and HTTP from the load balancer to the servers.
- Created an A alias record for dlc-linux-lb.dialloholmes.net.

## Issues and fixes
1. Terraform version mismatch:
   Installed version was 1.5.7, while the initial configuration
   required 1.6.0 or newer. Adjusted the version constraint to
   allow 1.5.7. Terraform initialization and validation succeeded.

2. Public DNS resolution failed:
   The domain registration pointed to ns45.domaincontrol.com and
   ns46.domaincontrol.com instead of the Route 53 hosted zone.
   Verified that the ALB worked directly and that Route 53 returned
   a valid answer. Updated the registered nameservers through AWS CLI.
   The update succeeded and the custom hostname began working.
   This registration change was performed outside Terraform.

## Verification
- Observed both Linux1 and Linux2 welcome messages through the hostname.
- Stopped Linux1 using AWS CLI and waited for it to stop.
- Repeated HTTP requests successfully returned Linux2's welcome message.
- Failover test passed.

## State at completion of failover test
- Linux1: stopped.
- Linux2: running.
- Load balancer: serving requests.
- GitHub upload: pending.
