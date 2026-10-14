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

import { AnkiReviewerSession } from './AnkiReviewerSession';

let currentSession: AnkiReviewerSession | undefined = undefined;

export function beginReviewerSession(mediaRoot: string): AnkiReviewerSession {
  currentSession = new AnkiReviewerSession(mediaRoot);
  return currentSession;
}

export function reviewerSession(): AnkiReviewerSession | undefined {
  return currentSession;
}
