# Fedora/COPR Packaging (`ruby-qt`)

This directory contains a minimal RPM packaging setup for building Fedora
binary packages in COPR.

## Files

- `ruby-qt.spec` - RPM spec for `ruby-qt`
- `Makefile` - helper to build SRPM from current git checkout

## Prerequisites (local)

```bash
sudo dnf install -y rpm-build git
```

## Build SRPM locally

From repository root:

```bash
make -C packaging/rpm srpm
```

SRPM will be created under:

```text
packaging/rpm/.rpmbuild/SRPMS/*.src.rpm
```

By default, SRPM is built with neutral `dist` (`--define "dist %{nil}"`),
so file names are distro-agnostic (for example `ruby-qt-0.1.7-1.src.rpm`).

## Submit build to COPR

1. Install and configure `copr-cli`:

```bash
sudo dnf install -y copr-cli
mkdir -p ~/.config
# put your API credentials into ~/.config/copr
```

2. Create project once (example):

```bash
copr-cli create ruby-qt --chroot fedora-41-x86_64
```

3. Submit SRPM:

```bash
copr-cli build ruby-qt packaging/rpm/.rpmbuild/SRPMS/*.src.rpm
```

## Notes

- Package name is `ruby-qt` (gem name remains `qt`).
- Binary `.so` is built inside Fedora buildroot during `gem install`.
- If `Version` changes in `ruby-qt.spec`, SRPM tarball name is updated
  automatically by `Makefile`.
