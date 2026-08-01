**Date**: 2026-08-01
**Status**: Draft
**Owner**: software-factory
**Task**: task-file-dashboard
**Session**: _(this session)_
**Decisions**:
  - _(captured inline below)_

### Problem statement

The task list currently lives in `docs/tasks.txt` — a local file only accessible when working in the workspace. The user wants to view and add tasks from anywhere (phone, other devices, browser) without needing a terminal, git, or the workspace open. The format is a well-defined YAML-like structure with projects, statuses, and task descriptions that needs to be preserved.

### Solution overview

A single HTML page (`docs/index.html`) hosted on Cloudflare Pages that:
1. Reads `docs/tasks.txt` from the GitHub repo via the REST API
2. Renders a clean, grouped view by project → status, with collapsible sections
3. Provides a form to add new tasks, which writes back to the file via the GitHub API
4. Requires a fine-grained Personal Access Token for authentication (read + write)

No backend, no database, no infrastructure. Just a static HTML file and the GitHub API.

### User stories

1. As a user visiting the page, I see all tasks grouped by project, then by status (Pending → Queued → Complete), with collapsible sections.
2. As a user visiting the page, I can see completed tasks but they are collapsed by default and shown with strikethrough text.
3. As a user visiting the page, I can add a new task by selecting a project (from a dropdown), selecting a status (Pending/Queued/Complete), and entering a description. The task is automatically inserted into the correct project/status section and committed to the repo.
4. As a user, I can only view and add tasks — no edit, no delete, no modification of existing tasks.
5. As a user, I authenticate once with a GitHub PAT that is stored in my browser's localStorage.
6. As a user, I can refresh the task list to see changes made by the agent or other users.

### Architecture

**Data flow:**
```
Browser → GitHub API (GET /repos/.../contents/docs/tasks.txt) → Page renders
User submits form → Page reads current file (GET) → Appends new line → 
Writes back (PUT) → Page refreshes
```

**Key components (all in one HTML file):**
- `parseTasks()` — parses the YAML-like tasks.txt format into a structured project/status/task hierarchy
- `renderTasks()` — renders the grouped view with collapsible cards
- `addTask()` — reads the current file, modifies it, writes back via the API
- `addTaskLine()` — finds the correct insertion point in the file (right project, right status, right order)
- `testToken()` / `saveToken()` — PAT management

**Auth:**
- Fine-grained PAT scoped to `ak47-arch/workspace` with `Contents: read & write`
- Stored in `localStorage` — never sent to any server, only used in GitHub API calls
- If the token expires or is invalid, the page shows the setup screen

### Implementation decisions

- **Single HTML file**: No build step, no dependencies, no npm. Just a file that works in any browser.
- **GitHub API for reads/writes**: The REST API's Contents endpoint handles both reading and writing. The SHA field prevents race conditions.
- **Ordered status insertion**: New status sections are inserted in the right order (Pending → Queued → Complete) when added to an existing project.
- **New project creation**: If a project doesn't exist yet, the form creates it at the end of the file with the correct structure.
- **Dark mode**: Uses `prefers-color-scheme` CSS media query for automatic dark/light mode switching.
- **No external CSS/JS frameworks**: Vanilla CSS, vanilla JS, no dependencies.

### Testing decisions

- The `addTaskLine` function was tested against 4 scenarios (add to existing status, add new status section, add to new project, add to project with no status sections) using a Node.js simulation.
- The parsing logic was verified against the actual `docs/tasks.txt` file — 11 projects and 34 tasks parsed correctly.
- Manual testing on the live page will be the final verification.

### Out-of-scope items

- **Edit/delete tasks**: Deliberately excluded. The user only wants view and add.
- **Drag-and-drop reordering**: Overkill for a text file.
- **Real-time sync**: The page requires a manual refresh to see changes.
- **Multi-user support**: The PAT is per-user. Multiple users would each need their own token.
- **Mobile app**: The page is responsive but not a native app.

### Further notes

- The page is served from `docs/index.html` on the main branch, hosted via Cloudflare Pages.
- The user's domain can be connected to Cloudflare Pages for a clean URL.
- The PAT setup is a one-time step: create a token, paste it, save it.