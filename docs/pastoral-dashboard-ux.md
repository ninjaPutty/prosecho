# Pastoral Dashboard: User Experience

## Purpose

Give Chapel pastors and authorized ministry staff a warm, clear way to understand who is connected
to the church, where people live, and which people records have recently changed. The experience
should feel personal and people-oriented, not like an administrative reporting system.

## What users need to do

- Find people by campus, connection status, age range, and home-address town.
- See the people matching those filters in a list and on a map.
- Notice recently discovered connection-status, address, and household changes.
- Move from a map point or change item to the relevant person's summary without losing the current
  filters.

## Dashboard layout

The implemented People view has combined filters, portrait/initial rows, freshness and refresh-state
summaries, and a person panel that keeps filters. Refresh people from Rock queues background work
while the current directory stays visible. Map/Changes navigation explains pending setup rather than
displaying invented points or events.

On a desktop screen, the dashboard has a compact welcome/header area, a persistent filter rail, a
large map, a recent-changes feed, and a people list or profile drawer. Users can move between these
views without re-entering their filters.

On a small screen, filters open in an accessible sheet and a clear Map/List control switches the
primary content. The layout should remain useful when the map is hidden or unavailable.

The page should include:

- A friendly heading such as “People at a glance.”
- A last-updated indicator so staff can judge how current the view is.
- Visible active-filter chips and a “clear all” action.
- Useful loading, no-results, stale-data, and temporary-error states.
- Keyboard-accessible controls and subtle transitions that respect reduced motion preferences.

## Filters

The first release offers:

- Home campus.
- Current connection status.
- Minimum and maximum age.
- Home-address town/locality.
- A change-time window: 1 week, 2 weeks, 30 days, or 90 days.

Filters apply together and affect people, map, result counts, and change feed. The interface always
makes the selected filters visible. Users can clear one filter or all filters without losing their
current view.

Age is shown as a human-friendly value and evaluated from birth date. Empty or unknown data should
be clearly represented, never guessed.

## Map and people

Users can toggle between individual pins and an aggregate heatmap. At wide views, clusters or
aggregate density keep the display legible. A pin opens a small person summary; selecting it can
reveal a profile drawer with a photo, chosen name, campus, connection status, and relevant
contact/profile details.

Use the person's Rock profile image when it is available and accessible. Show initials or a neutral
placeholder when it is not. Images are supplementary; a missing image must not make a person hard to
identify.

The map should show visible OpenStreetMap attribution. Home addresses are private: only authorized
staff should see address-level detail. At broader zoom, prefer clusters or heat rather than exposing
individual households.

## Recent changes

The change feed shows:

- Connection status changed.
- Home address changed.
- Household/family composition changed.

Each item identifies the person, change type, previous and current value when appropriate, and when
the application discovered it. The time filter applies to discovery time. The interface must not
imply that a poll's discovery time is the exact time the person or household changed.

Use factual wording. For example, show “Household member added” when that is what the data
establishes; do not label it a birth, marriage, or divorce unless the source data supports that
conclusion. If the reason is unclear, say so.

## Chapel-inspired visual direction

Use The Chapel's public site as inspiration: bold editorial headings, confident photography, a
high-contrast light/dark foundation, rounded action shapes, and a restrained turquoise accent. Make
the internal dashboard calmer and more compact than the public site. Prioritize Chapel identity and
actual Rock people photos; avoid generic hero artwork and decorative dashboard clutter.

Use an accessible contrast ratio for text and controls. Treat branded fonts as optional until
licensing and asset availability are confirmed.

## Boundaries

The first release presents and filters information. It does not edit a person, change family
membership, or send a message. The dashboard is private and is not available to anonymous visitors.

## Account administration

An administrator can manage the workspace in a browser without command-line tools. On the first
visit to `/admin`, a setup form asks for email, password, and password confirmation. It creates the
first account with account-admin access. Afterward, the administration dashboard is available only
to signed-in administrators.

The dashboard offers account creation and editing: email, password, active status,
administrator/staff role, campus assignments, and permissions to view photos, history, and precise
locations. Password fields are never prefilled; leaving a new password blank keeps the current one.

Administrators use **Fetch campuses from Rock** instead of entering campus names and IDs by hand. It
reports added, updated, and unchanged counts. Refreshing preserves staff assignments and local
parent organization without duplicates. The Rock catalog is flat; optional parents organize campuses
locally. Administrators can edit local names, parents, and active status, but source Rock IDs are
fixed. A parent does not automatically grant access to its children. Deactivating an account or
campus removes its access without deleting records. The dashboard explains validation problems and
prevents removing the last active administrator. These controls manage Prosecho only; they do not
edit people or campuses in Rock.

### Retention and data decisions

The administration dashboard links to **Data decisions**. Administrators enter how long to keep
profiles, change history, logs, and backups; describe address and household rules; and select the
person fields and custom attributes for the initial import.

The page provides suggested source descriptions from the Rock investigation and supports saving a
draft. When the decisions are complete, select **Record agreed decisions** and save. The page shows
the last editor and save time. Incomplete or invalid decisions show specific errors, and an
out-of-date form cannot overwrite another administrator's work. Saving these choices does not start
importing or deleting people.
