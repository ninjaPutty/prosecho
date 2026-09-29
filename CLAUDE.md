# MP Agent Guidance

Before working, read the canonical MP AGENTS.md:
https://drive.menloparking.com/documents/3f69a1c9-7ce3-4fdf-8135-b404c1494870

Fetch it with GET:
https://drive.menloparking.com/api/v1/documents/3f69a1c9-7ce3-4fdf-8135-b404c1494870

Request application/json and read the returned document.body.
Load DRIVE_MENLOPARKING_TOKEN in memory from OpenCode user secrets,
normally ~/.config/opencode/secrets.env, only when making Drive requests.
If unavailable, inspect only credential variable names under
~/.config/opencode/; do not dump secret files or try unrelated credentials.

Send Bearer authentication only to https://drive.menloparking.com.
Disable redirects and use User-Agent: OpenCode MP documentation reader.
Never expose credentials in arguments, logs, output, source, or images.

Read and follow the canonical document and its relevant linked guidance.
Refresh guidance last read more than 72 hours ago.
Read this repository's docs and preserve project-specific instructions.
If required guidance is inaccessible, report the blocker and ask for
approved access; do not bypass it or request secret values in chat.

Run application commands inside the dev container. Tests use Minitest,
not RSpec. Read README.md before setup and docs/deployment.md before deployment.
