<!--
SPDX-FileCopyrightText: 2026 Mario Campos <https://github.com/mariojcr>
SPDX-License-Identifier: Apache-2.0
-->

# Security

Report against the current `main` or a published tag, and say which image and
tag you used, how to reproduce it, and what it lets an attacker do. Keep live
credentials, server addresses and player data out of the report.

If this repository's [Security page](https://github.com/mariojcr/containers/security)
offers **Report a vulnerability**, use that private channel. If it does not,
open an issue asking for one, with no details of the vulnerability in it, and
wait for a reply. Do not publish exploit details in a public issue.

Two things worth knowing before you report:

- Both images run their process as root inside the container, and
  `net-nomad` additionally needs `NET_ADMIN` to do its job at all. That is the
  intended design, not a finding on its own.
- `proton` downloads game content from Steam at startup, under whatever
  credentials you give it (anonymous by default). Its own dependencies
  (DepotDownloader, GE-Proton) are pinned by checksum at build time.
