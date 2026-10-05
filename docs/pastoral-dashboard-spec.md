# The Chapel Pastoral Dashboard

This specification is organized into four focused documents:

1. [User experience](pastoral-dashboard-ux.md) ([Drive copy][ux-drive]) — goals, dashboard flows,
   filters, map, change feed, and visual direction. Written for Chapel users.
2. [Implementation technologies](pastoral-dashboard-implementation.md) ([Drive
   copy][implementation-drive]) — Rails architecture, Rock adapter, local data model, ActiveJob, and
   map services.
3. [Security and data governance](pastoral-dashboard-security.md) ([Drive copy][security-drive]) —
   access, read-only guarantees, privacy, data minimization, and retention.
4. [First-release implementation plan][plan-local] ([Drive copy][plan-drive]) — ordered milestones,
   decisions, and acceptance criteria.

The documents describe a private, people-oriented pastoral dashboard for Rock data. Rock remains the
source of truth. The first release is read-only; future Rock writes require a separately designed,
explicit user-intent confirmation.

## Source documents

- [Rock Person Data Structure](rock-person-data-structure.md)
- [Rock API Access Notes](rock-api-access.md)
- [Rails and Views Preferences for Agents][rails-guidance]
- [The Chapel homepage][chapel-home]
- [OpenStreetMap tile usage policy][osm-tiles]
- [Nominatim usage policy][nominatim]

[rails-guidance]: https://drive.menloparking.com/documents/a9984b46-c400-4dc0-8bd0-28c597cd9b33
[ux-drive]: https://drive.menloparking.com/documents/f6b4d6a4-baba-49f4-a0d6-0950ace25e85
[implementation-drive]:
  https://drive.menloparking.com/documents/06ae469e-61ea-4aa4-9ba4-149184426d62
[security-drive]: https://drive.menloparking.com/documents/3df10319-c9ee-4ea6-91cc-bf6eb3811c29
[plan-drive]: https://drive.menloparking.com/documents/7571514e-e496-460b-9a3f-dd0c47b42a79
[plan-local]: pastoral-dashboard-implementation-plan.md
[chapel-home]: https://chapel.org/
[osm-tiles]: https://operations.osmfoundation.org/policies/tiles/
[nominatim]: https://operations.osmfoundation.org/policies/nominatim/
