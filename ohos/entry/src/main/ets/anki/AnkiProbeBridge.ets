// Copyright (c) 2024 Turna. All rights reserved.
//
// The ArkTS object injected into the probe page as `AnkiProbeNative`.
//
// It is its own type rather than a field on the page or a method on
// `AnkiProbeReport`, because ArkTS hands the page *only* the public methods
// listed in `methodList`. Anything else on the object stays unreachable from
// page script, which is why the ability's completion sink is not here.

export class AnkiProbeBridge {
  private handler: ((raw: string) => void) | undefined = undefined;

  public attach(handler: (raw: string) => void): void {
    this.handler = handler;
  }

  /// Called from the page's JavaScript. Page script is untrusted input even
  /// here — it is running text this build assembled — so the payload is treated
  /// as an opaque string and nothing is parsed on this side of the boundary.
  public report(raw: string): void {
    const handler: ((raw: string) => void) | undefined = this.handler;
    if (handler === undefined) {
      return;
    }
    handler(raw);
  }
}
