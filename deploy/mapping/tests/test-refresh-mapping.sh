#!/bin/sh
# Exercise the escalation in deploy/mapping/refresh-mapping.sh without a portal.
#
# The wrapper decides whether a run that could not reach the portal is a mere
# deferral or something the owner has to hear about, so what is tested here is
# when it stays quiet and when it mails: not on the first failure, once past
# DEFERRED_HOURS, no more than once a day, immediately on a failure of our own,
# and exactly once when the portal comes back.
set -eu

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
wrapper="$here/../refresh-mapping.sh"
work=$(mktemp -d "${TMPDIR:-/tmp}/refresh-mapping-test.XXXXXX")
trap 'rm -rf "$work"' EXIT INT TERM

mkdir -p "$work/tools" "$work/state" "$work/site"
sent=$work/sent
: > "$sent"

# A stand-in for the portal-facing publisher: the test decides which status it
# reports, and the wrapper is expected to act on that status alone.
cat > "$work/tools/publish-mapping.py" <<'PY'
import os, sys
status = int(os.environ.get("FAKE_STATUS", "0"))
if status:
    print("deferred: asking the portal for the archive identity failed 3 times, "
          "last: HTTP Error 500: Internal Server Error")
    sys.exit(status)
print("up to date: %s describes 3650274a207ddd1:0" % sys.argv[1])
PY

cat > "$work/sendmail" <<'SH'
#!/bin/sh
cat >> "$SENT"
SH
chmod +x "$work/sendmail"

cat > "$work/site/jdf-lines.json" <<'JSON'
{"archive": {"lastModified": "2026-11-25T21:02:32+00:00"}, "lines": {}}
JSON

failures=0
check() {
    if [ "$2" = "$3" ]; then
        printf 'ok   %s\n' "$1"
    else
        printf 'FAIL %s: expected %s, got %s\n' "$1" "$3" "$2"
        failures=$((failures + 1))
    fi
}

run() {
    # The wrapper is expected to fail sometimes, which `set -e` would take as a
    # reason to stop testing.
    rc=0
    SENT=$sent FAKE_STATUS=$1 \
    VDV_LIVE_MAPPING=$work/site/jdf-lines.json \
    VDV_LIVE_TOOLS=$work/tools \
    VDV_LIVE_STATE_DIR=$work/state \
    VDV_LIVE_SENDMAIL=$work/sendmail \
    sh "$wrapper" >> "$work/out" 2>&1 || rc=$?
    echo "$rc"
}

mails() {
    grep -c '^Subject:' "$sent" || true
}

reset() {
    : > "$sent"
    rm -f "$work/state/state"
}

# A short outage stays quiet: eleven deferrals, no mail, exit 0 so the unit is
# never recorded as failed.
reset
status=0
i=0
while [ "$i" -lt 11 ]; do
    status=$(run 75)
    i=$((i + 1))
done
check "eleven deferrals exit 0" "$status" 0
check "eleven deferrals send no mail" "$(mails)" 0
check "deferrals are counted" "$(sed -n 's/^deferred=//p' "$work/state/state")" 11

# The twelfth is the first one worth a mail, and it says how long it has been.
status=$(run 75)
check "twelfth deferral exits 0" "$status" 0
check "twelfth deferral mails once" "$(mails)" 1
check "the mail names the duration" "$(grep -c 'unverified for 12h' "$sent")" 1

# Still deferred, but the owner was told minutes ago: quiet again.
status=$(run 75)
check "the next deferral is quiet" "$(mails)" 1
check "deferred keeps counting" "$(sed -n 's/^deferred=//p' "$work/state/state")" 13

# A failure of our own is not a deferral: the unit must fail, and it mails.
reset
status=$(run 1)
check "a real failure exits non-zero" "$status" 1
check "a real failure mails once" "$(mails)" 1
check "the mail says which status" "$(grep -c 'failed with status 1' "$sent")" 1

# And it does not repeat that mail every hour.
run 1 > /dev/null
check "a repeated failure is quiet" "$(mails)" 1

# Recovery is announced once, and the counter starts from zero again.
status=$(run 0)
check "recovery exits 0" "$status" 0
check "recovery mails once" "$(mails)" 2
check "recovery is announced" "$(grep -c 'verified again' "$sent")" 1
check "the counter is reset" "$(sed -n 's/^deferred=//p' "$work/state/state")" 0

status=$(run 0)
check "an ordinary run is quiet" "$(mails)" 2
check "an ordinary run exits 0" "$status" 0

if [ "$failures" -ne 0 ]; then
    printf '\n%s check(s) failed; wrapper output:\n' "$failures"
    sed 's/^/    /' "$work/out"
    exit 1
fi
echo "all checks passed"
