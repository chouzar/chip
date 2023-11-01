# chip

[![Package Version](https://img.shields.io/hexpm/v/chip)](https://hex.pm/packages/chip)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/chip/)

A pure gleam process registry that plays along types and gleam OTP abstractions.
Will automatically delist dead processes. 

## Example

```gleam
import gleam/erlang/process
import chip

// Names can be built out of any primitive or even types.
type Name {
  A
  B
}

// We can start the registry and register a new subject 
let assert Ok(registry) = chip.start()
chip.register(registry, A, process.new_subject())

// If we lose scope of our processes, just look it up in the registry!
let assert Ok(subject) = chip.find(registry, A)
let assert Error(chip.NotFound) = chip.find(registry, B)
```

Feature-wise its still very basic but planning to integrate helpers
for supervisors that restar processes and a way to lookup name groups for
dynamic dispatch.

## Installation

You can If available on Hex this package can be added to your Gleam project:

```sh
gleam add chip
```

and its documentation can be found at <https://hexdocs.pm/chip>.
