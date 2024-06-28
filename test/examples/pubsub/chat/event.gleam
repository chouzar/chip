pub type Event {
  Event(id: Int, user: String, message: String)
}

pub fn next(events: List(Event), user: String, message: String) -> Event {
  Event(id: next_id(events), user: user, message: message)
}

fn next_id(chat: List(Event)) -> Int {
  case chat {
    [] -> 1
    [record, ..] -> record.id + 1
  }
}
