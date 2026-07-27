
import { FlutterAbility, FlutterEngine } from '@ohos/flutter_ohos';
import { GeneratedPluginRegistrant } from '../plugins/GeneratedPluginRegistrant';
import RdbPlugin from '../plugins/RdbPlugin';
import FilePickerPlugin from '../plugins/FilePickerPlugin';

export default class EntryAbility extends FlutterAbility {
  configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    GeneratedPluginRegistrant.registerWith(flutterEngine)
    flutterEngine.getPlugins()?.add(new RdbPlugin())
    flutterEngine.getPlugins()?.add(new FilePickerPlugin())
  }
}
