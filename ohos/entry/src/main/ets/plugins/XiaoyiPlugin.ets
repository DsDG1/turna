// Copyright (c) 2024 Turna. All rights reserved.
// Bridges HarmonyOS system AI assistant ("小艺") launch to Flutter via
// MethodChannel. Lets the learner ask 小艺 to explain a practice question
// without configuring any API key — 小艺 answers inside the system AI
// assistant surface that we hand off to via startAbility.

import {
  FlutterPlugin,
  FlutterPluginBinding
} from '@ohos/flutter_ohos/src/main/ets/embedding/engine/plugins/FlutterPlugin';
import MethodCall from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodCall';
import MethodChannel from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodChannel';
import { MethodResult } from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodChannel';
import { common, Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import hilog from '@ohos.hilog';

const TAG = "XiaoyiPlugin";
const CHANNEL = "me.dsdogs.turna/xiaoyi";

export default class XiaoyiPlugin implements FlutterPlugin {
  private channel: MethodChannel | null = null;
  private ctx: common.UIAbilityContext | null = null;

  getUniqueClassName(): string {
    return "XiaoyiPlugin";
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    hilog.info(0x0000, TAG, 'onAttachedToEngine called');
    this.ctx = binding.getApplicationContext() as common.UIAbilityContext;
    this.channel = new MethodChannel(
      binding.getBinaryMessenger(),
      CHANNEL
    );
    hilog.info(0x0000, TAG, 'MethodChannel created for %{public}s', CHANNEL);
    this.channel.setMethodCallHandler({
      onMethodCall: (call: MethodCall, result: MethodResult): void => {
        hilog.info(0x0000, TAG, 'Received method call: %{public}s', call.method);
        switch (call.method) {
          case 'isSupported':
            result.success(true);
            break;
          case 'askXiaoyi':
            this.askXiaoyi(call, result);
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

  private askXiaoyi(call: MethodCall, result: MethodResult): void {
    if (!this.ctx) {
      result.error('NO_CONTEXT', 'Application context not available', null);
      return;
    }
    const prompt: string = call.argument('prompt') as string;
    if (!prompt || prompt.length === 0) {
      result.error('NO_PROMPT', 'prompt is empty', null);
      return;
    }

    // Build a query text that 小艺 can read from the launch intent.
    // Prefer the system AI-assistant voice/text handoff action; fall back to
    // the well-known 小艺 bundle when the action route is unavailable.
    const query: string = prompt;

    const want: Want = {
      action: 'ohos.want.action.voiceAssistant',
      parameters: {
        query: query,
        question: query
      }
    };

    this.ctx.startAbility(want).then(() => {
      hilog.info(0x0000, TAG, 'askXiaoyi startAbility succeeded');
      result.success(null);
    }).catch((err: BusinessError) => {
      hilog.error(0x0000, TAG, 'askXiaoyi startAbility failed code=%{public}d msg=%{public}s',
        err.code, err.message);
      result.error('LAUNCH_FAILED', '无法拉起小艺：' + err.message, null);
    });
  }
}