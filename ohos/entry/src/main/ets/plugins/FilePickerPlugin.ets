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
    // binding.getApplicationContext() returns an ApplicationContext, NOT a
    // UIAbilityContext. DocumentViewPicker.select() requires a real
    // UIAbilityContext to launch the system file-picker UI; passing an
    // ApplicationContext causes error 13900042 ("Unknown error").
    // EntryAbility.configureFlutterEngine stores the real UIAbilityContext
    // on globalThis.context — use that instead.
    this.ctx = globalThis.context as common.UIAbilityContext;
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
          case 'scanForFiles':
            this.scanForFiles(call, result);
            break;
          case 'importFromPath':
            this.importFromPath(call, result);
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
    // Prefer the live UIAbilityContext from globalThis (set by EntryAbility)
    // over the stale one captured at attach time, since the ability may have
    // been recreated (e.g. after a cold start edge case).
    const abilityContext =
      (globalThis.context as common.UIAbilityContext) ?? this.ctx;
    try {
      const documentSelectOptions = new picker.DocumentSelectOptions();
      // Filter by extensions passed from Flutter (e.g. ['.apkg', '.colpkg']).
      const extsRaw = call.argument('extensions') as Array<string>;
      const exts: Array<string> = extsRaw ?? ['.apkg', '.colpkg'];
      // HarmonyOS DocumentViewPicker requires the 'description|suffix' format
      // for each fileSuffixFilters entry (e.g. '图片(.png, .jpg)|.png,.jpg').
      // A bare suffix like '.apkg' is rejected by the picker with
      // "Please check the parameter you entered." (13900042). Synthesize a
      // generic description when the caller hands us a plain suffix.
      const normalized = exts.map(raw => {
        const e = raw.startsWith('.') ? raw : `.${raw}`;
        return raw.includes('|') ? raw : `文件(${e})|${e}`;
      });
      documentSelectOptions.fileSuffixFilters = normalized;
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
          // 13900042 = "Unknown error". On a stock phone/tablet it usually
          // means the system FilePicker sheet (com.huawei.hmos.security.
          // pickersheet) is missing — common on emulator/trimmed ROMs.
          // 16000001 = ability not found. The bundled suggestion nudges the
          // user to try a real device or install Files.
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

  /// Copy the picked file (referenced by URI) into the app sandbox so Flutter
  /// can read it by path. Returns the sandbox file path to Flutter.
  private copyToSandbox(uri: string, result: MethodResult): void {
    try {
      const srcFile = fs.openSync(uri, fs.OpenMode.READ_ONLY);
      const ctx = (globalThis.context as common.UIAbilityContext) ?? this.ctx!;
      const sandboxDir = ctx.filesDir;
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

  /// Scan well-known directories for files with the requested extensions.
  ///
  /// Used as a fallback when the system FilePicker sheet isn't available
  /// (e.g. trimmed emulator ROMs where com.huawei.hmos.security.pickersheet
  /// is missing). Scans (recursively, shallow):
  /// - The app's own sandbox: filesDir, cacheDir, tempDir
  /// - Subfolders named 'Download' or 'download' under filesDir
  /// - Common public roots reachable from sandbox-relative paths
  ///
  /// Args (from Flutter): { 'extensions': ['.apkg', '.colpkg'] }
  /// Returns: Array<{ path: string, name: string, size: number }> — paths
  /// point directly at the files (no copy needed), since they're already
  /// inside the app sandbox.
  private scanForFiles(call: MethodCall, result: MethodResult): void {
    if (!this.ctx) {
      result.error('NO_CONTEXT', 'Application context not available', null);
      return;
    }
    const ctx = (globalThis.context as common.UIAbilityContext) ?? this.ctx;
    const extsRaw = call.argument('extensions') as Array<string>;
    const suffixes = (extsRaw ?? ['.apkg', '.colpkg'])
      .map(e => e.startsWith('.') ? e.toLowerCase() : '.' + e.toLowerCase());

    const seen = new Set<string>();
    const out: Array<Record<string, Object>> = [];
    const maxDepth = 4;
    const maxResults = 200;

    const candidateRoots: Array<string> = [
      ctx.filesDir,
      ctx.cacheDir,
      // Common sub-paths users may stash Anki exports in. These are
      // inside the app sandbox so no permission is required.
      `${ctx.filesDir}/Download`,
      `${ctx.filesDir}/download`,
      `${ctx.cacheDir}/Download`,
      // External-sandbox paths the app can read (path_provider exposes
      // these via getExternalStoragePath / getExternalStoragePaths).
    ];

    const visit = (dir: string, depth: number): void => {
      if (out.length >= maxResults || depth > maxDepth) return;
      let names: Array<string>;
      try {
        // listFileSync returns names of immediate children (no recursion).
        names = fs.listFileSync(dir);
      } catch (e) {
        return;
      }
      for (const name of names) {
        if (out.length >= maxResults) return;
        const fullPath = `${dir}/${name}`;
        if (seen.has(fullPath)) continue;
        seen.add(fullPath);
        // We can't tell file vs dir from the name alone; statSync to
        // disambiguate and pull size in one shot.
        let st: fs.Stat;
        try {
          st = fs.statSync(fullPath);
        } catch (e) {
          continue;
        }
        if (st.isDirectory()) {
          visit(fullPath, depth + 1);
        } else {
          const lower = name.toLowerCase();
          if (suffixes.some(s => lower.endsWith(s))) {
            out.push({
              'path': fullPath,
              'name': name,
              'size': st.size,
            } as Record<string, Object>);
          }
        }
      }
    };

    for (const root of candidateRoots) {
      try {
        if (fs.accessSync(root)) {
          visit(root, 0);
        }
      } catch (e) {
        // root not accessible, skip
      }
    }

    hilog.info(0x0000, TAG,
      'scanForFiles: scanned %d roots, found %d matches',
      candidateRoots.length, out.length);
    result.success(out);
  }

  /// Import a file by absolute path.
  ///
  /// Verifies the path exists, has an allowed extension, and is readable by
  /// the app. Returns the absolute path on success. Used as a manual
  /// fallback: the user types/pastes a full path (e.g. from a file manager)
  /// and we open it directly.
  ///
  /// Args (from Flutter): { 'path': string, 'extensions': ['.apkg',...] }
  /// Returns: { 'path': string, 'name': string, 'size': number } on success.
  private importFromPath(call: MethodCall, result: MethodResult): void {
    const filePath = (call.argument('path') as string | null)?.trim();
    if (!filePath) {
      result.error('EMPTY_PATH', '未提供文件路径', null);
      return;
    }
    const extsRaw = call.argument('extensions') as Array<string>;
    const suffixes = (extsRaw ?? ['.apkg', '.colpkg'])
      .map(e => e.startsWith('.') ? e.toLowerCase() : '.' + e.toLowerCase());
    const lower = filePath.toLowerCase();
    if (!suffixes.some(s => lower.endsWith(s))) {
      result.error('BAD_EXTENSION',
        `文件后缀不匹配（仅支持 ${suffixes.join(', ')}）`, null);
      return;
    }
    try {
      if (!fs.accessSync(filePath)) {
        result.error('NOT_FOUND', `文件不存在或无法访问：${filePath}`, null);
        return;
      }
      const st = fs.statSync(filePath);
      if (!st.isFile()) {
        result.error('NOT_A_FILE', `不是普通文件：${filePath}`, null);
        return;
      }
      const name = filePath.split('/').pop() ?? '';
      result.success({
        'path': filePath,
        'name': name,
        'size': st.size,
      } as Record<string, Object>);
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(0x0000, TAG, 'importFromPath failed, code: %{public}s, msg: %{public}s',
        `${err.code}`, `${err.message}`);
      result.error('ACCESS_ERROR',
        `无法访问该路径: [${err.code}] ${err.message}`, null);
    }
  }
}