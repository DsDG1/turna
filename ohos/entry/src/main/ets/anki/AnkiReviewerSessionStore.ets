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
// second launch of a reviewer used to race its ready wait against the
// previous session (still present, already shell-ready) and present onto a
// destroyed page's Web controller. Shell readiness is pushed from
// `markShellReady` through [notifyReviewerShellReady]; callers do not poll.

import { AnkiReviewerSession } from './AnkiReviewerSession';

let currentSession: AnkiReviewerSession | undefined = undefined;
let sessionEpoch: number = 0;

export function beginReviewerSession(mediaRoot: string): AnkiReviewerSession {
  sessionEpoch += 1;
  currentSession = new AnkiReviewerSession(mediaRoot);
  currentSession.setShellReadyHook((): void => {
    notifyReviewerShellReady();
  });
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

type ShellReadyListener = () => void;

let shellReadyListeners: Array<ShellReadyListener> = [];

/// True only for a session begun after [wantEpoch] whose shell has loaded.
/// A still-ready session from an earlier launch does not qualify (B3).
export function shellReadyAfter(wantEpoch: number): boolean {
  const session: AnkiReviewerSession | undefined = currentSession;
  return session !== undefined && sessionEpoch > wantEpoch && session.isShellReady();
}

export function subscribeShellReady(listener: ShellReadyListener): () => void {
  shellReadyListeners.push(listener);
  return (): void => {
    const kept: Array<ShellReadyListener> = [];
    for (let index: number = 0; index < shellReadyListeners.length; index++) {
      const item: ShellReadyListener | undefined = shellReadyListeners[index];
      if (item !== undefined && item !== listener) {
        kept.push(item);
      }
    }
    shellReadyListeners = kept;
  };
}

export function notifyReviewerShellReady(): void {
  const snapshot: Array<ShellReadyListener> = shellReadyListeners.slice();
  for (let index: number = 0; index < snapshot.length; index++) {
    const listener: ShellReadyListener | undefined = snapshot[index];
    if (listener !== undefined) {
      listener();
    }
  }
}

/// A cancel that arrived while no session existed yet.
///
/// P0-1 opens the reviewer *before* the batch is loaded, so a cancel can land
/// in the window between `startAbilityForResult` and the ability's
/// `onWindowStageCreate`. Dropping it there would leave exactly the empty
/// reviewer page the warm-up is supposed to avoid producing. The request is
/// remembered instead, and the page consumes it right after installing its
/// cancel listener — not here, because at `beginReviewerSession` time the page
/// has not subscribed yet and the callback would have nowhere to go.
let cancelPending: boolean = false;

/// Cancels the live session, or remembers the request until one exists.
export function requestReviewerCancel(): void {
  const session: AnkiReviewerSession | undefined = currentSession;
  if (session === undefined) {
    cancelPending = true;
    return;
  }
  session.requestCancel();
}

/// Reads and clears the pending flag. Called by the page after it has
/// installed `setCancelListener`, so a warm-up cancelled during boot still
/// ends instead of sitting on screen.
export function consumePendingReviewerCancel(): boolean {
  const pending: boolean = cancelPending;
  cancelPending = false;
  return pending;
}
