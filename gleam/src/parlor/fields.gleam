//// Forgiving input, as agents send it: query parameters, a form body (create and join), a JSON
//// body, or (for messages) raw text. What JavaScript does with odd values is copied where an
//// agent could plausibly hit it: numbers where strings are expected, `null`, whitespace.

import gleam/bit_array
import gleam/dict.{type Dict}
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/float
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}

import gleam/string
import parlor/fail.{type HttpError}

/// A field's value. JSON can carry more than text; `Other` holds what JavaScript's String()
/// makes of it (3600 -> "3600", true -> "true").
pub type Value {
  Text(String)
  Other(String)
  Null
}

pub type Fields {
  Fields(values: Dict(String, Value), json: Bool)
}

pub fn parse(
  raw: String,
  content_type: String,
  query: List(#(String, String)),
  form form: Bool,
) -> Result(Fields, HttpError) {
  let base = to_values(query)
  let ct = string.lowercase(content_type)
  let starts_brace = string.starts_with(js_trim_start(raw), "{")
  case
    form
    && raw != ""
    && string.contains(ct, "x-www-form-urlencoded")
    && !starts_brace
  {
    True -> Ok(Fields(dict.merge(base, to_values(parse_query(raw))), False))
    False -> {
      let says_json = string.contains(ct, "json")
      case raw != "" && { says_json || starts_brace } {
        False -> Ok(Fields(base, False))
        True ->
          case json.parse(raw, decode.dynamic) {
            Ok(value) ->
              case object_entries(value) {
                Some(entries) -> Ok(Fields(dict.merge(base, entries), True))
                None -> Ok(Fields(base, False))
              }
            Error(_) if says_json -> Error(fail.bare(400, "invalid JSON body"))
            Error(_) -> Ok(Fields(base, False))
          }
      }
    }
  }
}

fn to_values(pairs: List(#(String, String))) -> Dict(String, Value) {
  list.fold(pairs, dict.new(), fn(d, pair) {
    dict.insert(d, pair.0, Text(pair.1))
  })
}

// A JSON object (or array, which JavaScript spreads by index) as fields; None for anything else.
fn object_entries(value: Dynamic) -> Option(Dict(String, Value)) {
  case decode.run(value, decode.dict(decode.string, decode.dynamic)) {
    Ok(d) -> Some(dict.map_values(d, fn(_, v) { classify(v) }))
    Error(_) ->
      case decode.run(value, decode.list(decode.dynamic)) {
        Ok(items) ->
          items
          |> list.index_map(fn(v, i) { #(int.to_string(i), classify(v)) })
          |> dict.from_list
          |> Some
        Error(_) -> None
      }
  }
}

fn classify(v: Dynamic) -> Value {
  case decode.run(v, decode.string) {
    Ok(s) -> Text(s)
    Error(_) ->
      case js_string(v) {
        Some(s) -> Other(s)
        None -> Null
      }
  }
}

// JavaScript's String() of a JSON value; None for null.
fn js_string(v: Dynamic) -> Option(String) {
  let bool = fn(b) {
    case b {
      True -> "true"
      False -> "false"
    }
  }
  let decoder =
    decode.one_of(decode.string, [
      decode.int |> decode.map(int.to_string),
      decode.float |> decode.map(js_number),
      decode.bool |> decode.map(bool),
      decode.list(decode.dynamic)
        |> decode.map(fn(items) {
          items
          |> list.map(fn(i) { js_string(i) |> option.unwrap("") })
          |> string.join(",")
        }),
      decode.dict(decode.string, decode.dynamic)
        |> decode.map(fn(_) { "[object Object]" }),
    ])
  decode.run(v, decoder) |> option.from_result
}

fn js_number(f: Float) -> String {
  let whole = float.truncate(f)
  case int.to_float(whole) == f && float.absolute_value(f) <. 1.0e21 {
    True -> int.to_string(whole)
    False -> float.to_string(f)
  }
}

/// JavaScript `String(f.name ?? '')`.
pub fn text(fields: Fields, name: String) -> String {
  case dict.get(fields.values, name) {
    Ok(Text(s)) | Ok(Other(s)) -> s
    _ -> ""
  }
}

/// JavaScript `f.name ?? f.other`: present and not null.
pub fn get(fields: Fields, name: String) -> Option(Value) {
  case dict.get(fields.values, name) {
    Ok(Null) | Error(_) -> None
    Ok(v) -> Some(v)
  }
}

pub fn value_text(v: Value) -> String {
  case v {
    Text(s) | Other(s) -> s
    Null -> ""
  }
}

/// JavaScript truthiness of a field: absent, null, "", 0, false and NaN are false.
pub fn truthy(fields: Fields, name: String) -> Bool {
  case dict.get(fields.values, name) {
    Ok(Text(s)) -> s != ""
    Ok(Other(s)) -> !list.contains(["0", "-0", "false", "NaN"], s)
    _ -> False
  }
}

/// The message text of a post or a close: JSON {"body": "..."}, or the raw body.
pub fn body(fields: Fields, raw: String) -> String {
  case fields.json, dict.get(fields.values, "body") {
    True, Ok(Text(s)) -> js_trim_end(s)
    True, _ -> ""
    False, _ -> js_trim_end(raw)
  }
}

/// Handles: trimmed, one leading @ dropped, anything but letters, digits, `.`, `_` and `-`
/// replaced by `-` (per UTF-16 unit, as JavaScript counts), at most 32 characters.
pub fn clean_handle(raw: String, fallback: String) -> String {
  let trimmed = js_trim_start(js_trim_end(raw))
  let trimmed = case string.starts_with(trimmed, "@") {
    True -> string.drop_start(trimmed, 1)
    False -> trimmed
  }
  let cleaned =
    string.to_utf_codepoints(trimmed)
    |> list.map(fn(cp) {
      let c = string.utf_codepoint_to_int(cp)
      case is_handle_char(c), c > 0xFFFF {
        True, _ -> string.from_utf_codepoints([cp])
        False, True -> "--"
        False, False -> "-"
      }
    })
    |> string.concat
    |> string.slice(0, 32)
  case cleaned {
    "" -> fallback
    h -> h
  }
}

pub fn is_handle_char(c: Int) -> Bool {
  { c >= 0x61 && c <= 0x7A }
  || { c >= 0x41 && c <= 0x5A }
  || { c >= 0x30 && c <= 0x39 }
  || c == 0x2E
  || c == 0x5F
  || c == 0x2D
}

/// Lowercases ASCII letters only, as a case-insensitive JavaScript regex compares them.
pub fn ascii_lower(s: String) -> String {
  string.to_utf_codepoints(s)
  |> list.map(fn(cp) {
    let c = string.utf_codepoint_to_int(cp)
    case c >= 0x41 && c <= 0x5A {
      True -> {
        let assert Ok(lower) = string.utf_codepoint(c + 32)
        lower
      }
      False -> cp
    }
  })
  |> string.from_utf_codepoints
}

// ---- JavaScript's notion of whitespace (trim, trimEnd, \s) ------------------------------------

fn is_js_space(c: Int) -> Bool {
  case c {
    0x09
    | 0x0A
    | 0x0B
    | 0x0C
    | 0x0D
    | 0x20
    | 0xA0
    | 0x1680
    | 0x2028
    | 0x2029
    | 0x202F
    | 0x205F
    | 0x3000
    | 0xFEFF -> True
    _ -> c >= 0x2000 && c <= 0x200A
  }
}

pub fn js_trim_start(s: String) -> String {
  string.to_utf_codepoints(s)
  |> list.drop_while(fn(cp) { is_js_space(string.utf_codepoint_to_int(cp)) })
  |> string.from_utf_codepoints
}

pub fn js_trim_end(s: String) -> String {
  string.to_utf_codepoints(s)
  |> list.reverse
  |> list.drop_while(fn(cp) { is_js_space(string.utf_codepoint_to_int(cp)) })
  |> list.reverse
  |> string.from_utf_codepoints
}

pub fn is_blank(s: String) -> Bool {
  js_trim_start(s) == ""
}

// ---- query strings, as URLSearchParams reads them: lenient, `+` is a space --------------------

pub fn parse_query(query: String) -> List(#(String, String)) {
  query
  |> string.split("&")
  |> list.filter(fn(part) { part != "" })
  |> list.map(fn(part) {
    case string.split_once(part, "=") {
      Ok(#(k, v)) -> #(unescape(k), unescape(v))
      Error(_) -> #(unescape(part), "")
    }
  })
}

fn unescape(s: String) -> String {
  s
  |> string.replace("+", " ")
  |> bit_array.from_string
  |> percent_decode(<<>>)
  |> lossy_utf8
}

fn percent_decode(bits: BitArray, acc: BitArray) -> BitArray {
  case bits {
    <<>> -> acc
    <<"%":utf8, a, b, rest:bits>> ->
      case hex(a), hex(b) {
        Ok(x), Ok(y) -> percent_decode(rest, <<acc:bits, { x * 16 + y }>>)
        _, _ -> percent_decode(<<a, b, rest:bits>>, <<acc:bits, "%":utf8>>)
      }
    <<byte, rest:bits>> -> percent_decode(rest, <<acc:bits, byte>>)
    _ -> acc
  }
}

fn hex(c: Int) -> Result(Int, Nil) {
  case c {
    _ if c >= 0x30 && c <= 0x39 -> Ok(c - 0x30)
    _ if c >= 0x41 && c <= 0x46 -> Ok(c - 0x41 + 10)
    _ if c >= 0x61 && c <= 0x66 -> Ok(c - 0x61 + 10)
    _ -> Error(Nil)
  }
}

/// Bytes to text, every invalid UTF-8 sequence replaced by U+FFFD, as Node decodes a body.
@external(erlang, "parlor_ffi", "lossy_utf8")
pub fn lossy_utf8(bits: BitArray) -> String

/// The first `n` UTF-16 units of `s`, as JavaScript's slice counts; a character that would be
/// split in half is left out.
pub fn utf16_slice(s: String, n: Int) -> String {
  string.to_utf_codepoints(s)
  |> take_units(n, [])
  |> string.from_utf_codepoints
}

fn take_units(cps, n, acc) {
  case cps {
    [] -> list.reverse(acc)
    [cp, ..rest] -> {
      let units = case string.utf_codepoint_to_int(cp) > 0xFFFF {
        True -> 2
        False -> 1
      }
      case units <= n {
        True -> take_units(rest, n - units, [cp, ..acc])
        False -> list.reverse(acc)
      }
    }
  }
}
