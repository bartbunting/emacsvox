FROM rust@sha256:e544a8ee0b93bb2ddc8c67a80606f040998eff3847e4deed988d0874559f52a8

ARG DEBIAN_SNAPSHOT=20260805T000000Z

# Use an immutable Debian snapshot and exact direct package versions.  The
# snapshot also freezes their transitive dependencies.
RUN rm -f /etc/apt/sources.list /etc/apt/sources.list.d/debian.sources \
    && printf '%s\n' \
       "deb http://snapshot.debian.org/archive/debian/${DEBIAN_SNAPSHOT} bookworm main" \
       "deb http://snapshot.debian.org/archive/debian/${DEBIAN_SNAPSHOT} bookworm-updates main" \
       "deb http://snapshot.debian.org/archive/debian-security/${DEBIAN_SNAPSHOT} bookworm-security main" \
       > /etc/apt/sources.list \
    && printf '%s\n' 'Acquire::Check-Valid-Until "false";' \
       > /etc/apt/apt.conf.d/99snapshot \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
       binutils-mingw-w64-x86-64=2.40-2+10.4 \
       cmake=3.25.1-1 \
       g++-mingw-w64-x86-64-win32=12.2.0-14+deb12u1+25.2+b1 \
       gcc-mingw-w64-x86-64-win32=12.2.0-14+deb12u1+25.2+b1 \
       libasound2-dev=1.2.8-1+b1 \
       libclang-dev=1:14.0-55.7~deb12u1 \
       mingw-w64-common=10.0.0-3 \
       mingw-w64-x86-64-dev=10.0.0-3 \
       pkg-config=1.8.1-1 \
    && rustup target add x86_64-pc-windows-gnu \
    && rm -rf /var/lib/apt/lists/*

LABEL org.emacsvox.omnivox.rust="1.97.1" \
      org.emacsvox.omnivox.debian-snapshot="20260805T000000Z" \
      org.emacsvox.omnivox.mingw-package="12.2.0-14+deb12u1+25.2+b1"
