
import { FlutterAbility, FlutterEngine } from '@ohos/flutter_ohos';
import { GeneratedPluginRegistrant } from '../plugins/GeneratedPluginRegistrant';
import RdbPlugin from '../plugins/RdbPlugin';
import FilePickerPlugin from '../plugins/FilePickerPlugin';

export default class EntryAbility extends FlutterAbility {
  configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    GeneratedPluginRegistrant.registerWith(flutterEngine)
    // Turna's own platform channels, registered here rather than in
    // GeneratedPluginRegistrant: the Flutter tool generates that file from the
    // plugins declared in pubspec.yaml, and these two are hand-written sources
    // in this directory with no package to declare them. Editing the generated
    // file would work until the next `flutter pub get` rewrote it and silently
    // dropped the registration, leaving the method channel without a handler.
    flutterEngine.getPlugins()?.add(new RdbPlugin());
    flutterEngine.getPlugins()?.add(new FilePickerPlugin());
  }
}
