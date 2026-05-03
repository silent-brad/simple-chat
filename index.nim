import std/[strutils, asyncdispatch, sets, hashes, json]
import db_connector/db_sqlite
import karax/[karaxdsl, vdom], jester, ws, ws/jester_extra

converter to_string(x: VNode): string = $x
type User = object
  name: string
  socket: WebSocket
proc hash(x: User): Hash = hash(x.name)
var chatrooms = init_table[string, HashSet[User]]()
let db = open("chat.db", "", "", "")
db.exec(sql"CREATE TABLE IF NOT EXISTS messages (room TEXT, name TEXT, message TEXT)")
proc load_history(room: string): VNode =
  build_html(tdiv(id="content", hx-swap-oob="beforeend")):
    for row in db.fast_rows(sql"SELECT name, message FROM messages WHERE room = ?", room):
      tdiv:
        bold: text row[0]
        text ": " & row[1]
template index*(rest: untyped): untyped =
  build_html(html(lang = "en")):
    head:
      meta(charset = "UTF-8", name="viewport", content="width=device-width, initial-scale=1")
      link(rel = "stylesheet", href = "https://unpkg.com/@picocss/pico@latest/css/pico.min.css")
      script(src = "https://unpkg.com/htmx.org@1.6.0")
      title: text "Simple Chat"
    body:
      nav(class="container-fluid"):
        ul: li: a(href = "/", class="secondary"): strong: text "Simple Chat"
      main(class="container"): rest
proc chat_input(): VNode = build_html(input(name="message", id="clearinput", autofocus="", required=""))
proc send_all(users: HashSet[User], msg: string) =
  for user in users: discard user.socket.send(msg)
template build_message*(msg: untyped): untyped =
  build_html(tdiv(id="content", hx-swap-oob="beforeend")):
    tdiv: msg
routes:
  get "/":
    let html = index:
      h1: text "Join a room!"
      section:
        h2: text "Current rooms"
        ul:
          for row in db.fast_rows(sql"SELECT DISTINCT room FROM messages"):
            li: a(href = "/chat?room=" & row[0] & "&name="): text row[0]
      form(action="/chat", `method`="get"):
        label:
          text "Room"
          input(type="text", name="room")
        label:
          text "Username"
          input(type="text", name="name")
        input(type="submit", value="Join")
    resp html
  get "/chat":
    let html = index:
      h1: text @"room"
      tdiv(hx-ws="connect:/chat/" & @"room" & "/" & @"name"):
        p(id="content")
        form(hx-ws="send", id="message"): chat_input()
    resp html
  get "/chat/@room/@name":
    var ws = await new_web_socket(request)
    var user = User(name: @"name", socket: ws)
    try:
      chatrooms.mget_or_put(@"room", init_hash_set[User]()).incl(user)
      discard user.socket.send(load_history(@"room"))
      let joined = build_message:
        italic: text user.name
        italic: text " has joined the room"
      chatrooms[@"room"].send_all(joined)
      while user.socket.ready_state == Open:
        let sent_message = (await user.socket.receive_str_packet()).parse_json["message"]
        db.exec(sql"INSERT INTO messages VALUES (?, ?, ?)", @"room", user.name, sent_message.get_str())
        discard user.socket.send(chat_input())
        let reply = build_message:
          bold: text user.name
          text ": " & sent_message.get_str()
        chatrooms[@"room"].send_all(reply)
    except:
      chatrooms[@"room"].excl(user)
      let left = build_message:
        italic: text user.name
        italic: text " has left the room"
      chatrooms[@"room"].send_all(left)
    resp ""
