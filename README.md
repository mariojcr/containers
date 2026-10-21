<!--
SPDX-FileCopyrightText: 2026 Mario Campos <https://github.com/mariojcr>
SPDX-License-Identifier: Apache-2.0
-->

# containers

Small images for self-hosted infrastructure, one directory each, published to
`ghcr.io/mariojcr`.

| Image | What it is |
|---|---|
| [`proton`](proton/) | A Steam dedicated server in a container: DepotDownloader installs the game, the binary runs native or under GE-Proton |
| [`net-nomad`](net-nomad/) | Network sidecar for Nomad tasks: the allocation's firewall and an optional NAT-PMP forwarded port |

They run on a home cluster on Nomad, but neither assumes it: `proton` only
needs a volume and some environment variables, and `net-nomad` needs a shared
network namespace and `NET_ADMIN`.

## Tags

Every build publishes two: the version (`proton:11-11`, `net-nomad:1.0.0`),
which is rewritten each time, and `<version>-<short sha>`, which never moves.
Pin the second one where you care about knowing exactly what is running; a
restart then cannot bring in a different image than the one you tested.

## Builds

Each image has a workflow in `.github/workflows/` that runs when its directory
changes. Pull requests only check that the image builds; pushes to a branch
publish it.

## Dependency updates

Two bots, each doing what it is good at, and no credentials to store.

**Dependabot** (`.github/dependabot.yml`) takes the Dockerfiles' base images
and the workflows' actions. It is native to GitHub, so it needs no token, it
may write under `.github/workflows/`, and the pull requests it opens do
trigger the build — the bump is validated before it merges.

**Renovate** (`renovate.json5`, Mondays from its own workflow) takes what
Dependabot cannot read, which is versions that live inside a file:

- **GE-Proton**, the `ARG PROTON_VERSION` in proton's Dockerfile, which the
  workflow also reads the image tag from.
- **DepotDownloader**, the ARG next to it.

Both are pinned by checksum, and a post-upgrade task re-pins the checksum when
the version moves (`scripts/pin-proton.sh`, `scripts/pin-depotdownloader.sh`).
If one of those never runs, the build fails on the checksum, which is the
right failure: an unverified artifact is not installed.

Renovate runs with the Actions `GITHUB_TOKEN`, which has two limits: it cannot
write under `.github/workflows/` (hence the versions living in Dockerfiles and
the actions belonging to Dependabot), and the pull requests it opens do **not**
trigger other workflows. A GE-Proton bump is therefore validated when it lands
on `main`, not on the pull request; if that build fails, the published tag
stays as it was. Swapping the token for a GitHub App
(`actions/create-github-app-token`) closes that gap without a personal access
token.

For Renovate to open pull requests at all, the repository needs *Allow GitHub
Actions to create and approve pull requests*.

## License

[Apache-2.0](LICENSE).
