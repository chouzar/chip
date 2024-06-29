# General use cases 

Chip is meant as a general solution for naming and grouping processess, therefore there may be many use cases attached to it. 

## As a process Index

Probably one of the most common uses cases for chip will involve looking up for subjects in your system. 

For example, in a web app we may add the registry as part of our app context. 

```gleam
pub fn main() {
  let assert Ok(registry) = chip.start()
  let self: process.Subject(Nil) = process.new_subject()
  
  chip.register(registry, chip.new(self) |> chip.tag("1st"))
  chip.register(registry, chip.new(self) |> chip.tag("2nd"))
  chip.register(registry, chip.new(self) |> chip.tag("3rd"))
  
  web.server(Context(registry))
  
  process.sleep_forever()
}
```

Then have access to the subjects at a completely different scope.

```gleam
pub server(request, context) {
  case request.route {
    Get, ["/resource/", id] -> {
      let result = chip.find(context.registry, id)
      render(result)
    }
  }
}
```

Of course, this ability to directly reference subjects is not very useful without a supervision tree, as if the subject dies we can no longer send messages to it. Check the [supervision guideline](chip-as-part-of-a-supervision-tree.html) for more. 

## As a dispatcher

One of the most useful use cases for chip involves dispatching messages to a collection of subjects. 

For example, we may register subjects as part of a group: 

```gleam
type Group {
  Even
  Odd
}

pub fn main() {
  let assert Ok(registry) = chip.start()

  let assert Ok(store_1) = store.start(1)
  let assert Ok(store_2) = store.start(2)
  let assert Ok(store_3) = store.start(3)

  chip.register(registry, chip.new(store_1) |> chip.group(Odd))
  chip.register(registry, chip.new(store_2) |> chip.group(Even))
  chip.register(registry, chip.new(store_3) |> chip.group(Odd))
}
``` 

Then later dispatch messages to all members:

```gleam
chip.dispatch(registry, fn(store) {
  store.increment(store)   
})
```

Or a sub-group of members:

```gleam
chip.dispatch_group(registry, Odd, fn(store) {
  store.increment(store)   
})
```

This is specially useful when wanting to create a PubSub system between subjects. Check the [PubSub Guideline](chip-as-a-local-pubsub.html) for more.  

## As app configuration

Other libraries in the erlang ecosystem like [registry](https://hexdocs.pm/elixir/Kernel.html), [pg](https://www.erlang.org/doc/apps/kernel/pg.html) and [syn](https://github.com/ostinelli/syn) can serve the purpose of storing configuration along processess.

Chip may not be well suited for this purpose as it can only store subjects of a single message type. If you need to reference subjects with different message types you may look at the [singularity](https://hexdocs.pm/singularity/) library. 

# More specific examples

Check the [wrapping up chip Guideline](wrapping-up-chip.html) for examples on how to re-purpose chip to your own specific use-cases.
