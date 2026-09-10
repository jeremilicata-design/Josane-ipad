# Growing With Jesus — video production system

Reference for Josane's YouTube channel: the weekly pipeline, the file
conventions each step depends on, and where the revision trigger fits.

Reconstructed from the recording guide, the three recurring calendar
events, and the version emails sent to Josane. Anything marked TODO is
not yet confirmed against the code that runs on the MacBook.

## The weekly cycle

| When | Who | What happens |
|---|---|---|
| Friday 09:00 | Josane | Records. Main video plus two Shorts, ten thumbnail photos. |
| Friday 18:00 | Josane | Saves the folder into shared iCloud, with `notes.txt`. |
| Friday night | System (MacBook) | Cuts the video. Silence stripped, flag commands applied, Shorts and thumbnails generated. |
| Saturday 10:00 | Josane | Reviews the cut and writes her revision notes. |
| Saturday | System (MacBook) | Applies the revisions. Output goes to Drive as `LONGFORM v2`, `v3`, and Josane gets a summary email. |

## Recording day

Full guide: https://claude.ai/code/artifact/9a1aa3f0-3b7a-45e7-8fb6-b951c0750ddb

Rear camera, 4K30, lens at eye level, window in front. Framed mid-chest
up with room on both sides, because the vertical Shorts crop out of the
middle. Same spot every week.

Ten thumbnail photos are taken in Photo mode before anything is filmed:
two each of warm open smile, surprised, thoughtful, laughing, serious.
Video frames are too soft to use.

### Spoken commands

Josane edits while talking. Every command starts with `flag` so ordinary
speech cannot trigger one, with about a second of silence either side.
The editor finds them, acts on them, and deletes the command itself.

| Command | Effect |
|---|---|
| `flag scratch` | Delete the sentence just spoken, then it is said again |
| `flag clip` … `flag end clip` | Mark the span as a candidate Short |
| `flag ding` | Place the subscribe sound here |
| `flag chapter` + name | Start a new section |
| `flag broll` + word | Drop in matching footage |
| `flag hold` | Protect the silence that follows from the silence stripper |
| `flag end` | Everything after this is ignored |

Known failure: transcription once heard `flag scratch` as "like
scratch" and missed twelve of them in one stretch. Treat near misses of
the wake word as matches.

## Handoff files

Both live in the dated folder inside the shared iCloud folder
`Growing With Jesus`, for example `2026-08-14/`.

`notes.txt`, written by Josane on recording day:

```
TOPIC: how to pray for your future husband
TITLE IDEA: I prayed 4 years and got it wrong
NOTES: rambled around the middle, cut freely
```

`revisions.txt`, written by Josane on review day. One line per note,
timestamp first, because the timestamp is what gets parsed:

```
2:34 - cut this whole part, I repeat myself
4:10 - keep this pause, don't trim it
5:52 - wrong word, I meant grace not mercy
8:20 - this bit should be a Short
```

## The revision trigger

Josane works from her iPad, where saving a text file into a specific
folder is the most awkward step in the whole week. The revision notes
page replaces that step:

https://claude.ai/code/artifact/eee2f39a-10bd-4ef9-bdc2-174d900af1ca

She picks the recording date, types one note per moment, and taps
**Send my revisions**. Drafts save as she types, so a half-finished
review survives closing the tab.

See `docs/revision-notes-schema.md` for the stored shape and how the
MacBook side reads it.

## Standing editorial rules

Learned from the first two revision rounds and worth keeping:

- Cut on the last word of every sentence. The recurring complaint was a
  fifth of a second of Josane finishing a line, pausing, and looking
  down, left in before each cut.
- Never cut a closing callback to the opening. One revision note asked
  for a cut that would have removed the strongest line in the video; the
  pause before it was what she actually meant.
- No greeting in the intro. Series name in the first ten seconds, then
  straight into the hook.
- Nothing is posted until both of them approve it.

## Open questions

- TODO: the project folder and command that run the edit and the
  revision pass on the MacBook. The convention elsewhere is
  `~/<Project>/workflows/NN-name.md`.
- TODO: how the MacBook picks up a revision send. Reading the page's
  stored notes from a Claude session on that machine is verified to
  work; nothing schedules it yet.
