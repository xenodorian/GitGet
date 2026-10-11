# GitGet: Project Plan and AI Agent Instructions

## 1. Project goal

Build **GitGet**, a lightweight, controller-operated GitHub ROM downloader for the R36S running ArkOS.

GitGet is a dedicated application, **not a web browser**. It must not launch, bundle, or depend on Firefox, Chromium, or a full browser engine. It should communicate directly with GitHub using HTTP requests and GitHub's public REST API, parse structured responses, and display only the information needed for repository and file navigation.

The primary user is not expected to use a terminal, keyboard, package manager, build tools, or manual configuration on either the PC or the handheld. Deliverables must be prepared by AI agents in the repository and packaged for direct installation by extracting a ZIP onto the R36S microSD card.

## 2. Non-negotiable user requirements

1. **No terminal instructions for the user.** Do not ask the user to run commands on a PC or handheld.
2. **No setup steps after extraction.** The intended release is a ZIP that can be extracted onto the microSD card and launched from the ArkOS Ports menu.
3. **No browser engine.** Do not use a general-purpose browser or embedded Chromium.
4. **No GitHub login.** Browse public repositories anonymously. Do not request tokens or credentials.
5. **Controller-only operation.** All normal navigation, selection, download, cancellation, and error recovery must work with the R36S physical controls.
6. **Browse the complete public profile.** List all public repositories belonging to `xenodorian`, including pagination. Allow folder navigation within each repository and support the repository's default branch.
7. **Filter irrelevant content.** Hide irrelevant files by default. Initially include `.sgba`, `.gba`, `.pak`, and `.zip`, and make the allowlist easy for an AI agent to extend. Consider other ROM/archive formats only when they are useful to this project's scope. Do not assume that a file extension alone proves a file is safe or valid.
8. **Download the original file.** Preserve the source filename and extension. Show progress, report errors, and avoid leaving partial files that appear complete.
9. **Protect the device.** Do not modify firmware, install system packages, replace system libraries, or run stress tests. Avoid unbounded memory use, request loops, and crash loops.
10. **Prepare and test on a PC.** Build and package the release in CI or an AI-accessible build environment. Do not compile on the handheld.
11. **Evidence over assumptions.** Do not claim the ZIP is R36S-ready until its launch path, architecture, dependencies, input, display, network, and storage assumptions have been checked against evidence.
12. **Make each milestone independently reviewable.** Commit source, build scripts, packaging scripts, tests, and documentation to this repository. Keep the final installation ZIP as a reproducible build artifact or release asset.

## 3. Repository and collaboration rules

- Repository: `xenodorian/GitGet`
- Default branch: `main`
- Treat this document as the project requirements baseline.
- Before editing, inspect the current repository tree, branches, existing files, recent commits, and project settings available to the agent.
- Preserve useful existing work. Do not replace the repository wholesale or delete files merely to simplify the project.
- If the repository is empty, create a clear source layout and an initial commit.
- Use small, descriptive commits. Do not claim a change was pushed unless the GitHub tool confirms a commit result.
- Keep implementation instructions in repository files, not in instructions that require the user to perform technical work.
- Record important decisions and compatibility evidence in `docs/` so later AI agents can continue without repeating discovery.

## 4. First milestone: a device information report

Before committing to the final graphics stack or binary architecture, create a **minimal, read-only ArkOS environment-report utility**. This is the first deliverable because the user does not want repeated manual testing or a guessing process.

### Requirements

- Prefer a small POSIX-compatible shell script using standard system interfaces and utilities, rather than a compiled executable. This minimizes the chance that the diagnostic itself fails because of CPU architecture or missing runtime libraries.
- Package it as a PortMaster/ArkOS launchable entry using the appropriate launch conventions established by repository research. Do not assume that any arbitrary shell script placed in a folder automatically appears in Ports.
- Collect information that is useful to a native app build:
  - kernel, distribution and ArkOS version indicators;
  - machine architecture, userspace word size, CPU features;
  - memory and storage space;
  - display resolution and available framebuffer/DRM information;
  - input device names and relevant controller configuration clues, without reading or recording button presses;
  - available shell utilities, runtimes, shared libraries and SDL-related libraries;
  - network interfaces, TLS certificate locations, and available HTTP clients;
  - relevant PortMaster paths, environment variables, directory permissions, and expected writable locations.
- Do not collect passwords, Wi-Fi credentials, tokens, browser data, or personal files.
- Do not install packages, contact external services, change settings, or modify system files.
- Bound command output and add timeouts where applicable. A missing command must be recorded as unavailable, not treated as fatal.
- Write a clearly named plain-text report to a predictable location on the microSD card. If the preferred location is not writable, try a documented fallback. Do not silently discard the report.
- Show a simple on-screen completion/failure message that can be dismissed using the handheld controls, if the available launch environment supports it.
- Exit cleanly and avoid automatically relaunching on failure.
- Include PC-side tests or static checks for the script and package layout. Clearly distinguish checks that can be performed without the actual handheld from checks that require device evidence.
- Provide concise instructions in a README: extract the ZIP, launch the diagnostic from ArkOS, shut down normally, return the card to a PC, and upload the report. No commands should be required from the user.

### Diagnostic milestone acceptance criteria

- The ZIP has a verified file listing and correct relative paths.
- The launcher follows the real ArkOS/PortMaster conventions supported by the chosen package type.
- The script is read-only except for creating its report and necessary temporary file.
- The report is generated even if optional utilities are missing.
- The report contains no secrets and includes enough information to choose a target architecture and runtime strategy.
- The agent has not represented PC-only tests as a successful physical R36S test.

## 5. Architecture selection after the report

Use the report and credible ArkOS/PortMaster documentation to select the implementation. Do not choose a stack based only on familiarity.

Evaluate, in order:

1. **Native executable and existing system libraries**, if a dependable build target and graphical/input stack can be established.
2. **A small bundled runtime**, only if it can be packaged completely and its size and startup cost are acceptable.
3. **A script-based UI using a runtime already confirmed to exist**, only if its availability and compatibility are established by the report.
4. **A narrowly scoped alternative supported by PortMaster**, if the above options cannot meet the requirements.

The app must not depend on the handheld having internet access to download its own runtime or dependencies. All required application-owned components must be bundled in the release. Do not bundle system libraries blindly or replace libraries supplied by ArkOS.

If the report cannot be obtained, continue with repository research and a best-effort build, but explicitly document remaining assumptions and never claim those assumptions have been confirmed on the user's device.

## 6. Application behavior and interface

### Navigation model

- Start at a profile screen for `xenodorian`.
- List public repositories, fetching all pages as needed.
- Selecting a repository opens its default branch at the repository root.
- Folders navigate into their contents; a visible Back action returns to the parent.
- Show only supported downloadable file types by default, while retaining folders needed to reach them.
- Provide a small status area for loading, connection failures, current path, and download progress.
- Provide a downloads view showing active, completed, failed, and cancelled downloads.
- Avoid unnecessary images, animations, transitions, and large lists in memory.
- Cache repository and directory metadata in a bounded, disposable cache. Provide a refresh action.

### Suggested controls

Use the standard controller mapping for the selected ArkOS/PortMaster environment and verify it from documentation or the diagnostic report. The intended behavior is:

- D-pad: move selection and navigate lists.
- A: open a folder, select a file, or confirm an action.
- B: go back or cancel the current dialog.
- Start: open downloads or the main actions menu.
- Select: refresh or open a small context menu, if this mapping is reliable.

Display control hints on screen. Do not require a keyboard or text entry for ordinary use.

### File filtering

- Default visible extensions: `.sgba`, `.gba`, `.pak`, `.zip`.
- Match extensions case-insensitively.
- Keep the allowlist in a documented configuration or a small source module so an AI agent can extend it without rewriting navigation.
- Directories must remain navigable even when their names do not resemble supported file types.
- Hide common source and project clutter such as `.c`, `.h`, `.py`, `.md`, `.png`, `.jpg`, build directories, and dotfiles by default. Do not hide a directory merely because it contains source-code-looking names.
- If a supported file is stored in a GitHub Release asset rather than the repository tree, that is a separate feature and should be added only after basic repository browsing and downloading are reliable.

## 7. GitHub access and data handling

- Use anonymous HTTPS requests to GitHub's public API.
- Enumerate `https://api.github.com/users/xenodorian/repos` with pagination; do not assume one page contains every repository.
- Read repository metadata to discover each default branch.
- Use the Git Trees or Contents API to navigate directories. Handle API response types explicitly.
- Use the repository's raw download URL or a suitable GitHub download URL for file contents; do not try to download a binary ROM through an endpoint that returns only JSON metadata.
- Follow GitHub rate limits. Respect response headers where available, cache metadata, use bounded retries with backoff, and stop retrying when the user cancels.
- Set finite connection and read timeouts. Handle no network, DNS failure, TLS failure, HTTP 403/404/5xx, rate limiting, malformed JSON, deleted files, and empty directories without crashing.
- Do not use authenticated API calls or embed a personal access token.
- Never execute downloaded files. GitGet only saves selected files.
- Do not automatically extract downloaded ZIP archives. Download the archive as-is unless a separate extraction feature is explicitly designed later.

## 8. Download safety and storage

- Determine and document the correct writable download directory on the ArkOS SD card. Prefer a dedicated, clearly named folder under the user's ROM storage area rather than writing into system directories.
- Do not assume all R36S SD-card layouts or mount paths are identical. Validate the destination at runtime and present a clear error if it is unavailable.
- Show filename, approximate size when available, progress, and final status.
- Write to a temporary filename and rename to the final filename only after a successful transfer and verification of available length/checksum metadata.
- Preserve the original extension. Prevent path traversal and sanitize remote filenames without unnecessarily changing ordinary filenames.
- Never overwrite an existing file silently. Offer a controller-operated choice to keep the existing file, use a non-conflicting filename, or cancel.
- Allow cancellation and clean up incomplete temporary files.
- Check free space before starting when the remote size is known; still handle insufficient space during transfer.
- Limit simultaneous downloads to avoid exhausting memory, network resources, or storage.
- Save a small local download history, without credentials, so the user can see prior results.

## 9. Reliability, performance, and failure recovery

- Keep the main UI responsive during HTTP requests and downloads.
- Bound JSON response sizes, list sizes, caches, retries, and memory consumption.
- Do not recursively crawl every repository. Fetch directory contents only as the user navigates.
- Avoid startup loops. A failure must lead to a readable error screen or a clean exit.
- Log diagnostics and failures to a local text file, with secrets and sensitive headers omitted.
- Use clear error messages, not raw stack traces, as the normal user-facing response.
- Ensure a malformed repository entry or unsupported filename cannot crash the application.
- Avoid destructive cleanup. Delete only GitGet-owned temporary files and cache entries.

## 10. Build and packaging requirements

The release package must be generated by a reproducible PC-side build or CI workflow. It must not require a compiler, pip, package manager, or network dependency installation on the R36S.

The ZIP should contain only what the chosen installation method needs, with a documented layout. Include, as appropriate:

- the launch script in the correct Ports/PortMaster location;
- the compiled executable for the confirmed target;
- all application-owned runtime files and required non-system libraries;
- configuration and assets;
- license notices for bundled components;
- a short user-facing README;
- version/build information;
- the diagnostic report utility until its purpose has been served or it is intentionally retained as a support tool.

Requirements:

- Use Unix line endings for shell scripts and preserve executable permissions where the archive format supports them. Verify that the installation method does not rely solely on ZIP permission preservation; the launcher should follow the conventions of the actual PortMaster package format.
- Do not include PC build outputs, caches, credentials, source archives, or unrelated files in the installation ZIP.
- Avoid overwriting unrelated user files during extraction.
- Provide a ZIP integrity check and a manifest of packaged paths.
- If PortMaster requires a particular package structure or metadata, follow that documented structure rather than inventing one.
- Produce a final release ZIP as an artifact or GitHub Release asset, and include a checksum.
- Document exactly where the ZIP must be extracted. The user should not have to manually move individual files.

## 11. Testing strategy

### Tests that can be automated on a PC or CI

- Static checks of shell scripts and source.
- Unit tests for extension filtering, pagination, path handling, API response parsing, error handling, and filename collision behavior.
- HTTP client tests using recorded/mock API responses, including rate limits and malformed responses.
- Download tests for successful, interrupted, cancelled, truncated, and insufficient-space transfers.
- ZIP contents and path validation.
- Architecture and dynamic-library checks for the produced executable.
- Startup checks under a suitable Linux test environment.
- Memory and response-size bounds tests.
- Verification that the package contains no credentials and no browser engine.

### Checks that cannot honestly be claimed without suitable device evidence

- Actual R36S screen rendering and input mapping.
- Real ArkOS launch-menu integration.
- Actual Wi-Fi adapter and TLS behavior.
- Writable paths and SD-card layout on the user's specific installation.
- Physical-device startup stability and performance.

Do as much validation as possible in one planned pass. Do not turn development into repeated manual testing requests to the user. If physical testing is unavailable, label the release as unverified on hardware and explain the remaining uncertainties in the repository documentation.

## 12. Suggested milestones

1. **Repository reconnaissance:** inspect existing files, history, permissions, and current implementation; document findings.
2. **Environment report utility:** implement, package, and statically validate the read-only ArkOS diagnostic ZIP.
3. **Architecture decision:** use the report and reliable documentation to choose the smallest supportable UI/network stack.
4. **Core application:** implement profile repository listing, pagination, folder navigation, extension filtering, and controller input.
5. **Downloader:** implement safe transfers, progress, cancellation, conflict handling, and download history.
6. **Robustness:** implement caching, bounded retries, error screens, diagnostics, and resource limits.
7. **Packaging:** create the self-contained ArkOS/PortMaster ZIP using the verified package structure.
8. **Automated validation:** run all tests, inspect archive contents, verify target architecture/dependencies, and record results.
9. **Release:** publish the ZIP, checksum, installation instructions, and known limitations.

Each milestone must result in committed work and a concise progress note. Do not skip the environment-report milestone in favor of guessing the target environment.

## 13. Definition of done

GitGet is complete when:

- The source and build/packaging instructions are committed to this repository.
- A single ZIP can be extracted onto the microSD card using the documented method without the user running commands.
- The application launches from the expected ArkOS/PortMaster interface.
- It uses no browser engine and requires no GitHub login.
- The user can browse every public repository on `xenodorian`, navigate folders, see supported file types, and download selected files using the handheld controls.
- Downloads are safely written to the SD card and failures are recoverable.
- All available automated checks pass and their results are documented.
- Hardware-only validation is clearly distinguished from simulated or static checks.
- The final ZIP, checksum, and concise installation instructions are available from the repository or its releases.

## 14. Instructions to the AI agent taking over

Start by inspecting this repository and its current state. Then implement **Milestone 2, the environment-report utility**, as the first functional deliverable. Research the real ArkOS/PortMaster launch conventions before choosing its package layout. Commit all source and packaging files, run the available static checks, and create a ZIP artifact. Do not ask the user to type commands or perform intermediate technical setup. Do not claim that the diagnostic or final application was tested on physical hardware unless that evidence actually exists.
