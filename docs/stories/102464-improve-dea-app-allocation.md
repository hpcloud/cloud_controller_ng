## Improved DEA app allocation

*Placement zone* is a new concept allowing DEAs to be grouped. In the code, this is purely a flag on the DEA, but in a deployment this could be used to mark DEAs intended for particular app deployment environments (dev/stage/prod), DEAs having particular hardware characteristics, etc..

DEAs now have a `placement_properties/zone` key in their config in which they can specify their placement zone. [n.b. Troy, per-node config in kato is new and will need to be documented as well]

When deploying an app instance to a placement zone, the Cloud Controller chooses a DEA to receive the instance prioritizing the DEA that is running the fewest instances of the app already. This maintains an even distribution of instances of any one app across the DEAs in the placement zone.