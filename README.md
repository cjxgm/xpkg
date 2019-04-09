# Extraction-based package manager for embeded platforms

Goal:

- Uses only busybox.
- No networking or repositories.
- Support install and uninstall local packages. Installing new version is upgrading.
- Only extraction, no post-install scripts or anything like that.
- Package name and version comes from filename: `package-name@version.tar.gz`
- PROBABLY: pacman-like hooks

