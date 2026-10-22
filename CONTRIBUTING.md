# Contributing to Isola

Thanks for helping. Isola has two apps in one repository, `macOS/` (Swift) and `Windows/` (C# and WPF); see the
README for building each.

## Branches

| Branch | What it holds | Who changes it, and how |
| ------ | ------------- | ----------------------- |
| `main` | The current stable release. Every release is tagged from it. | Nobody pushes to it, the admin included. It only moves when a **release pull request** from `dev` is merged. |
| `dev` | Everything finished since the last release: the next release in the making. | Contributors open pull requests into it. The admin may also push to it directly. |
| your branch | One change: a fix or a feature. | You, in this repository or in your fork. Branch it from `dev`, and delete it once merged. |

```
feature/x ─┐
fix/y ─────┼──▶ dev ──(release PR)──▶ main ──▶ tag v1.2.0 ──▶ GitHub release
feature/z ─┘
```

## Contributing a change

There are two ways in, depending on whether you can push to this repository.

### With write access (collaborators)

1. Branch from `dev`:

   ```sh
   git fetch origin
   git switch -c fix/clipboard-crash origin/dev
   ```

   Name branches for what they do: `fix/…`, `feature/…`, `docs/…`.
2. Make the change, keeping it to one thing. Match the style of the code around it.
3. Build what you touched: `macOS/build_app.sh` and/or `Windows/build.ps1` (or `Windows/build.sh`).
4. Push your branch and open a pull request **into `dev`** (not `main`):

   ```sh
   git push -u origin fix/clipboard-crash
   ```

### Without write access (everyone else): use a fork

You cannot create branches here, so work in your own copy of the repository, a fork, and send the change back as a
pull request.

1. On GitHub, click **Fork** at the top of the repository page. **Untick "Copy the `main` branch only"**, so your fork
   also has `dev`.
2. Clone your fork, and add this repository as `upstream` so you can keep up with it:

   ```sh
   git clone https://github.com/YOUR-USERNAME/Isola.git
   cd Isola
   git remote add upstream https://github.com/Natuworkguy/Isola.git
   git fetch upstream
   ```

3. Branch from the latest `dev` of this repository, not your fork's (which may be behind):

   ```sh
   git switch -c fix/clipboard-crash upstream/dev
   ```

4. Make the change and build what you touched, as above.
5. Push the branch to your fork:

   ```sh
   git push -u origin fix/clipboard-crash
   ```

6. Open the pull request. GitHub offers a **Compare & pull request** button on your fork after the push; otherwise go
   to this repository's **Pull requests → New pull request → compare across forks**. Set it up as:

   - **base repository:** `Natuworkguy/Isola`, **base:** `dev`
   - **head repository:** `YOUR-USERNAME/Isola`, **compare:** `fix/clipboard-crash`

   Leave **Allow edits by maintainers** ticked, so small fixes can be made on your branch directly.
7. To bring your branch up to date when `dev` moves on (or when asked to):

   ```sh
   git fetch upstream
   git merge upstream/dev
   git push
   ```

### Then, either way

- Say in the pull request what it changes and why, and how you tested it. A screenshot or a short video helps for
  anything you can see.
- The **Build** checks (macOS, Windows x64, Windows ARM64) must pass, and the admin reviews and merges. Pushing more
  commits to your branch updates the pull request.
- Pull requests into `main` fail the **Release PR comes from dev** check and cannot be merged; `main` only takes
  releases. Aim every pull request at `dev`.
- Once it is merged, you can delete your branch.

## Repository rules

GitHub enforces the branch model with rulesets:

| Applies to | Rules |
| ---------- | ----- |
| `main` | Changes only arrive through a pull request from `dev`, merged with a merge commit, once the Build checks and **Release PR comes from dev** pass. Nobody can push to it directly, force-push or delete it, the admin included. |
| `dev` | Changes arrive through pull requests, which need an approving review and passing Build checks. Only the admin can push to it directly. No force-pushes, no deletion. |
| `v*` tags | Only the admin can create, move or delete release tags, and releases are only built from tags on `main`. |
