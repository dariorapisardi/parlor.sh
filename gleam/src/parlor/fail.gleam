//// Errors are JSON {"error", "code", "hint"} with a matching HTTP status (room.md, "Other
//// calls"). Anything that refuses a request returns one of these; the web layer renders it.

import gleam/option.{type Option, None, Some}
import gleam/string

pub type HttpError {
  HttpError(
    status: Int,
    error: String,
    hint: Option(String),
    headers: List(#(String, String)),
  )
}

pub fn new(status: Int, error: String, hint: String) -> HttpError {
  HttpError(status:, error:, hint: Some(hint), headers: [])
}

pub fn bare(status: Int, error: String) -> HttpError {
  HttpError(status:, error:, hint: None, headers: [])
}

pub fn with_headers(
  e: HttpError,
  headers: List(#(String, String)),
) -> HttpError {
  HttpError(..e, headers:)
}

/// The stable, machine-readable name of an error: what a client matches on, where `error` is
/// written for people and `hint` for agents. One table, so the set of codes is this function.
pub fn code(e: HttpError) -> String {
  let starts = fn(prefix) { string.starts_with(e.error, prefix) }
  case e.error {
    "invalid JSON body" -> "invalid_json"
    "invalid ttl value" -> "invalid_ttl"
    "empty message" -> "empty_message"
    "message contains a room token" -> "token_in_message"
    "not a room URL" -> "not_a_room_url"
    "cursor is ahead of the room" -> "cursor_ahead"
    "missing Authorization: Bearer TOKEN header" -> "missing_token"
    "unknown token for this room" | "unknown token for this alias" ->
      "unknown_token"
    "room is full" -> "room_full"
    "message does not fit" -> "message_does_not_fit"
    "participant limit reached" -> "participant_limit"
    "no such room" | "no such room on this server" -> "no_such_room"
    "no such alias" -> "no_such_alias"
    "the room this alias points to no longer exists" -> "alias_room_gone"
    "not found" -> "not_found"
    "you are already in this room" -> "already_joined"
    "room is closed" -> "room_closed"
    "room is removed" -> "room_removed"
    "room was purged" -> "room_purged"
    "body too large" -> "body_too_large"
    "internal error" -> "internal_error"
    "no room for more rooms" | "no room for more aliases" -> "server_full"
    _ ->
      case
        starts("only the host can"),
        starts("no participant"),
        starts("cannot reply to"),
        starts("too many ")
      {
        True, _, _, _ -> "not_host"
        _, True, _, _ -> "no_such_participant"
        _, _, True, _ -> "no_such_message"
        _, _, _, True -> "rate_limited"
        _, _, _, _ ->
          case e.status {
            400 -> "bad_request"
            401 -> "unauthorized"
            403 -> "forbidden"
            404 -> "not_found"
            410 -> "gone"
            _ -> "error"
          }
      }
  }
}
