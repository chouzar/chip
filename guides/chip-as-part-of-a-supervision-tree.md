# Chip as part of a Supervision tree

A supervision tree is a strategy used in the wider erlang ecosystem to keep long-running processeess alive. When a process in any part of the tree terminates the supervisor will attempt to restart the process and any subsequent processess after it. Giving our whole system self-healing properties.

Lets assume we have the simplest "counter" actor code: 

```gleam
pub opaque type Message {
  Inc
  Oops
}

fn loop(message: Message, count: Int) {
  case message {
    Inc -> actor.continue(count + 1)
    Oops -> panic as "unexpected error"
  }
}
```

Integrating to a supervisor is simple enough if we create a `childspec` for our counter: 

```gleam 
pub fn main() {
  let self = process.new_subject()

  let childspec = fn(_param) {
    // start the counter
    use counter <- try(actor.start(0, loop))
    // on success, send counter back to caller.
    process.send(self, counter)
    Ok(counter)
  }

  // start all processess under a supervision tree 
  let assert Ok(_supervisor) =
    supervisor.start(fn(children) {
      children
      |> supervisor.add(supervisor.worker(childspec))
    })

  do_work(self)
}
```

With the implementation above, we have asured that our supervisor will keep this specific counter spec alive. In the case of unexpected termination the supervisor will re-run the childspec again to restore this and follow-up processess.  

For example lets assume the counter is terminated at the `do_work` function: 

```gleam
fn do_work(self) {
  // wait to receive the counter's subject, and operate on it
  let assert Ok(counter) = process.receive(self, 50)
  io.debug(counter)

  // lets attempt to restart it and receive another reference
  process.send(counter, Oops)
  let assert Ok(counter) = process.receive(self, 50)
  io.debug(counter)
}
```

The two subject counter references printed to the terminal are: 

```erlang
Subject(//erl(<0.90.0>), //erl(#Ref<0.3359404744.2770337801.190515>))
Subject(//erl(<0.91.0>), //erl(#Ref<0.3359404744.2770337801.190559>))
```

We can confirm that both process ids `0.90.0` and `0.91.0` are different, therefore when the first counter was terminated the supervisor restarted it and created `0.91.0` in its place.

All of this requires carrying the `self` reference around the program and knowing when to receive the process in case of failure. We may be completely out of scope. This is where a registry may help. 

Lets build a `start` specification for our counter actor: 

```gleam
pub fn start(registry, tag) {
  let init = fn() { init(registry, tag) }
  actor.start_spec(actor.Spec(init: init, init_timeout: 10, loop: loop))
}

fn init(registry, id) {
  // Create a reference to self
  let self = process.new_subject()

  // Register the counter under an id on initialization
  chip.register(
    registry,
    self
      |> chip.new()
      |> chip.tag(id),
  )

  // Adding self to the selector allows us to receive the Stop message
  actor.Ready(
    0,
    process.new_selector()
      |> process.selecting(self, function.identity),
  )
}
```

Then integrate chip and our new start function under our supervisor: 

```gleam
pub fn main() {
  let self = process.new_subject()

  let childspec_registry = fn(_param) {
    use registry <- try(chip.start())
    // on success, send the registry back to caller.
    process.send(self, registry)
    Ok(registry)
  }

  // Transform initial child parameter to the registry and an id tag
  let updater_registry = fn(_param, registry) { #(registry, 1) }

  let childspec_counter = fn(param) {
    // We now receive the registry and initial id
    let #(registry, id) = param
    start(registry, id)
  }

  // Subsequent child counters will increment their id tag
  let updater_counter = fn(param, _counter) {
    let #(registry, id) = param
    #(registry, id + 1)
  }

  // start all processess under a supervision tree 
  let assert Ok(_supervisor) =
    supervisor.start(fn(children) {
      children
      |> supervisor.add(
        supervisor.worker(childspec_registry)
        |> supervisor.returning(updater_registry),
      )
      |> supervisor.add(
        supervisor.worker(childspec_counter)
        |> supervisor.returning(updater_counter),
      )
    })

  // wait to receive the registry's subject, and operate on it
  let assert Ok(registry) = process.receive(self, 50)
  do_work(registry)
}
```

It is quite a bit of extra code and specification, but keep in mind you may move most of this to helpers. Now we can reference the counter from the registry in our `do_work` function.

```gleam
fn do_work(registry) {
  // retrieve the counter's subject, and operate on it
  let assert Ok(counter) = chip.find(registry, 1)
  io.debug(counter)

  // lets attempt to restart it and wait for the registry to update
  process.send(counter, Oops)
  process.sleep(50)
  let assert Ok(counter) = chip.find(registry, 1)
  io.debug(counter)
}
```

Printing us these subjects: 

```erlang
Subject(//erl(<0.91.0>), //erl(#Ref<0.211861637.3582984195.76640>))
Subject(//erl(<0.92.0>), //erl(#Ref<0.211861637.3582984195.76689>))
```

Granted the registry didn't solve all our issues, now we need to pass around a copy of our registry's subject through our app. And the registry may not yet have registered the new subject (we had to wait a few milliseconds for it to update and restart). 

These issues are out of scope of chip but may be solved through different techniques. For example, top-level processes may use an "app configuration" library that keeps track of singleton processes, if you'd like to re-purpose chip for this please check the [wrapping up chip Guideline](wrapping-up-chip.html) for more.
