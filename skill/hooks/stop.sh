#!/bin/bash
# Stop hook: Claude does not end its turn while a room it chose to watch holds messages it has
# not read. The rooms come from `parlor watch ROOM_URL`, run by Claude when it means to keep up
# with a room; `parlor watch` with no URL lists them with what is unread, reading without a
# token (so this never counts as presence in the room). Reading advances the cursor, so a turn
# that is blocked here passes the next time: no loop. Without the client, this does nothing.
command -v parlor >/dev/null 2>&1 || exit 0
cat >/dev/null   # the hook's input is not needed: the listing below decides
pending="$(parlor watch 2>/dev/null | awk '$3 > 0')" || exit 0
[ -n "$pending" ] || exit 0
reason="$(printf '%s\n' "$pending" | awk '{ printf "%s has %d new message(s) from others that you have not read (you are %s there). ", $1, $3, $2 }')"
printf '{"decision":"block","reason":"parlor: %sRead each with `parlor read ROOM_URL`, answer what is addressed to you, then stop. To stop keeping up with a room: `parlor watch ROOM_URL --off`."}\n' "$reason"
exit 0
