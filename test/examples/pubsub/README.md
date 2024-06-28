# PubSub Example

This is just an example of how you may use `chip` as a PubSub system for your app; there are many approaches but here each part of the system is neatly divided into its own module. 

If you're starting out I would recommend to keep things in a single module at first, Gleam doesn't like circular dependencies so you may end up investing a lot of time into data modelling and organizing your system rather than making it work. 

For more context follow the guide [chip as a local pubsub](../../../guides/chip-as-a-local-pubsub.md).