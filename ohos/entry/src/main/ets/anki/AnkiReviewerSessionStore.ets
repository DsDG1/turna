// Copyright (c) 2024 Turna. All rights reserved.
//
// Process-wide handle on the running reviewer session.
//
// It must live in a library module, not in `AnkiReviewerPage.ets`: the toolchain
// compiles an `@Entry` page referenced by `main_pages.json` into its own module
// instance for the router, separate from the instance a direct importer of the
// same file sees. A session stored on the page's module state was therefore
// written by the ability and never read back by the page — proven on device by
// a `reviewer_not_open` 503 answered 35 ms *after* the ability had created the
// session, in the same process. Library modules are shared, so this file is the
// one place the ability (writer), the plugin (Dart's entry) and the page
// (reader) all agree on.
//
// B3: the store also hands out a monotonic epoch, one per session ever begun.
// A destroyed ability's session is removed on destroy, and `awaitReviewerReady`
// additionally refuses to accept any session from BEFORE its own call: the
// second launch of a reviewer used to race its `ready` poll against the
// previous session (still present, already shell-ready) and present onto a
// destroyed page's Web controller.

import { AnkiReviewerSession } from './AnkiReviewerSession';

let currentSession: AnkiReviewerSession | undefined = undefined;
let sessionEpoch: number = 0;

export function beginReviewerSession(mediaRoot: string): AnkiReviewerSession {
  sessionEpoch += 1;
  currentSession = new AnkiReviewerSession(mediaRoot);
  return currentSession;
}

/// Removes a session the ability is destroying. Identity-checked so a late
/// `onDestroy` from a superseded instance cannot drop its replacement (B6
/// singleton relaunches create the replacement from `onNewWant`).
export function endReviewerSession(session: AnkiReviewerSession): void {
  if (currentSession === session) {
    currentSession = undefined;
  }
}

export function reviewerSession(): AnkiReviewerSession | undefined {
  return currentSession;
}

/// Monotonic count of sessions ever begun in this process. Callers capture it
/// before launching a reviewer and only accept strictly newer sessions.
export function reviewerSessionEpoch(): number {
  return sessionEpoch;
}
