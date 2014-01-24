## Improved DEA app allocation

*Distribution zone* is a new concept allowing DEAs to be grouped. In the code, this is purely a flag on the DEA, but in a deployment this could be used to mark DEAs intended for particular app deployment environments (dev/stage/prod), DEAs having particular hardware characteristics, etc..

DEAs now have a `placement_properties/zones` key in their config in which they can specify their distribution zones - there is a helper kato command to do so:

$ kato node zones add <zone>
$ kato node zones list
$ kato node zones remove <zone>

When deploying an app instance to a distribution zone, the Cloud Controller chooses a DEA to receive the instance prioritizing the DEA that is running the fewest instances of the app already. This maintains an even distribution of instances of any one app across the DEAs in the distribution zone.

By default, apps will be deployed into the 'default' zone. Similarly, DEAs that don't register a zone or those that advertise the 'default' zone will accept apps from this zone. This maintains backwards compatibility, so DEAs without zones support will accept 'default' apps. 

Zones allow you to create rigid segregation, for instance you can designate certain DEAs to be production-only and no apps in any zone other than 'production' will be deployed to those DEAs.

To implement this, zones are strictly enforced, so if an app is in zone X and a DEA doesn't advertise zone X, the app will in no case be deployed to that DEA. This means if an app attempts to use zone X and no DEAs in the cluster provide zone X, the app will not deploy, and will show the corresponding message during "stackato push".

DEAs can advertise multiple zones, and in doing so will be able to accept apps that use any of the zones that they advertise.