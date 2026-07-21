# Contributing to Manifold

Thanks for wanting to help. A few things worth knowing before you open a PR.

## What I'm looking for

App-side fixes and improvements are welcome. Bug reports, questions, "this
broke", "this is confusing", "X seems wrong" are all useful too.

PRs that touch the engine or the research components generally aren't what I'm
after. The math underneath is specific and easy to break in ways that don't
look broken, and unwinding that costs more than it saves. Read it, fork it,
yoink from it, but the engine isn't a community surface.

## Which license your change lands under

Manifold is mixed. Most of it is GPL-3.0-or-later with the Manifold-Woflo
exception; the reusable Woflo research components keep their Woflo Labs
community-source terms. The destination path of your change decides which one
applies to it, so a fix landing in a GPL path is GPL, and a change to a research
path takes that path's terms. [LICENSE.md](LICENSE.md) has the exact boundary.

## Ownership and the contributor agreement

You keep ownership of your work. Nothing here assigns copyright to me.

Before a PR can merge, you accept the
[Woflo Labs Contributor Agreement 1.0](LICENSES/CONTRIBUTOR-AGREEMENT-1.0.md).
The PR template already carries the acceptance checkbox in
`.github/pull_request_template.md`; ticking it on your PR records that you've
read and agreed to it, and acceptance is required before I can merge.

The agreement gives me, as Project Steward, the room to maintain, relicense, and
commercially license work that's accepted into Manifold. In return, accepted
contributions stay publicly available in source form under meaningful public
permissions.

If your employer, client, or school might own rights in what you're submitting,
make sure you have their authorization to contribute it before you do.

When a PR has more than one author, each author records the same acceptance,
unless you have the authority to accept on their behalf.
