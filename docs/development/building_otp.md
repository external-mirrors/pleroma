# Building OTP Binaries Yourself

{! backend/installation/otp_vs_from_source.include !}

This guide covers building OTP binaries yourself, for example to make packages for your distro.

## System dependencies

{! backend/installation/generic_dependencies.include !}

Also you should have a dedicated user which will run pleroma with only the permissions it needs.
This guide will assume it is named ``pleroma``.

## Elixir dependencies

Unless your distro has support for elixir libraries, run ``mix deps.get`` to fetch the required elixir dependencies.

## Mix Release

See <https://hexdocs.pm/mix/Mix.Tasks.Release.html> for more details.

### Configuration

* For AGPLv3 compliance and if source code is modified, `source_url` in `mix.exs` should be updated to point to the correct repository.
* Create a file at ``config/prod.secret.exs`` containing: ```
import Config

config :tzdata, :data_dir, "/var/lib/pleroma/tzdata"
```
* To build with your system's [libvips](https://libvips.github.io/libvips/) instead of the vendored one: ``export VIX_COMPILATION_MODE="PLATFORM_PROVIDED_LIBVIPS"``
* To build with your system's [lexbor](https://lexbor.com/) instead of the vendored one: ``export WITH_SYSTEM_LEXBOR=1``

### Compiling

``mix release --path pleroma``

You can then:
* Copy the contents of `./pleroma/` into a directory like `/opt/pleroma`, which will be referred to as ``${relpath}``
* (Optional) Create a symlink of ``${relpath}/bin/pleroma`` and ``${relpath}/bin/pleroma_ctl`` into a directory contained in regular `$PATH` such as ``/usr/bin``

## Permissions

You'll need to restrict file access permissions like so:

<!-- TODO: check which exact restrictions are needed  -->
* ``chmod 0750 ${relpath}``
* ``chmod -R g-w,o= ${relpath} && chown -R 0:pleroma ${relpath}``
* ``chmod 0750 ${relpath}/releases/COOKIE && chown 0:pleroma ${relpath}/releases/COOKIE`` (This file controls access to pleroma's console)
* ``mkdir -p 0750 /etc/pleroma && chown 0:pleroma /etc/pleroma``
* ``mkdir -p 0750 /var/lib/pleroma && chown 0:pleroma /var/lib/pleroma``

## Service files

Contributed OpenRC (`init.d/pleroma`) and systemd (`pleroma.service`) service files present in ``./rel/files/installation/`` (relative to source dir) get copied to ``${relpath}/installation/`` you can copy & modify those into the appropriate directories for your system.
