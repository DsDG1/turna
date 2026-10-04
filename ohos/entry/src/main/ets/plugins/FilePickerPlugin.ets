// Copyright (c) 2024 Turna. All rights reserved.
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
const CHANNEL = "me.dsdogs.turna/file_picker";

// Characters no common filesystem accepts, plus the C0 control range. A space
// is deliberately absent: it is legal in a name and common in the files people
// actually pick. The picked name comes from another app, so it is untrusted
// input about to be handed to `openSync` as a path.
const UNSAFE_NAME_CHARS = /[\\/:*?"<>|\u0000-\u001F]/g;

export default class FilePickerPlugin implements FlutterPlugin {
  private channel: MethodChannel | null = null;

  // Injected rather than discovered. `DocumentViewPicker` requires a real
  // UIAbilityContext, and a FlutterPluginBinding only hands out an
  // ApplicationContext — casting one to the other is a type lie that happens to
  // work for APIs that accept a Context and fails for the ones that do not.
  //
  // The previous version read `globalThis.context`, which ArkTS forbids
  // (`arkts-no-globalthis`) and which nothing ever assigned, so every pick
  // failed with NO_CONTEXT. The ability now passes its own context in.
  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }

  private context: common.UIAbilityContext;

  getUniqueClassName(): string {
    return "FilePickerPlugin";
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(
      binding.getBinaryMessenger(),
      CHANNEL
    );
    this.channel.setMethodCallHandler({
      onMethodCall: (call: MethodCall, result: MethodResult): void => {
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
  }

  private pickFile(call: MethodCall, result: MethodResult): void {
    const context = this.context;
    if (!context) {
      hilog.error(0x0000, TAG, 'No UIAbilityContext was injected by the ability.');
      result.error('NO_CONTEXT', 'Application context not available', null);
      return;
    }
    try {
      // The extension filter arrives from Dart under `extensions`. The two
      // names must stay in step: when they drifted apart the filter was
      // silently dropped and every pick came back narrowed to a stale
      // hardcoded Anki pair.
      const extsRaw = call.argument('extensions') as Array<string>;
      const exts = normalizeExtensions(extsRaw);
      const documentSelectOptions = new picker.DocumentSelectOptions();
      // HarmonyOS DocumentViewPicker requires the 'description|suffix' format
      // for each fileSuffixFilters entry (e.g. '图片(.png, .jpg)|.png,.jpg').
      // A bare suffix like '.apkg' is rejected with 13900042 ("Please check the
      // parameter you entered."), so wrap each one in a generic description.
      documentSelectOptions.fileSuffixFilters = exts.map(e => `文件(${e})|${e}`);
      documentSelectOptions.maxSelectNumber = 1;
      const documentPicker = new picker.DocumentViewPicker(context);
      documentPicker.select(documentSelectOptions)
        .then((uris: Array<string>) => {
          if (!uris || uris.length === 0) {
            result.success(null);
            return;
          }
          this.stageUri(uris[0], exts, result);
        })
        .catch((err: BusinessError) => {
          hilog.error(0x0000, TAG, 'pickFile failed, code: %{public}s, msg: %{public}s',
            `${err.code}`, `${err.message}`);
          // 13900042 = "Unknown error", 16000001 = ability not found. Both
          // point at the system FilePicker sheet being unavailable.
          const hint = (err.code === 13900042 || err.code === 16000001)
            ? '（请在装有完整鸿蒙系统的真机上重试，或安装"文件管理"应用）'
            : '';
          result.error('PICK_ERROR',
            `选择文件失败: [${err.code}] ${err.message}${hint}`, null);
        });
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(0x0000, TAG, 'pickFile exception, code: %{public}s, msg: %{public}s',
        `${err.code}`, `${err.message}`);
      result.error('PICK_ERROR', `选择文件失败: [${err.code}] ${err.message}`, null);
    }
  }

  /// Copies the picked file (referenced by URI) into the app's cache
  /// directory so Dart can read it by path, and reports the real name and size
  /// alongside it.
  ///
  /// The name has to be the picked file's own. The previous version wrote
  /// `anki_import_<timestamp>.apkg` unconditionally, which put a wrong
  /// extension on the bytes: every caller in this app asks for something else
  /// (`zip`, `json`, `turnapack`), so the suffix check downstream rejected a
  /// correctly picked file every single time, and the only extension that
  /// worked was the Anki one this build does not ship.
  private stageUri(uri: string, exts: Array<string>, result: MethodResult): void {
    try {
      this.discardStaged();

      const name = safeFileName(lastSegment(uri), exts);
      // cacheDir, not filesDir: this is a transient staging copy of a file
      // picked from elsewhere, so it belongs where the OS may reclaim it rather
      // than in durable app storage.
      const destPath = `${this.context.cacheDir}/${name}`;
      const srcFile = fs.openSync(uri, fs.OpenMode.READ_ONLY);
      const destFile = fs.openSync(destPath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY);
      let size: number = 0;
      try {
        fs.copyFileSync(srcFile.fd, destFile.fd);
        // Stat the copy, not the URI: a provider-backed URI may not have a
        // knowable length, or may make asking for one expensive.
        size = fs.statSync(destPath).size;
      } finally {
        fs.closeSync(srcFile);
        fs.closeSync(destFile);
      }
      this.stagedPath = destPath;
      hilog.info(0x0000, TAG, 'Staged picked file: %{public}s', destPath);
      // Name and size travel with the path so Dart can hand back an honest
      // PlatformFile instead of one claiming size 0 under a synthesised name.
      result.success({ path: destPath, name: name, size: size });
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(0x0000, TAG, 'stageUri failed, code: %{public}s, msg: %{public}s',
        `${err.code}`, `${err.message}`);
      result.error('COPY_ERROR', `复制文件失败: [${err.code}] ${err.message}`, null);
    }
  }

  // The staged copy from the previous pick, replaced on every successful pick
  // so repeated imports cannot pile up: the file is only needed until the
  // caller has read it into its own storage.
  private stagedPath: string | null = null;

  /// Removes the previous staged copy. Best-effort: the OS is free to clear
  /// cacheDir at any time, and a failure here must not stop the user from
  /// picking another file.
  private discardStaged(): void {
    const previous = this.stagedPath;
    if (!previous) return;
    this.stagedPath = null;
    try {
      fs.unlinkSync(previous);
    } catch (e) {
      // Best-effort cleanup of a cache file; nothing depends on it succeeding.
    }
  }
}

/// Normalizes caller-supplied extensions to lowercase, dot-prefixed suffixes.
/// An empty or unusable list means no filter at all rather than a stale
/// hardcoded pair: hiding the user's own file from them is worse than showing
/// everything and letting Dart's suffix check reject it.
function normalizeExtensions(raw: Array<string> | null | undefined): Array<string> {
  if (!raw || raw.length === 0) {
    return [];
  }
  const normalized: Array<string> = [];
  for (const item of raw) {
    if (typeof item !== 'string') continue;
    const withDot = item.startsWith('.') ? item : `.${item}`;
    if (withDot.length > 1) {
      normalized.push(withDot.toLowerCase());
    }
  }
  return normalized;
}

/// The last path segment of a `file://` URI, percent-decoded. DocumentViewPicker
/// returns a URI and nothing else, so both the display name and the extension
/// have to come from here.
function lastSegment(uri: string): string {
  const withoutQuery = uri.split('?')[0];
  const trimmed = withoutQuery.endsWith('/') ? withoutQuery.slice(0, -1) : withoutQuery;
  const slash = trimmed.lastIndexOf('/');
  const segment = slash === -1 ? trimmed : trimmed.slice(slash + 1);
  return percentDecode(segment);
}

function percentDecode(value: string): string {
  if (!value.includes('%')) return value;
  let out = '';
  for (let i = 0; i < value.length; i++) {
    if (value[i] !== '%' || i + 2 >= value.length) {
      out += value[i];
      continue;
    }
    const hex = value.slice(i + 1, i + 3);
    if (!/^[0-9a-fA-F]{2}$/.test(hex)) {
      out += value[i];
      continue;
    }
    out += String.fromCharCode(parseInt(hex, 16));
    i += 2;
  }
  return out;
}

/// Turns a foreign, untrusted name into one safe to hand to `openSync`, keeping
/// the extension so the caller's suffix check can still see it. When the name
/// carries no usable extension the first requested one is appended: a name
/// without an extension is what a provider-backed URI looks like, and guessing
/// wrong here would reintroduce the bug this replaced.
function safeFileName(raw: string, exts: Array<string>): string {
  let name = raw.replace(UNSAFE_NAME_CHARS, '_');
  const dot = name.lastIndexOf('.');
  const hasExtension = dot > 0 && dot < name.length - 1;
  if (!hasExtension && exts.length > 0) {
    name = `${name}${exts[0]}`;
  }
  if (name.length === 0 || name === '.' || name === '..') {
    name = `import${exts.length > 0 ? exts[0] : ''}`;
  }
  return name;
}
