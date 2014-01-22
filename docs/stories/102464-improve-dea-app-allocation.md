## Improved DEA app allocation

When choosing a DEA on which to deploy an instance of an app, the Cloud Controller will now prioritize the eligible DEA which is running the fewest instances of the app already. This maintains an even distribution of instances of any one app across the DEAs. The previous allocation was round-robin.
