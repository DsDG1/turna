
import { FlutterAbility, FlutterEngine } from '@ohos/flutter_ohos';
import { GeneratedPluginRegistrant } from '../plugins/GeneratedPluginRegistrant';
import RdbPlugin from '../plugins/RdbPlugin';
import FilePickerPlugin from '../plugins/FilePickerPlugin';
import XiaoyiPlugin from '../plugins/XiaoyiPlugin';

export default class EntryAbility extends FlutterAbility {
  configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    // flutter_local_notifications reads globalThis.context lazily when its
    // MethodChannel is invoked (see MethodCallHandlerImpl.initialize). Set
    // it here — before any MethodChannel call — so the OHos notification
    // plugin can resolve the UIAbilityContext.
    globalThis.context = this.context;
    GeneratedPluginRegistrant.registerWith(flutterEngine)
    flutterEngine.getPlugins()?.add(new RdbPlugin())
    flutterEngine.getPlugins()?.add(new FilePickerPlugin())
    flutterEngine.getPlugins()?.add(new XiaoyiPlugin())
  }
}
