//// Errors are JSON {"error", "hint"} with a matching HTTP status (room.md, "Other calls").
//// Anything that refuses a request returns one of these; the web layer renders it.

import gleam/option.{type Option, None, Some}

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
