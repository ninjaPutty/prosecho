# Flashcards

## Name recall practice

Flashcards follows Changes in the workspace navigation and is available only to staff with photo
permission and an active campus grant. The approved directory policy must allow photos. The feature
uses the existing authorized portrait endpoint; no photos or names are sent to a third-party service.

Choose campuses from the user's current grants, connection statuses from the visible directory, and
between 1 and 100 people. Only currently visible people with available photo references and meaningful
names are eligible. The chosen pool needs at least four distinct names. Each person appears once per
run; all four answer names come from that same pool and must be distinct. Same-gender choices are
preferred when an explicitly approved `Gender` custom attribute is present. The current directory
does not import gender as a standard field; missing gender never leads to guessing or expanded data
collection.

Show a photo and four names. Record the first answer, reveal the correct name, then let the user
continue. Repeated submissions cannot change the answer or count another attempt. Users may do
multiple runs per day. Revoked photo/campus access, removed people, or changed directory policy must
not expose saved choices; a run with unavailable choices requires restarting.

## Spaced repetition

Use a Leitner-style schedule independently for each user and person. Incorrect answers reset the
review level and make the name due again after ten minutes. Consecutive correct answers advance
through intervals of 1, 3, 7, 14, 30, and 60 days. Prioritize overdue names, then unseen people, then
people whose reviews are not yet due if needed to fill the requested run. Randomize new-person
selection and answer order. This supports spaced retrieval and corrective feedback without claiming
that multiple-choice recognition is equivalent to unaided recall.

## Daily dashboard progress

Show the user's seven most recent practice days, grouped in the application's local time zone.
Present each day's summary as a full-width banner, with content stacked on smaller screens.
Aggregate all runs started on each day. Report cards answered, number of runs, completion percentage
(answered cards divided by planned cards), and accuracy (correct answers divided by answered cards).
Repeated practice of a person counts as another attempt. Incomplete runs remain in the completion
denominator. Practice results are private to their user, not a staff leaderboard.

Practice stores local user/person identifiers, ordered choices, answer outcomes, and review intervals,
not copied photos, names, or raw Rock responses. Deleting a person removes their review record and
prevents the old card from being played; aggregate answer outcomes remain. Deleting an account
removes its practice records. Retention beyond these deletion rules is not yet automated.

## Local operation

Run migrations and `bin/check` inside the dev container. The new practice schema is local until a
separately approved migration/deployment. Regression tests use synthetic people and never call Rock.
Lookbook includes completion and daily-progress scenarios. Browser appearance and live-photo review
remain separate acceptance checks.
