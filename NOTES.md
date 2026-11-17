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

# Stage 2: East/West Geographic Redundancy

## Infrastructure added
- Deployed Linux3 and Linux4 with Apache in us-east-1.
- Created East Coast networking, security groups, and an ALB.
- Verified both East servers displayed their custom welcome messages.

## Shared DNS
- Converted dlc-linux-lb.dialloholmes.net from West-only routing
  to two geoproximity A alias records for East and West.
- Enabled Evaluate Target Health on both aliases.
- Used geographic proximity rather than explicit country/state rules.

## Verified regional failover
- Stopped both West servers.
- Confirmed East targets remained healthy and West targets were unused.
- Initially observed HTTP 502/503 responses during the transition.
- Subsequently confirmed the shared hostname resolved to East ALB IPs.
- Verified the shared hostname served US East welcome messages.
- West-to-East failover: PASSED.
- The precise cause of the initial errors was not conclusively isolated.

## Configuration issue fixed
- Manual editing introduced duplicated and incomplete DNS resource blocks.
- Rebuilt the damaged section and passed terraform validate.

## Remaining verification
- Confirm both West servers are healthy after restart.
- Test geographic selection from West and East connections
  while both regions are healthy.
- Test East-to-West failover and restore East afterward.

## State management
- This project extends the original West deployment using its existing state.
- The original GitHub repository preserves the West-only code.
- Do not independently apply the old West-only configuration against
  this expanded deployment's state.
