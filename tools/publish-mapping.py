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

Exit status is 0 both when the file was rebuilt and when it was already current.
"""

import argparse
import email.utils
import json
import os
import subprocess
import sys
import tempfile
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import jdf_lines_mapping  # noqa: E402

ARCHIVE_URL = "https://portal.cisjr.cz/pub/JDF/JDF.zip"
USER_AGENT = "VdvLive-mapping/1.0 (+https://github.com/ondrej-li/vdv-live)"


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
    with urllib.request.urlopen(request, timeout=60) as response:
        headers = response.headers
        content_range = headers.get("Content-Range", "")
        size = int(content_range.rsplit("/", 1)[-1]) if "/" in content_range else -1
        return {
            "etag": headers.get("ETag"),
            "lastModified": iso_date(headers.get("Last-Modified")),
            "bytes": size,
        }


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


def download(url, path):
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=600) as response, open(path, "wb") as handle:
        while True:
            chunk = response.read(1 << 20)
            if not chunk:
                break
            handle.write(chunk)


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

    archive = identity(arguments.url)
    current = recorded(arguments.output)

    if not arguments.force and describes_same_publication(current, archive):
        print(f"up to date: {arguments.output} describes {archive.get('etag') or archive.get('bytes')}")
        return 0

    print(f"rebuilding for {archive.get('etag') or 'unknown etag'}, "
          f"published {archive.get('lastModified') or 'unknown'}")

    with tempfile.TemporaryDirectory(prefix="vdvlive-mapping-") as scratch:
        archive_path = os.path.join(scratch, "JDF.zip")
        download(arguments.url, archive_path)
        built = jdf_lines_mapping.build(archive_path)
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
