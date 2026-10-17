
import { FlutterAbility, FlutterEngine } from '@ohos/flutter_ohos';
import { GeneratedPluginRegistrant } from '../plugins/GeneratedPluginRegistrant';
import FilePickerPlugin from '../plugins/FilePickerPlugin';
import AudioPlugin from '../plugins/AudioPlugin';
import TtsPlugin from '../plugins/TtsPlugin';
import SherpaTtsPlugin from '../plugins/SherpaTtsPlugin';
import AnkiReviewerPlugin from '../plugins/AnkiReviewerPlugin';

export default class EntryAbility extends FlutterAbility {
  configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    GeneratedPluginRegistrant.registerWith(flutterEngine)
    // Turna's own platform channels, registered here rather than in
    // GeneratedPluginRegistrant: the Flutter tool generates that file from the
    // plugins declared in pubspec.yaml, and these are hand-written sources
    // in this directory with no package to declare them. Editing the generated
    // file would work until the next `flutter pub get` rewrote it and silently
    // dropped the registration, leaving the method channel without a handler.
    // The ability's own UIAbilityContext, not a binding lookup: DocumentViewPicker
    // needs the real type. The plugin used to read `globalThis.context`, which
    // ArkTS forbids and which nothing ever assigned, so every pick failed with
    // NO_CONTEXT.
    flutterEngine.getPlugins()?.add(new FilePickerPlugin(this.context));
    // Audio and TTS have no OHOS Flutter plugin to declare in pubspec.yaml
    // (audioplayers / flutter_tts have none, and overriding them is forbidden),
    // so they are registered here like the other hand-written channels.
    // Both need the ability's own UIAbilityContext: cacheDir for staging a
    // bundled asset and resourceManager for reading one out of the hap.
    flutterEngine.getPlugins()?.add(new AudioPlugin(this.context));
    flutterEngine.getPlugins()?.add(new TtsPlugin());
    // sherpa-onnx synthesises; AudioBackend plays. Registered here for the same
    // reason as the other hand-written channels — no pubspec.yaml package to
    // declare, and `GeneratedPluginRegistrant` is regenerated from that list.
    flutterEngine.getPlugins()?.add(new SherpaTtsPlugin(this.context));
    // ADR 0050 §6 step 5b. The Official Anki reviewer's channel, which during
    // the probe batch only launches the capability probe ability. Needs the
    // UIAbilityContext for the same reason as the other four: `startAbility`
    // is an ability-level call and cannot be served by an ApplicationContext.
    flutterEngine.getPlugins()?.add(new AnkiReviewerPlugin(this.context));
  }
}

