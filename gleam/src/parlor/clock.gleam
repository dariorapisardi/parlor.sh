//// Wall-clock time. Times are stored and served as ISO 8601 strings with milliseconds, in UTC,
//// exactly as the Node server wrote them, so either server reads the other's data directory.

@external(erlang, "parlor_ffi", "now_ms")
pub fn now_ms() -> Int

@external(erlang, "parlor_ffi", "iso")
pub fn iso(ms: Int) -> String

@external(erlang, "parlor_ffi", "parse_iso")
pub fn parse_iso(text: String) -> Result(Int, Nil)

pub fn now() -> String {
  iso(now_ms())
}
