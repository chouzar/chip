import examples/pubsub/chat/pubsub
import examples/pubsub/chat/server
import gleam/erlang/process
import gleam/otp/actor
import gleam/otp/supervisor

pub type Supervisor =
  process.Subject(supervisor.Message)

pub fn start(
  caller: process.Subject(server.Server),
) -> Result(Supervisor, actor.StartError) {
  supervisor.start(fn(children) {
    children
    |> supervisor.add(pubsub.childspec())
    |> supervisor.add(server.childspec(caller))
  })
}
