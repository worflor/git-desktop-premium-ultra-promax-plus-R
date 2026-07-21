// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

class GitResult<T> {
  final T? data;
  final String? error;

  bool get ok => error == null;

  const GitResult.ok(T this.data) : error = null;

  const GitResult.err(String this.error) : data = null;
}
