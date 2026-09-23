//// Every tunable, read once from the environment. The names and defaults are the original Node
//// server's: they are part of the contract (README, "Run your own"). 0 means "no limit" for the
//// caps and rates.

import envoy
import gleam/float
import gleam/int
import gleam/result
import gleam/string

pub type Config {
  Config(
    root: String,
    port: Int,
    host: String,
    public_url: String,
    data_dir: String,
    cli_path: String,
    ttl: Int,
    ttl_max: Int,
    ttl_min: Int,
    sweep_every: Int,
    drain_grace_ms: Int,
    max_body: Int,
    max_messages: Int,
    max_participants: Int,
    max_rooms: Int,
    max_room_bytes: Int,
    max_wait: Float,
    max_waiters_per_client: Int,
    max_waiters: Int,
    rate_create: Int,
    rate_post: Int,
    trust_proxy: Bool,
    test_tokens: String,
  )
}

pub fn from_env() -> Config {
  // docs/, skill/ and data/ resolve from the working directory (the repository root, or
  // /opt/parlor in production), unless PARLOR_ROOT says otherwise.
  let root = get("PARLOR_ROOT", ".")
  let path = fn(p) { root <> "/" <> p }
  Config(
    root:,
    port: number("PORT", 8787),
    host: get("HOST", "0.0.0.0"),
    public_url: get("PUBLIC_URL", ""),
    data_dir: get("DATA_DIR", path("data")),
    cli_path: get("CLI_PATH", path("skill/parlor/parlor")),
    ttl: seconds(get("TTL", ""), 30 * 86_400),
    ttl_max: seconds(get("TTL_MAX", ""), 0),
    ttl_min: seconds(get("TTL_MIN", ""), 60),
    sweep_every: seconds(get("SWEEP_EVERY", ""), 30),
    drain_grace_ms: number("DRAIN_GRACE_MS", 250),
    max_body: number("MAX_BODY", 8 * 1024),
    max_messages: number("MAX_MESSAGES", 10_000),
    max_participants: number("MAX_PARTICIPANTS", 0),
    max_rooms: number("MAX_ROOMS", 0),
    max_room_bytes: number("MAX_ROOM_BYTES", 0),
    max_wait: get("MAX_WAIT", "")
      |> parse_number
      |> result.unwrap(55.0),
    max_waiters_per_client: number("MAX_WAITERS_PER_CLIENT", 100),
    max_waiters: number("MAX_WAITERS", 0),
    rate_create: number("RATE_CREATE", 0),
    rate_post: number("RATE_POST", 0),
    trust_proxy: get("TRUST_PROXY", "") == "1",
    // Test only: a file that receives every issued token.
    test_tokens: get("PARLOR_TEST_TOKENS", ""),
  )
}

// Node reads `env.X || default`: an empty variable is the default.
fn get(name: String, default: String) -> String {
  case envoy.get(name) {
    Ok("") | Error(_) -> default
    Ok(value) -> value
  }
}

fn number(name: String, default: Int) -> Int {
  case get(name, "") |> parse_number {
    Ok(n) -> float.round(n)
    Error(_) -> default
  }
}

/// A decimal number as JavaScript's Number() reads one from a query or form field: "5", "1.5",
/// " 7 ", "-3". Anything else is an error (Node's NaN).
pub fn parse_number(text: String) -> Result(Float, Nil) {
  let text = string.trim(text)
  case int.parse(text) {
    Ok(n) -> Ok(int.to_float(n))
    Error(_) ->
      case float.parse(text) {
        Ok(f) -> Ok(f)
        // Gleam wants a digit on both sides of the point; JavaScript takes "5." and ".5".
        Error(_) ->
          case string.ends_with(text, "."), string.starts_with(text, ".") {
            True, _ -> float.parse(text <> "0")
            _, True -> float.parse("0" <> text)
            _, _ -> Error(Nil)
          }
      }
  }
}

/// Seconds ("3600") or a number with a unit ("90m", "72h", "7d"). `fallback` when it is neither.
pub fn seconds(value: String, fallback: Int) -> Int {
  parse_seconds(value) |> result.unwrap(fallback)
}

pub fn parse_seconds(value: String) -> Result(Int, Nil) {
  let value = string.trim(value)
  let #(number, unit) = case string.last(value) {
    Ok(last) ->
      case string.lowercase(last) {
        "s" | "m" | "h" | "d" -> #(
          string.drop_end(value, 1),
          string.lowercase(last),
        )
        _ -> #(value, "")
      }
    Error(_) -> #(value, "")
  }
  let multiplier = case unit {
    "m" -> 60
    "h" -> 3600
    "d" -> 86_400
    _ -> 1
  }
  // Digits, optionally a point and more digits, then optional spaces before the unit.
  let number = string.trim_end(number)
  use n <- result.try(decimal(number))
  Ok(float.round(n *. int.to_float(multiplier)))
}

fn decimal(text: String) -> Result(Float, Nil) {
  let digits = fn(s) { s != "" && string.to_graphemes(s) |> all_digits }
  case string.split_once(text, ".") {
    Ok(#(whole, fraction)) ->
      case digits(whole) && digits(fraction) {
        True -> float.parse(whole <> "." <> fraction)
        False -> Error(Nil)
      }
    Error(_) ->
      case digits(text) {
        True -> int.parse(text) |> result.map(int.to_float)
        False -> Error(Nil)
      }
  }
}

fn all_digits(chars: List(String)) -> Bool {
  case chars {
    [] -> True
    [c, ..rest] ->
      case c {
        "0" | "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9" ->
          all_digits(rest)
        _ -> False
      }
  }
}

/// "30 days", "1 hour", "90 minutes", "45 seconds".
pub fn human_duration(s: Int) -> String {
  case s % 86_400, s % 3600, s % 60 {
    0, _, _ -> plural(s / 86_400, "day")
    _, 0, _ -> plural(s / 3600, "hour")
    // The Node server said "1 minutes"; kept, so the pages did not change with the port.
    _, _, 0 -> int.to_string(s / 60) <> " minutes"
    _, _, _ -> int.to_string(s) <> " seconds"
  }
}

fn plural(n: Int, unit: String) -> String {
  int.to_string(n)
  <> " "
  <> unit
  <> case n {
    1 -> ""
    _ -> "s"
  }
}
