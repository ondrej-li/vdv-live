# What survives without a network

Decided on 2026-10-01, for issue #9.

The feed is live data: a position from an hour ago is not the map, and showing it
as though it were would be worse than showing nothing. So the app keeps what it
can date and marks it as old, and deliberately keeps nothing else.

## Kept

| What | Where | Why |
|---|---|---|
| The last payload, with the time it was fetched | The caches directory, one JSON file | A cold start with no network then has something to show, and can say how old it is |
| Fetched timetable entries | The caches directory, one file per line | A line's timetable does not change when the network goes away |
| The archive index | The caches directory | Without it nothing maps a line to its entry |

The caches directory is the right home for all three: the system may take them
back at any time, and losing them costs the app nothing worse than the empty map
it would have shown anyway.

## Marked, not hidden

- The restored payload is drawn **grey** until a live payload replaces it. That is
  the marker the app already uses for a vehicle the feed has stopped reporting, and
  it means the same thing here: this is not news.
- The header gives up the vehicle count for `Offline · last 12:34` while the feed
  cannot be reached, so the age of what is on screen is visible rather than implied.
- The banner says what is being shown - "No connection to the feed. Showing the
  last positions from 12:34." - and carries the retry.
- All of it goes the moment a payload arrives.

Unreachable and unreadable are kept apart. `VehicleAPIError.transport` is the
request never making it to the server, which is what a device without a network
produces; anything else (a status code, a body the decoder refuses) is the feed
answering badly, and is reported as an error rather than as being offline.

## Deliberately not kept

- **Nothing undated.** The stored file carries `fetchedAt`, and a file this build
  cannot read is treated as no file at all rather than as fresh data.
- **No history.** Keeping positions back in time, to draw a trail or to animate a
  gap, is a different feature and would grow without bound.
- **No offline queue.** Pinned lines and settings live in `UserDefaults`, which is
  local already, and nothing the user does needs a network.
- **No separate retry schedule.** The banner's retry and the automatic refresh both
  keep trying, so the app recovers by itself as soon as the feed answers.

## The timetable index

That one is refreshed cheaply *because* the portal dates and identifies its file:
one range request says which publication is being offered, and the two megabytes
are read again only when the answer says there is something new (issue #25, PR
#26). Nothing re-reads the index on its own.
