// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

import 'dart:math' as math;

import '../i18n/gen/strings.g.dart';

/// Locale-aware formatting for relative time, byte sizes, and the handful of
/// idle/age phrasings the UI renders. Every string here routes through slang
/// keys under `t.common.time` / `t.common.size`, so translations live in one
/// place while the arithmetic (thresholds, rounding) stays byte-identical to
/// the hand-rolled formatters these functions replaced.
///
/// Each function mirrors exactly one former call-site formatter — where two
/// surfaces phrased the same concept differently ('3d ago' vs 'idle 3 days',
/// or floor vs truncating division) they stay separate on purpose. Callers
/// keep passing nothing for [now]; it exists only so tests can pin the clock.

// ── Byte sizes ────────────────────────────────────────────────────────────

/// Sidebar repo-size readout. Input is in KILOBYTES (git's `count-objects`
/// size). KB shown as-is, MB rounded, GB to one decimal.
String compactSize(int kb) {
  if (kb < 1024) return t.common.size.kb(n: kb);
  final mb = kb / 1024;
  if (mb < 1024) return t.common.size.mb(n: mb.round());
  final gb = mb / 1024;
  return t.common.size.gb(n: gb.toStringAsFixed(1));
}

/// Media-preview byte readout. Input is in BYTES. B shown as-is, KB and MB to
/// one decimal; no GB tier.
String formatByteSize(int bytes) {
  if (bytes < 1024) return t.common.size.bytes(n: bytes);
  if (bytes < 1024 * 1024) {
    return t.common.size.kb(n: (bytes / 1024).toStringAsFixed(1));
  }
  return t.common.size.mb(n: (bytes / (1024 * 1024)).toStringAsFixed(1));
}

// ── Relative time — full 'ago' phrasings ──────────────────────────────────

/// Sidebar last-active. Input is UNIX SECONDS. Sub-minute reads 'now'; no
/// weeks tier; months/years via truncating division.
String compactAge(int unixSeconds, {DateTime? now}) {
  final delta = (now ?? DateTime.now()).difference(
      DateTime.fromMillisecondsSinceEpoch(unixSeconds * 1000));
  if (delta.inMinutes < 1) return t.common.time.now;
  if (delta.inMinutes < 60) return t.common.time.minutesAgo(n: delta.inMinutes);
  if (delta.inHours < 24) return t.common.time.hoursAgo(n: delta.inHours);
  if (delta.inDays < 30) return t.common.time.daysAgo(n: delta.inDays);
  if (delta.inDays < 365) {
    return t.common.time.monthsAgo(n: delta.inDays ~/ 30);
  }
  return t.common.time.yearsAgo(n: delta.inDays ~/ 365);
}

/// Branch-card recency. Sub-minute reads 'just now'; carries a weeks tier;
/// months/years via floored division.
String relativeTime(DateTime then, {DateTime? now}) {
  final delta = (now ?? DateTime.now()).difference(then);
  if (delta.inMinutes < 1) return t.common.time.justNow;
  if (delta.inMinutes < 60) return t.common.time.minutesAgo(n: delta.inMinutes);
  if (delta.inHours < 24) return t.common.time.hoursAgo(n: delta.inHours);
  if (delta.inDays < 7) return t.common.time.daysAgo(n: delta.inDays);
  if (delta.inDays < 30) {
    return t.common.time.weeksAgo(n: (delta.inDays / 7).floor());
  }
  if (delta.inDays < 365) {
    return t.common.time.monthsAgo(n: (delta.inDays / 30).floor());
  }
  return t.common.time.yearsAgo(n: (delta.inDays / 365).floor());
}

/// Stash-card recency (ISO input, local-time). Sub-minute reads 'just now';
/// no weeks tier; unparseable input renders empty.
String relativeAge(String iso, {DateTime? now}) {
  try {
    final then = DateTime.parse(iso).toLocal();
    final diff = (now ?? DateTime.now()).difference(then);
    if (diff.inMinutes < 1) return t.common.time.justNow;
    if (diff.inMinutes < 60) return t.common.time.minutesAgo(n: diff.inMinutes);
    if (diff.inHours < 24) return t.common.time.hoursAgo(n: diff.inHours);
    if (diff.inDays < 30) return t.common.time.daysAgo(n: diff.inDays);
    if (diff.inDays < 365) {
      return t.common.time.monthsAgo(n: (diff.inDays / 30).floor());
    }
    return t.common.time.yearsAgo(n: (diff.inDays / 365).floor());
  } catch (_) {
    return '';
  }
}

/// History commit-list recency (ISO input). Sub-45s reads 'just now'; carries
/// a weeks tier; unparseable input falls back to the leading ISO date.
String relativeDate(String iso, {DateTime? now}) {
  try {
    final dt = DateTime.parse(iso);
    final diff = (now ?? DateTime.now()).difference(dt);
    final s = diff.inSeconds;
    if (s < 45) return t.common.time.justNow;
    final m = diff.inMinutes;
    if (m < 60) return t.common.time.minutesAgo(n: m);
    final h = diff.inHours;
    if (h < 24) return t.common.time.hoursAgo(n: h);
    final days = diff.inDays;
    if (days < 7) return t.common.time.daysAgo(n: days);
    if (days < 30) return t.common.time.weeksAgo(n: (days / 7).floor());
    if (days < 365) return t.common.time.monthsAgo(n: (days / 30).floor());
    return t.common.time.yearsAgo(n: (days / 365).floor());
  } catch (_) {
    return iso.length > 10 ? iso.substring(0, 10) : iso;
  }
}

/// History timeline recency (ISO input) using short-day thresholds but the
/// long 'ago' phrasings; unparseable input falls back to the leading ISO date.
String relativeAgeAgo(String iso, {DateTime? now}) {
  try {
    final dt = DateTime.parse(iso);
    final diff = (now ?? DateTime.now()).difference(dt);
    if (diff.inDays > 365) {
      return t.common.time.yearsAgo(n: (diff.inDays / 365).floor());
    }
    if (diff.inDays > 30) {
      return t.common.time.monthsAgo(n: (diff.inDays / 30).floor());
    }
    if (diff.inDays > 0) return t.common.time.daysAgo(n: diff.inDays);
    if (diff.inHours > 0) return t.common.time.hoursAgo(n: diff.inHours);
    return t.common.time.minutesAgo(n: diff.inMinutes);
  } catch (_) {
    return iso.length > 10 ? iso.substring(0, 10) : iso;
  }
}

/// X-ray strip recency (ISO input). Negative or sub-45s reads 'just now';
/// caps at a days tier, then falls back to the leading ISO date. Unparseable
/// input returns verbatim.
String relativeTimeCapped(String iso, {DateTime? now}) {
  final d = DateTime.tryParse(iso);
  if (d == null) return iso;
  final diff = (now ?? DateTime.now()).difference(d);
  if (diff.isNegative) return t.common.time.justNow;
  if (diff.inSeconds < 45) return t.common.time.justNow;
  if (diff.inMinutes < 60) return t.common.time.minutesAgo(n: diff.inMinutes);
  if (diff.inHours < 24) return t.common.time.hoursAgo(n: diff.inHours);
  if (diff.inDays < 30) return t.common.time.daysAgo(n: diff.inDays);
  return iso.length >= 10 ? iso.substring(0, 10) : iso;
}

/// Workspace-shell "last touched" recency phrase (the bare relative token, no
/// prefix). Sub-minute reads 'just now'; caps at a months tier, no years.
String lastTouchedRelative(DateTime lastActivity, {DateTime? now}) {
  final age = (now ?? DateTime.now()).difference(lastActivity);
  if (age.inMinutes < 1) return t.common.time.justNow;
  if (age.inMinutes < 60) return t.common.time.minutesAgo(n: age.inMinutes);
  if (age.inHours < 24) return t.common.time.hoursAgo(n: age.inHours);
  if (age.inDays < 30) return t.common.time.daysAgo(n: age.inDays);
  return t.common.time.monthsAgo(n: (age.inDays / 30).floor());
}

// ── Relative time — short (no 'ago') phrasings ────────────────────────────

/// History hover-caption age (ISO input): one token, y/mo/d/h/m via floored
/// division with a minute floor of 0; unparseable input falls back to the
/// leading ISO date.
String relAgeShort(String iso, {DateTime? now}) {
  try {
    final dt = DateTime.parse(iso);
    final diff = (now ?? DateTime.now()).difference(dt);
    if (diff.inDays > 365) {
      return t.common.time.yearsShort(n: (diff.inDays / 365).floor());
    }
    if (diff.inDays > 30) {
      return t.common.time.monthsShort(n: (diff.inDays / 30).floor());
    }
    if (diff.inDays > 0) return t.common.time.daysShort(n: diff.inDays);
    if (diff.inHours > 0) return t.common.time.hoursShort(n: diff.inHours);
    return t.common.time.minutesShort(n: math.max(diff.inMinutes, 0));
  } catch (_) {
    return iso.length > 10 ? iso.substring(0, 10) : iso;
  }
}

/// Diff trail-strip age (ISO input): one token, y/mo via truncating division,
/// then d/h/m; unparseable input renders empty.
String relativeDateShort(String iso, {DateTime? now}) {
  try {
    final date = DateTime.parse(iso);
    final diff = (now ?? DateTime.now()).difference(date);
    if (diff.inDays > 365) return t.common.time.yearsShort(n: diff.inDays ~/ 365);
    if (diff.inDays > 30) return t.common.time.monthsShort(n: diff.inDays ~/ 30);
    if (diff.inDays > 0) return t.common.time.daysShort(n: diff.inDays);
    if (diff.inHours > 0) return t.common.time.hoursShort(n: diff.inHours);
    return t.common.time.minutesShort(n: diff.inMinutes);
  } catch (_) {
    return '';
  }
}

/// Palette commit-age chip (ISO input): 'TODAY' same-day, then d/w/months(as
/// 'm')/y via rounded division; unparseable input renders empty.
String commitAgeChip(String iso, {DateTime? now}) {
  try {
    final age = (now ?? DateTime.now()).difference(DateTime.parse(iso));
    if (age.inDays == 0) return t.common.time.today;
    if (age.inDays < 7) return t.common.time.daysShort(n: age.inDays);
    if (age.inDays < 30) {
      return t.common.time.weeksShort(n: (age.inDays / 7).round());
    }
    if (age.inDays < 365) {
      return t.common.time.commitMonthsShort(n: (age.inDays / 30).round());
    }
    return t.common.time.yearsShort(n: (age.inDays / 365).round());
  } catch (_) {
    return '';
  }
}

// ── Idle phrasings (branch lifecycle) ─────────────────────────────────────

/// Semantics narration for an idle/corpse branch. Null date reads 'idle';
/// under a year reads 'idle {n} days'; a year+ inflects 'idle 1 year' /
/// 'idle 3 years'.
String idlePhrase(DateTime? last, {DateTime? now}) {
  if (last == null) return t.common.time.idle;
  final d = (now ?? DateTime.now()).difference(last).inDays;
  if (d < 365) return t.common.time.idleDays(n: d);
  return t.common.time.idleYears(n: (d / 365).floor());
}

/// Compact wordless idle age for the data zone. Null date returns null;
/// under a year reads '{n}d'; a year+ reads '{n}y'.
String? idleAgeShort(DateTime? last, {DateTime? now}) {
  if (last == null) return null;
  final d = (now ?? DateTime.now()).difference(last).inDays;
  if (d < 365) return t.common.time.daysShort(n: d);
  return t.common.time.yearsShort(n: (d / 365).floor());
}
