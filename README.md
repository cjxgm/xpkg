# Extraction-based package manager for embeded platforms

Goal:

- Uses only busybox.
- No networking or repositories.
- Support install and uninstall local packages. Installing new version is upgrading.
- Only extraction, no post-install scripts or anything like that.
- Package name and version comes from filename: `package-name@version.tar.gz`
- PROBABLY: pacman-like hooks

Tested with:

- Busybox 1.30.1

Tested on:

- Arch Linux
- Codex OS (Remarkable Paper Tablet), with custom-compiled busybox 1.30.1

