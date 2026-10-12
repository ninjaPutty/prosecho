# ChurchNext account linking

## Scope

Prosecho links imported Rock person profiles to ChurchNext identities. These are not Prosecho staff
login accounts, and linking grants no application login, campus, photo, or other permissions. This
phase builds only Prosecho. ChurchNext changes and deployment require separate work.

## Intake and matching

Accept authenticated server-to-server account submissions containing ChurchNext's stable user ID,
first and last name, email, email-verification state, and optional photo availability. Never accept a
public browser's unsupported claim of another user's identity. ChurchNext must derive these fields
from its signed-in account, not from arbitrary browser parameters.

Automatically link only when a verified email matches exactly one currently eligible imported person
and neither identity is linked elsewhere. Email comparison ignores surrounding whitespace and case,
but does not remove plus tags, dots, or other address distinctions. Shared or unverified emails,
existing-link conflicts, and similar names require administrator review. Name similarity never
automatically links an account.

Use case/accent-tolerant name comparison, including the person's approved nickname and modest
spelling/transposition differences. Suggestions are heuristics, not confidence probabilities or
proof of identity. No person information is sent to an AI provider, and photos are not analyzed.
Accounts without plausible suggestions remain pending and visible in the administrative intake area.

Requests for the same ChurchNext user ID are idempotent. Pending requests refresh their suggestions;
already-linked IDs retain their original link and cannot silently move to a different person.
Directory refreshes preserve established ChurchNext IDs.

## Administrator review

The administrator-only **ChurchNext accounts** area displays the submitted ChurchNext identity,
email, and permitted portrait, followed by potential directory matches with permitted portraits,
names, and approved emails. Incoming ChurchNext records form an administrator-managed intake queue;
directory suggestions remain restricted to the reviewer's current campus grants and confirmed policy.
Administrators without campus grants may inspect intake records but cannot approve directory links.

**Match** records the link and notifies ChurchNext. **Not match** remembers the rejected pair and
removes it from future suggestions, including future exact-email auto-linking. Retain decisions by
stable Rock identity so deleting/reimporting a local projection does not erase a rejection. Decisions
are audited with IDs, actors, and timestamps rather than copied personal values. Forms require CSRF
protection. Recheck role, account state, campus scope, and policy at the point of every decision.

Photos require the administrator's explicit photo permission. Use private authenticated proxy
endpoints, never embedded credentials, third-party image CDNs, or arbitrary submitted image URLs.
Unavailable photos fall back to initials.

## Data decisions and operations

Email import is a new optional approved directory field. Supporting this field does not change the
existing saved policy. An administrator must select **Email address (ChurchNext account linking)**
in **Data decisions**, confirm the decision, and refresh people from Rock. Old-policy projections
are not eligible. Removing approval hides matching candidates and clears imported emails on the
next successful refresh; it does not automatically erase existing identity links or intake records.

The API is disabled until a runtime integration token is configured. Callback and photo fetching
remain disabled until an approved ChurchNext HTTPS origin and separate outbound credential exist.
Callbacks are durable, retryable, and idempotent; a temporarily unavailable ChurchNext service must
not undo a locally approved link. Integration failures retain only safe status codes, not response
bodies or private exception messages.

Intake identities and remembered decisions are durable records. Automatic expiry, unmatching,
account deletion propagation, and correction/reassignment workflows are outside this phase and need
an agreed retention/correction policy. Removing a directory person does not authorize reassignment:
the established integration record and outbound event retain their original identifiers.

The [integration contract](churchnext-api-contract.md) specifies the ChurchNext work still to build.
The same [contract is published on MP Drive][drive-contract] under ChurchNext's architecture docs.
Tests use synthetic identities and stub HTTP; no ChurchNext code or live account linkage is created.

[drive-contract]: https://drive.menloparking.com/documents/faae065f-aa7b-4ab0-a155-4ac898f11a8f
