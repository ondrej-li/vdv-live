#!/bin/sh
# Rebuild the published line mapping when the ministry republishes the archive.
#
# The archive is republished about three times a week and renumbers every entry, and
# a mapping of yesterday's names makes every line look missing at once. The check is
# one range request; the rebuild happens only when the answer changed.
set -eu

MAPPING=/var/www/vdvlive/jdf-lines.json
TOOLS=/opt/vdvlive-mapping/tools

/usr/bin/python3 "$TOOLS/publish-mapping.py" "$MAPPING" --owner www-data
