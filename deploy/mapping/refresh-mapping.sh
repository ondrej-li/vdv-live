#!/bin/sh
# Rebuild the published line mapping when the ministry republishes the archive.
#
# The archive is republished about three times a week and renumbers every entry, and
# a mapping of yesterday's names makes every line look missing at once. The check is
# one range request; the rebuild happens only when the answer changed.
#
# The portal is a ministry IIS box: while it republishes it answers 500, or stops
# answering, for hours. That is not a broken unit and must not be reported as one -
# a poll that could not read the archive exits EX_TEMPFAIL (75), which the unit
# lists in SuccessExitStatus. What does matter is how long it lasts: past
# DEFERRED_HOURS the published mapping is no longer merely old, it is unverified
# against whatever the portal now offers, so this script mails the owner once a day
# until the portal answers again. Failures that are ours (a mapping with too few
# lines, a write error) still exit non-zero, so systemd records the unit as failed
# and the host report says so.
set -u

# The defaults are what the unit runs with; the overrides exist so the escalation
# logic below can be exercised without a portal, a web root or a mail server.
MAPPING=${VDV_LIVE_MAPPING:-/var/www/vdvlive/jdf-lines.json}
TOOLS=${VDV_LIVE_TOOLS:-/opt/vdvlive-mapping/tools}
STATE_DIR=${VDV_LIVE_STATE_DIR:-/var/lib/vdvlive-mapping}
SENDMAIL=${VDV_LIVE_SENDMAIL:-/usr/sbin/sendmail}
STATE=$STATE_DIR/state
MAIL_TO=admin@ondralinek.cz
MAIL_FROM=alerts@ondralinek.cz
DEFERRED=75
DEFERRED_HOURS=12
REMIND_AFTER=86400

mkdir -p "$STATE_DIR"

state_value() {
    [ -f "$STATE" ] || return 1
    sed -n "s/^$1=//p" "$STATE" | tail -1
}

state_set() {
    kept=$(sed "/^$1=/d" "$STATE" 2>/dev/null || true)
    printf '%s\n%s=%s\n' "$kept" "$1" "$2" | sed '/^$/d' > "$STATE.tmp"
    mv "$STATE.tmp" "$STATE"
}

mail() {
    {
        printf 'From: vdvlive-mapping <%s>\n' "$MAIL_FROM"
        printf 'To: %s\n' "$MAIL_TO"
        printf 'Subject: %s\n' "$1"
        printf 'Auto-Submitted: auto-generated\n\n'
        printf '%s\n' "$2"
        # -f so the envelope matches the From header: the box submits from root,
        # and a Return-Path of root@ for a message signed as alerts@ is the kind
        # of mismatch that shows up in someone's DMARC report later.
    } | "$SENDMAIL" -i -f "$MAIL_FROM" -t
}

describe_mapping() {
    /usr/bin/python3 - "$MAPPING" <<'PY' 2>/dev/null || echo "no published mapping"
import json, os, sys, time
path = sys.argv[1]
try:
    archive = json.load(open(path, encoding="utf-8")).get("archive") or {}
except (OSError, ValueError):
    archive = {}
if not os.path.exists(path):
    print("no published mapping")
else:
    print("published mapping: built %s, from the archive published %s"
          % (time.strftime("%Y-%m-%d %H:%M %Z", time.localtime(os.path.getmtime(path))),
             archive.get("lastModified") or "unknown"))
PY
}

output=$({ /usr/bin/python3 "$TOOLS/publish-mapping.py" "$MAPPING" --owner www-data; } 2>&1)
status=$?
printf '%s\n' "$output"

deferred=$(state_value deferred || echo 0)
mailed=$(state_value mailed || echo 0)
last_mail=$(state_value last_mail || echo 0)
now=$(date +%s)
detail=$(printf '%s\n' "$output" | tail -1)

if [ "$status" -eq "$DEFERRED" ]; then
    deferred=$((deferred + 1))
    state_set deferred "$deferred"
    if [ "$deferred" -ge "$DEFERRED_HOURS" ] && [ $((now - last_mail)) -ge "$REMIND_AFTER" ]; then
        mail "vdv: the timetable mapping is unverified for ${deferred}h" \
"The ministry portal has not answered for the timetable archive through ${deferred}
consecutive hourly checks, so the line mapping on vdv.ondralinek.cz could not be
checked against what the portal now offers.

$(describe_mapping)
last error: $detail
journal: journalctl -u vdvlive-mapping -n 50

The site keeps serving the last mapping that was verified, so nothing is down. If
this lasts past a republication, lines can start answering \"not in the published
timetable\"; nothing needs doing until then, and nothing at all if the portal
recovers - you will get one mail saying so."
        state_set mailed 1
        state_set last_mail "$now"
        echo "==> mailed: unverified for ${deferred}h"
    else
        echo "==> deferred ${deferred}h (mailing at ${DEFERRED_HOURS}h, then daily)"
    fi
    exit 0
fi

if [ "$status" -ne 0 ]; then
    state_set deferred 0
    echo "==> failed with status $status"
    if [ $((now - last_mail)) -ge "$REMIND_AFTER" ]; then
        mail "vdv: the mapping refresh failed" \
"The hourly mapping refresh on vdv.ondralinek.cz failed with status $status. That is
not the portal being unavailable - a deferral is handled separately - so this one
needs a look.

$(describe_mapping)
last line: $detail
journal: journalctl -u vdvlive-mapping -n 50

The site keeps serving the previous mapping until this succeeds."
        state_set mailed 1
        state_set last_mail "$now"
        echo "==> mailed: failure"
    fi
    exit "$status"
fi

state_set deferred 0
if [ "$mailed" = "1" ]; then
    mail "vdv: the mapping is verified again" \
"The ministry portal is answering again and the mapping on vdv.ondralinek.cz has
been checked against it.

$(describe_mapping)"
    echo "==> mailed: recovered"
fi
state_set mailed 0
exit 0
