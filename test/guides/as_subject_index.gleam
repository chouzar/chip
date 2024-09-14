import artifacts/game.{DrawCard}
import artifacts/store

pub fn main() {
  let assert Ok(sessions) = store.start()

  let assert Ok(session_1) = game.start(DrawCard)
  let assert Ok(session_2) = game.start(DrawCard)
  let assert Ok(session_3) = game.start(DrawCard)

  store.index(sessions, 1, session_1)
  store.index(sessions, 2, session_2)
  store.index(sessions, 3, session_3)

  router(sessions, "/resource/", 2)
}

fn router(sessions, url, id) {
  case url, id {
    "/resource/", id -> render_resource(sessions, id)
    _other, _id -> render_error()
  }
}

fn render_resource(sessions, id) {
  case store.get(sessions, id) {
    Ok(session) -> game.current(session)
    Error(Nil) -> render_error()
  }
}

fn render_error() {
  "Print Error"
}
