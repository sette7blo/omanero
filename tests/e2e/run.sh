#!/bin/bash
# End-to-end check of the browser extension in a real, headless browser:
#   BROWSER=/opt/brave-bin/brave NODE=node tests/e2e/run.sh
# It uses a throwaway profile and state dir and serves a fake x.com page from
# memory, so the real profile, the real wallet state and the real site are
# never touched. SIDE_PROFILE=1 checks that the wallet turns away a browser
# that is not on the main profile, where the extension must show nothing. Expect two pills on the profile, then on the feed badges for Ann and Dave
# (not Bob, whose address was only in a post), two page entries, a request for @Ann_B,
# and an empty page once the browser has closed. MODE=github runs the GitHub
# case instead: a profile bio, then a forked repo whose manifest.json and README
# each name an address, and a tip from the manifest's control.
set -u
T=$(mktemp -d)
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
EXT=$ROOT/extension/x
CLI=$ROOT/bin/omanero
NODE=${NODE:-node}
BROWSER=${BROWSER:-/opt/brave-bin/brave}
PORT=9377
export XDG_STATE_HOME=$T/state OMANERO_NO_SUMMON=1
# The throwaway profile counts as a side profile unless told otherwise.
[[ -n ${SIDE_PROFILE:-} ]] || export OMANERO_ANY_PROFILE=1
mkdir -p $T/profile/NativeMessagingHosts
cat > $T/profile/NativeMessagingHosts/io.github.sette7blo.omanero.json <<JSON
{"name":"io.github.sette7blo.omanero","description":"omanero wallet","path":"$CLI","type":"stdio",
 "allowed_origins":["chrome-extension://lkdojiemjmekaibbklkoheninffafick/"]}
JSON
"$BROWSER" --headless=new --user-data-dir=$T/profile --load-extension=$EXT \
  --remote-debugging-port=$PORT --no-first-run --disable-gpu about:blank >$T/brave.log 2>&1 &
BRAVE=$!
for i in $(seq 40); do curl -s -o /dev/null http://127.0.0.1:$PORT/json/version && break; sleep 0.5; done
mkfifo $T/ctl
$NODE "$(dirname "$0")/cdp.js" $PORT ${MODE:-tip} < $T/ctl > $T/cdp.out 2>&1 &
exec 9> $T/ctl
for i in $(seq 40); do grep -q "READY\|FAILED" $T/cdp.out 2>/dev/null && break; sleep 0.5; done
cat $T/cdp.out
show() { $CLI --json status | python3 -c "import json,sys; d=json.load(sys.stdin); print('$1 page', [(i['handle'], i['source'], i['address'][:6]) for i in d['page']]); r=d['request']; print('$1 request', r and (r['recipient'], r['description'], r['address'][:6]))"; }
show open
pgrep -af "omanero chrome-extension" | cut -c1-120
echo stop >&9; exec 9>&-
for i in $(seq 20); do kill -0 $BRAVE 2>/dev/null || break; sleep 0.5; done
kill $BRAVE 2>/dev/null
sleep 1
show closed
grep -iE "load-extension|not allowed|extension.*(error|fail)" $T/brave.log | head -5
rm -rf "$T"
