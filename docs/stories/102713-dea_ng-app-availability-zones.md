## DEA availability zones

*Availability zone* is a new concept which allows a cluster administrator to configure Stackato to respect the physical/logical distribution of servers, similar to availability zones or regions in EC2. 

Stackato will ensure that, if there are multiple availability zones configured, that apps are evenly distributed among them as much as possible (if there are 3 instances of an app and 3 availability zones, 1 instance will be in each zone). This significantly improves HA and quick disaster recovery - if an entire datacenter or availability zone goes offline, the app will remain running with little to no downtime.

DEAs now have a `placement_properties/availability_zone` key in their config in which they can specify their availability zone - there is a helper kato command to do so:

$ kato node availabilityzone
# => default
$ kato node availabilityzone dc1
# => dc1

By default, all DEAs are part of the 'default' availability zone. Setting up multiple availability zones will ensure even distribution of apps among the DEAs within them.