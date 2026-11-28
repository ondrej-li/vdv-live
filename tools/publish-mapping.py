#!/usr/bin/env python3
"""Keep the published line mapping in step with the archive it describes.

The archive is republished about three times a week and renumbers every entry when
it is, which leaves a mapping of yesterday's names pointing at entries that now hold
other lines. An app that reads today's index and yesterday's mapping then answers
"not in the published timetable" for every line at once - which is what a reader
sees as a timetable feature that has stopped working.

The mapping therefore belongs to one publication and has to be rebuilt when that
publication changes. This is that rebuild, for the copy the project serves:

    python3 tools/publish-mapping.py /var/www/vdvlive/jdf-lines.json

One range request says which publication the portal is offering; if it is the one
the file already names, nothing else happens. Otherwise the archive is downloaded,
`tools/jdf_lines_mapping.py` derives the mapping from it, and the file is replaced
in one rename - so a reader of the site sees either the old mapping or the new one,
never half of either.

Exit status is 0 both when the file was rebuilt and when it was already current,
and 75 (EX_TEMPFAIL) when the portal could not be read at all - see `defer`.
"""

import argparse
import email.utils
import http.client
import json
import os
import socket
import sys
import tempfile
import time
import urllib.error
import urllib.request
import zipfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import jdf_lines_mapping  # noqa: E402

ARCHIVE_URL = "https://portal.cisjr.cz/pub/JDF/JDF.zip"
USER_AGENT = "VdvLive-mapping/1.0 (+https://github.com/ondrej-li/vdv-live)"

# EX_TEMPFAIL: the portal did not answer usefully, so there is nothing to decide
# and nothing that needs a human. The unit treats it as success and tries again on
# the next timer run; refresh-mapping.sh counts the hours and escalates on its own.
DEFERRED = 75

# Answers that mean "ask again later" rather than "this request or this archive is
# wrong". 5xx is the portal itself: it is a ministry IIS box and answers 500 for
# hours at a time around a republication.
TRANSIENT_STATUS = {408, 425, 429, 500, 502, 503, 504}

# Enough attempts to ride out a blip, few enough to stay inside the unit's
# TimeoutStartSec even when every attempt has to time out.
ATTEMPTS = 3
BACKOFF = (5, 30)


class Defer(Exception):
    """The portal could not be read; the next timer run tries again."""


def transient(error):
    """True for a failure that is worth retrying, false for one that is not."""
    if isinstance(error, urllib.error.HTTPError):
        return error.code in TRANSIENT_STATUS
    return isinstance(error, (urllib.error.URLError, http.client.HTTPException,
                              ConnectionError, socket.timeout, TimeoutError))


def attempt(what, operation):
    """Run `operation`, retrying while the failure looks transient.

    Raises Defer once the attempts are spent, so a poll that never reached the
    portal is reported as a deferral instead of as a broken unit.
    """
    for number in range(1, ATTEMPTS + 1):
        try:
            return operation()
        except Exception as error:              # noqa: BLE001 - classified below
            if not transient(error):
                raise
            if number == ATTEMPTS:
                raise Defer(f"{what} failed {ATTEMPTS} times, last: {error}") from error
            wait = BACKOFF[min(number - 1, len(BACKOFF) - 1)]
            print(f"{what} failed ({error}); retrying in {wait}s", flush=True)
            time.sleep(wait)
    raise AssertionError("unreachable")


def iso_date(http_date):
    """`Wed, 11 Nov 2026 20:48:43 GMT` as `2026-11-11T20:48:43+00:00`.

    The app reads the mapping's date with an ISO 8601 parser, which is also what
    `index-version.json` holds, so the two can be compared without a second format.
    """
    if not http_date:
        return None
    try:
        return email.utils.parsedate_to_datetime(http_date).isoformat()
    except (TypeError, ValueError):
        return None


def identity(url=ARCHIVE_URL):
    """The portal's answer to "which archive are you offering", for one byte.

    The headers carry everything that identifies the file, and the app records the
    same three things when it reads the index, so the two can be compared.
    """
    request = urllib.request.Request(
        url,
        headers={"Range": "bytes=0-0", "User-Agent": USER_AGENT},
    )

    def once():
        with urllib.request.urlopen(request, timeout=60) as response:
            headers = response.headers
            content_range = headers.get("Content-Range", "")
            size = int(content_range.rsplit("/", 1)[-1]) if "/" in content_range else -1
            return {
                "etag": headers.get("ETag"),
                "lastModified": iso_date(headers.get("Last-Modified")),
                "bytes": size,
            }

    return attempt("asking the portal for the archive identity", once)


def recorded(path):
    """What the published mapping says it was built from, if it says anything."""
    try:
        with open(path, encoding="utf-8") as handle:
            return json.load(handle).get("archive") or {}
    except (FileNotFoundError, json.JSONDecodeError):
        return {}


def describes_same_publication(mapping, archive):
    if mapping.get("etag") and archive.get("etag"):
        return mapping["etag"] == archive["etag"]
    if mapping.get("bytes") not in (None, -1) and archive.get("bytes") not in (None, -1):
        return mapping["bytes"] == archive["bytes"]
    return False


def download(url, path, expected_bytes=-1):
    """Fetch the archive, retrying a transient failure or a truncated body.

    A republication can be served half-written, and a short file would otherwise
    be unpacked into a mapping that is missing entries rather than one that is
    merely old.
    """

    def once():
        request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
        with urllib.request.urlopen(request, timeout=600) as response, \
                open(path, "wb") as handle:
            while True:
                chunk = response.read(1 << 20)
                if not chunk:
                    break
                handle.write(chunk)
        written = os.path.getsize(path)
        if expected_bytes > 0 and written != expected_bytes:
            raise ConnectionError(
                f"archive is {written} bytes, the portal announced {expected_bytes}")

    attempt("downloading the archive", once)


def write_atomically(document, path):
    directory = os.path.dirname(os.path.abspath(path))
    os.makedirs(directory, exist_ok=True)
    handle, temporary = tempfile.mkstemp(dir=directory, prefix=".jdf-lines-", suffix=".json")
    try:
        with os.fdopen(handle, "w", encoding="utf-8") as stream:
            json.dump(document, stream, ensure_ascii=False, indent=1, sort_keys=True)
            stream.write("\n")
        os.chmod(temporary, 0o644)
        os.replace(temporary, path)
    except BaseException:
        os.unlink(temporary)
        raise


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", help="the mapping file to keep current")
    parser.add_argument("--url", default=ARCHIVE_URL, help="where the archive lives")
    parser.add_argument("--force", action="store_true", help="rebuild even if the file is current")
    parser.add_argument("--owner", default=None,
                        help="chown the written file to this user, e.g. www-data")
    arguments = parser.parse_args()

    try:
        return publish(arguments)
    except Defer as error:
        print(f"deferred: {error}", flush=True)
        return DEFERRED


def publish(arguments):
    archive = identity(arguments.url)
    current = recorded(arguments.output)

    if not arguments.force and describes_same_publication(current, archive):
        print(f"up to date: {arguments.output} describes {archive.get('etag') or archive.get('bytes')}")
        return 0

    print(f"rebuilding for {archive.get('etag') or 'unknown etag'}, "
          f"published {archive.get('lastModified') or 'unknown'}")

    with tempfile.TemporaryDirectory(prefix="vdvlive-mapping-") as scratch:
        archive_path = os.path.join(scratch, "JDF.zip")
        download(arguments.url, archive_path, archive.get("bytes", -1))
        try:
            built = jdf_lines_mapping.build(archive_path)
        except (zipfile.BadZipFile, KeyError) as error:
            # A body of the right length that is not the archive we expect is the
            # portal's problem, not a decision someone has to make at 3am.
            raise Defer(f"the archive is not readable: {error}") from error
        document = jdf_lines_mapping.document_of(built, identity=archive)

    if len(built["lines"]) < 100:
        print(f"refusing to publish {len(built['lines'])} lines: that is not the region's timetable")
        return 1

    write_atomically(document, arguments.output)
    if arguments.owner:
        try:
            import pwd
            entry = pwd.getpwnam(arguments.owner)
            os.chown(arguments.output, entry.pw_uid, entry.pw_gid)
        except (KeyError, PermissionError, ImportError) as error:
            print(f"could not chown to {arguments.owner}: {error}")

    print(f"published {len(built['lines'])} lines from {built['entries']} entries "
          f"of the {built['stamp'].get('date', 'undated')} archive -> {arguments.output}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
