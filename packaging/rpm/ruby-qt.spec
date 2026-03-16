Name:           ruby-qt
Version:        0.1.6
Release:        1%{?dist}
Summary:        Ruby bindings for Qt 6 with generated native bridge

License:        BSD-2-Clause
URL:            https://github.com/CyJimmy264/qt
Source0:        %{name}-%{version}.tar.gz

BuildRequires:  ruby
BuildRequires:  ruby-devel
BuildRequires:  rubygems-devel
BuildRequires:  rubygem-rake
BuildRequires:  rubygem-ffi
BuildRequires:  gcc-c++
BuildRequires:  make
BuildRequires:  pkgconf-pkg-config
BuildRequires:  qt6-qtbase-devel
BuildRequires:  clang
BuildRequires:  chrpath

Requires:       ruby
Requires:       rubygem(ffi)
Requires:       qt6-qtbase

%global gem_name qt
%global gem_dir /usr/share/gems
%global gem_instdir %{gem_dir}/gems/%{gem_name}-%{version}
%global debug_package %{nil}

%description
qt provides Ruby bindings for Qt 6 with an AST-generated bridge over a native
extension (qt_ruby_bridge.so).

This package ships prebuilt binaries for the target Fedora buildroot.

%prep
%autosetup -n %{name}-%{version}

%build
# Guard against source/spec version drift (SRPM is built from git HEAD).
gem_version=$(ruby -e "spec = Gem::Specification.load('qt.gemspec'); puts spec.version")
if [ "$gem_version" != "%{version}" ]; then
  echo "Version mismatch: qt.gemspec=$gem_version, spec=%{version}" >&2
  exit 1
fi

# 1) Generate Ruby bridge metadata/source from system Qt headers.
ruby scripts/generate_bridge.rb

# 2) Build the gem artifact from the project root.
gem build qt.gemspec --output %{gem_name}-%{version}.gem

%install
mkdir -p %{buildroot}
rm -rf .rpm-gem-root
mkdir -p .rpm-gem-root

# Build/install gem into a temporary root first, then copy into BUILDROOT.
# This avoids embedding BUILDROOT paths into native extension artifacts.
gem install \
  --local \
  --force \
  --ignore-dependencies \
  --no-document \
  --install-dir .rpm-gem-root \
  %{gem_name}-%{version}.gem

mkdir -p %{buildroot}%{gem_dir}
cp -a .rpm-gem-root/. %{buildroot}%{gem_dir}/

# Keep runtime bridge in gem lib path so FFI can load it without RubyGems
# extension activation checks.
if [ ! -f %{buildroot}%{gem_instdir}/lib/qt/qt_ruby_bridge.so ]; then
  ext_so=$(find %{buildroot}%{gem_dir}/extensions -type f -name qt_ruby_bridge.so | head -n1)
  if [ -n "$ext_so" ]; then
    mkdir -p %{buildroot}%{gem_instdir}/lib/qt
    cp -a "$ext_so" %{buildroot}%{gem_instdir}/lib/qt/qt_ruby_bridge.so
  fi
fi

# RPM ships prebuilt extension binary; make installed gemspec runtime-only so
# RubyGems does not demand extension (re)build state at activation time.
gemspec_file=%{buildroot}%{gem_dir}/specifications/%{gem_name}-%{version}.gemspec
if [ -f "$gemspec_file" ]; then
  sed -i '/\.extensions =/d' "$gemspec_file"
fi

# Ship generated Ruby bridge metadata to avoid runtime regeneration.
mkdir -p %{buildroot}%{gem_instdir}/build/generated
cp -a build/generated/bridge_api.rb %{buildroot}%{gem_instdir}/build/generated/
cp -a build/generated/constants.rb %{buildroot}%{gem_instdir}/build/generated/
cp -a build/generated/widgets.rb %{buildroot}%{gem_instdir}/build/generated/

# Drop build logs containing absolute BUILDROOT paths; otherwise check-buildroot fails.
find %{buildroot} -type f \( -name gem_make.out -o -name mkmf.log \) -delete

# Ensure no host-specific RUNPATH leaks into packaged native extensions.
find %{buildroot} -type f -name qt_ruby_bridge.so -exec /usr/bin/chrpath -d {} \; || :

%files
%license LICENSE
%doc README.md
%{gem_dir}/cache/%{gem_name}-%{version}.gem
%{gem_instdir}
%{gem_dir}/specifications/%{gem_name}-%{version}.gemspec
%{gem_dir}/extensions

%changelog
* Mon Mar 16 2026 Maksim Veynberg <mv@cj264.ru> - 0.1.6-1
- Generate event payload schemas and switch event runtime callbacks to JSON payload delivery
- Expand generated event payload coverage for additional event families
- Derive event payload classes without regex rules and prefer more specific deterministic family matching
- Add consume semantics for event runtime callbacks
- Add end-to-end runtime coverage for move/show/hide/close lifecycle events

* Mon Mar 16 2026 Maksim Veynberg <mv@cj264.ru> - 0.1.5-1
- Add wheel event runtime support with ignore hook
- Derive event runtime mappings from QEvent enums during generation

* Sat Mar 14 2026 Maksim Veynberg <mv@cj264.ru> - 0.1.4-1
- Wrap QObject-derived pointer returns into Ruby widget objects

* Thu Mar 05 2026 Maksim Veynberg <mv@cj264.ru> - 0.1.3-1
- Initial Fedora/COPR packaging for ruby-qt
