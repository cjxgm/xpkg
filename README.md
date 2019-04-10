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

# Bootstrap

Download `xpkg.sh` and copy it to your device. Then,

```sh
busybox sh xpkg.sh -b
```

It will create a package `xpkg@VERSION.tar.gz` in `/xpkg-store/bootstrap/`
and install it.

You can then remove your `xpkg.sh` and type `xpkg` to use it.

