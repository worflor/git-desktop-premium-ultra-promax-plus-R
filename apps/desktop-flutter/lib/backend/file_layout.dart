// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

/// Returns the final path component (filename) of [path], normalising
/// both forward- and back-slashes.
String pathBasename(String path) {
  final norm = path.replaceAll('\\', '/');
  final idx = norm.lastIndexOf('/');
  return idx < 0 ? norm : norm.substring(idx + 1);
}
