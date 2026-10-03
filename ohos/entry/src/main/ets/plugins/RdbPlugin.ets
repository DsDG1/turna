// Copyright (c) 2024 Turna. All rights reserved.
// Bridges HarmonyOS native RDB (@kit.ArkData relationalStore) to Flutter drift
// via MethodChannel, enabling full course database functionality on HarmonyOS.

import {
  FlutterPlugin,
  FlutterPluginBinding
} from '@ohos/flutter_ohos/src/main/ets/embedding/engine/plugins/FlutterPlugin';
import MethodCall from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodCall';
import MethodChannel from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodChannel';
import { MethodResult } from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodChannel';
import Any from '@ohos/flutter_ohos/src/main/ets/plugin/common/Any';
import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import hilog from '@ohos.hilog';

const TAG = "RdbPlugin";
const CHANNEL = "me.dsdogs.turna/rdb";

export default class RdbPlugin implements FlutterPlugin {
  private channel: MethodChannel | null = null;
  private store: relationalStore.RdbStore | null = null;
  private ctx: common.UIAbilityContext | null = null;

  getUniqueClassName(): string {
    return "RdbPlugin";
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
          case 'openDb':
            this.openDb(call, result);
            break;
          case 'executeSql':
            this.executeSql(call, result);
            break;
          case 'query':
            this.query(call, result);
            break;
          case 'close':
            this.closeDb(result);
            break;
          default:
            hilog.warn(0x0000, TAG, 'Unknown method: %{public}s', call.method);
            result.notImplemented();
        }
      }
    });
    hilog.info(0x0000, TAG, 'MethodCallHandler set');
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    this.closeDbSync();
    this.channel?.setMethodCallHandler(null);
    this.channel = null;
    this.ctx = null;
  }

  private openDb(call: MethodCall, result: MethodResult): void {
    hilog.info(0x0000, TAG, 'openDb called with args: %{public}s', JSON.stringify(call.args));
    if (!this.ctx) {
      hilog.error(0x0000, TAG, 'Context is null');
      result.error('NO_CONTEXT', 'Application context not available', null);
      return;
    }
    const name: string = call.args as string ?? 'course.db';
    hilog.info(0x0000, TAG, 'Opening database: %{public}s', name);
    const config: relationalStore.StoreConfig = {
      name: name,
      securityLevel: relationalStore.SecurityLevel.S1,
    };
    relationalStore.getRdbStore(this.ctx, config)
      .then((store: relationalStore.RdbStore) => {
        hilog.info(0x0000, TAG, 'Database opened successfully');
        this.store = store;
        result.success(true);
      })
      .catch((err: Error) => {
        hilog.error(0x0000, TAG, 'Failed to open database: %{public}s', err.message);
        result.error('DB_OPEN_ERROR', `打开数据库失败: ${err.message}`, null);
      });
  }

  private executeSql(call: MethodCall, result: MethodResult): void {
    if (!this.store) {
      result.error('DB_NOT_OPEN', '数据库未打开', null);
      return;
    }
    let sql: string = call.argument('sql') as string;
    let params: Array<ESObject> = call.argument('params') as Array<ESObject>;
    hilog.info(0x0000, TAG, 'executeSql: %{public}s', sql);
    hilog.info(0x0000, TAG, 'executeSql params: %{public}s', JSON.stringify(params));

    // HarmonyOS RDB has issues with ON CONFLICT DO UPDATE syntax.
    // Rewrite to INSERT OR REPLACE for simple cases.
    const conflictMatch = sql.match(/^INSERT INTO "(\w+)" \(([^)]+)\) VALUES \((\?(, \?)+)\) ON CONFLICT\("\w+"\) DO UPDATE SET .+$/i);
    if (conflictMatch) {
      const tableName = conflictMatch[1];
      const columns = conflictMatch[2];
      const values = conflictMatch[3];
      sql = `INSERT OR REPLACE INTO "${tableName}" (${columns}) VALUES (${values})`;
      // Only keep the parameters for the VALUES clause
      const valueCount = (values.match(/\?/g) || []).length;
      params = params.slice(0, valueCount);
      hilog.info(0x0000, TAG, 'Rewrote SQL to: %{public}s with %{public}d params', sql, params.length);
    }

    this.store.executeSql(sql, params ?? [])
      .then(() => {
        hilog.info(0x0000, TAG, 'executeSql success');
        result.success(true);
      })
      .catch((err: Error) => {
        hilog.error(0x0000, TAG, 'executeSql error: %{public}s', err.message);
        result.error('EXECUTE_ERROR', `执行SQL失败: ${err.message}`, null);
      });
  }

  private query(call: MethodCall, result: MethodResult): void {
    if (!this.store) {
      result.error('DB_NOT_OPEN', '数据库未打开', null);
      return;
    }
    const sql: string = call.argument('sql') as string;
    const params: Array<ESObject> = call.argument('params') as Array<ESObject>;
    hilog.info(0x0000, TAG, 'query: %{public}s', sql);
    this.store.querySql(sql, params ?? [])
      .then((rs: relationalStore.ResultSet) => {
        // Check if the ResultSet is valid - if table doesn't exist,
        // HarmonyOS RDB returns a ResultSet with 0 columns instead of throwing
        const colNames: Array<string> = rs.getColumnNames();
        if (colNames.length === 0) {
          rs.close();
          throw new Error(`Query returned no columns - table may not exist: ${sql}`);
        }
        const rows: Array<ESObject> = [];
        while (rs.goToNextRow()) {
          const row: ESObject = {};
          const colNames: Array<string> = rs.getColumnNames();
          for (let i: number = 0; i < rs.columnCount; i++) {
            const colName: string = colNames[i];
            let value: ESObject = null;
            try {
              const strVal: string | null = rs.getString(i);
              if (strVal !== null && strVal !== undefined) {
                value = strVal;
              }
            } catch (e) {
              // not a string
            }
            if (value === null) {
              try {
                const longVal: number | null = rs.getLong(i);
                if (longVal !== null && longVal !== undefined) {
                  value = longVal;
                }
              } catch (e) {
                // not a long
              }
            }
            if (value === null) {
              try {
                const doubleVal: number | null = rs.getDouble(i);
                if (doubleVal !== null && doubleVal !== undefined) {
                  value = doubleVal;
                }
              } catch (e) {
                // not a double
              }
            }
            row[colName] = value;
          }
          rows.push(row);
        }
        rs.close();
        hilog.info(0x0000, TAG, 'query returned %{public}d rows', rows.length);
        result.success(rows);
      })
      .catch((err: Error) => {
        hilog.error(0x0000, TAG, 'query error: %{public}s', err.message);
        result.error('QUERY_ERROR', `查询失败: ${err.message}`, null);
      });
  }

  private closeDb(result: MethodResult): void {
    this.closeDbSync();
    result.success(true);
  }

  private closeDbSync(): void {
    if (this.store) {
      try {
        this.store.close();
      } catch (e) {
        // ignore close errors
      }
      this.store = null;
    }
  }
}
