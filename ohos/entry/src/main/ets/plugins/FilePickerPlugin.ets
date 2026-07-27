// Copyright (c) 2024 VarnamalaPlus. All rights reserved.
// Native file picker for HarmonyOS — bridges @ohos.file.picker to Flutter
// via MethodChannel, since the file_picker Flutter plugin does not support OHos.

import {
  FlutterPlugin,
  FlutterPluginBinding
} from '@ohos/flutter_ohos/src/main/ets/embedding/engine/plugins/FlutterPlugin';
import MethodCall from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodCall';
import MethodChannel from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodChannel';
import { MethodResult } from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodChannel';
import { common } from '@kit.AbilityKit';
import { picker } from '@kit.CoreFileKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import hilog from '@ohos.hilog';

const TAG = "FilePickerPlugin";
const CHANNEL = "com.varnamala/file_picker";

export default class FilePickerPlugin implements FlutterPlugin {
  private channel: MethodChannel | null = null;
  private ctx: common.UIAbilityContext | null = null;

  getUniqueClassName(): string {
    return "FilePickerPlugin";
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    hilog.info(0x0000, TAG, 'onAttachedToEngine called');
    this.ctx = binding.getApplicationContext() as common.UIAbilityContext;
    this.channel = new MethodChannel(
      binding.getBinaryMessenger(),
      CHANNEL
    );
    this.channel.setMethodCallHandler({
      onMethodCall: (call: MethodCall, result: MethodResult): void => {
        hilog.info(0x0000, TAG, 'Received method call: %{public}s', call.method);
        switch (call.method) {
          case 'pickFile':
            this.pickFile(call, result);
            break;
          default:
            result.notImplemented();
        }
      }
    });
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    this.channel?.setMethodCallHandler(null);
    this.channel = null;
    this.ctx = null;
  }

  private pickFile(call: MethodCall, result: MethodResult): void {
    if (!this.ctx) {
      result.error('NO_CONTEXT', 'Application context not available', null);
      return;
    }
    try {
      // this.ctx is already a UIAbilityContext (cast in onAttachedToEngine).
      // Using it directly avoids the fragile FlutterManager.getUIAbility()
      // lookup, which returns undefined when the application context does not
      // match any registered UIAbility's context (causing
      // "Cannot read property context of undefined").
      const abilityContext = this.ctx as common.UIAbilityContext;
      const documentSelectOptions = new picker.DocumentSelectOptions();
      // Filter by extensions passed from Flutter (e.g. ['.apkg', '.colpkg']).
      const extsRaw = call.argument('extensions') as Array<string>;
      const exts: Array<string> = extsRaw ?? ['.apkg', '.colpkg'];
      documentSelectOptions.fileSuffixFilters = exts;
      documentSelectOptions.maxSelectNumber = 1;
      const documentPicker = new picker.DocumentViewPicker(abilityContext);
      documentPicker.select(documentSelectOptions)
        .then((uris: Array<string>) => {
          if (!uris || uris.length === 0) {
            result.success(null);
            return;
          }
          this.copyToSandbox(uris[0], result);
        })
        .catch((err: BusinessError) => {
          hilog.error(0x0000, TAG, 'pickFile failed, code: %{public}s, msg: %{public}s',
            `${err.code}`, `${err.message}`);
          result.error('PICK_ERROR', `选择文件失败: [${err.code}] ${err.message}`, null);
        });
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(0x0000, TAG, 'pickFile exception, code: %{public}s, msg: %{public}s',
        `${err.code}`, `${err.message}`);
      result.error('PICK_ERROR', `选择文件失败: [${err.code}] ${err.message}`, null);
    }
  }

  /// Copy the picked file (referenced by URI) into the app sandbox so Flutter
  /// can read it by path. Returns the sandbox file path to Flutter.
  private copyToSandbox(uri: string, result: MethodResult): void {
    try {
      const srcFile = fs.openSync(uri, fs.OpenMode.READ_ONLY);
      const sandboxDir = this.ctx!.filesDir;
      const fileName = `anki_import_${Date.now()}.apkg`;
      const destPath = `${sandboxDir}/${fileName}`;
      const destFile = fs.openSync(destPath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY);
      try {
        fs.copyFileSync(srcFile.fd, destFile.fd);
      } finally {
        fs.closeSync(srcFile);
        fs.closeSync(destFile);
      }
      hilog.info(0x0000, TAG, 'Copied picked file to sandbox: %{public}s', destPath);
      result.success(destPath);
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(0x0000, TAG, 'copyToSandbox failed, code: %{public}s, msg: %{public}s',
        `${err.code}`, `${err.message}`);
      result.error('COPY_ERROR', `复制文件失败: [${err.code}] ${err.message}`, null);
    }
  }
}