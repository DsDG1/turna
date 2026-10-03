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
import { util } from '@kit.ArkTS';
import hilog from '@ohos.hilog';

const TAG = "RdbPlugin";
const CHANNEL = "me.dsdogs.turna/rdb";
const DOMAIN = 0xA700;

export default class RdbPlugin implements FlutterPlugin {
  private channel: MethodChannel | null = null;
  private store: relationalStore.RdbStore | null = null;
  private ctx: common.UIAbilityContext | null = null;
  // Depth of open transactions, so begin/commit/rollback stay balanced when
  // drift nests a `transaction()` inside another one. ArkData has no nested
  // transaction, so an inner begin is a no-op and the outermost commit is the
  // one that actually commits.
  private txDepth: number = 0;

  getUniqueClassName(): string {
    return "RdbPlugin";
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    hilog.info(DOMAIN, TAG, 'onAttachedToEngine called');
    this.ctx = binding.getApplicationContext() as common.UIAbilityContext;
    this.channel = new MethodChannel(
      binding.getBinaryMessenger(),
      CHANNEL
    );
    hilog.info(DOMAIN, TAG, 'MethodChannel created for %{public}s', CHANNEL);
    this.channel.setMethodCallHandler({
      onMethodCall: (call: MethodCall, result: MethodResult): void => {
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
          case 'beginTransaction':
            this.beginTransaction(result);
            break;
          case 'commit':
            this.commit(result);
            break;
          case 'rollback':
            this.rollback(result);
            break;
          case 'close':
            this.closeDb(result);
            break;
          default:
            hilog.warn(DOMAIN, TAG, 'Unknown method: %{public}s', call.method);
            result.notImplemented();
        }
      }
    });
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    this.closeDbSync();
    this.channel?.setMethodCallHandler(null);
    this.channel = null;
    this.ctx = null;
  }

  private openDb(call: MethodCall, result: MethodResult): void {
    if (!this.ctx) {
      hilog.error(DOMAIN, TAG, 'Context is null');
      result.error('NO_CONTEXT', 'Application context not available', null);
      return;
    }
    const name: string = call.argument('name') as string ?? 'course.db';
    hilog.info(DOMAIN, TAG, 'Opening database: %{public}s', name);
    // No foreign-key switch here. ArkData's StoreConfig has none, and the only
    // route was `PRAGMA foreign_keys`, which this engine accepts on write but
    // never answers on read: a `querySql` for a PRAGMA returns a ResultSet
    // whose `getColumnNames()` never returns, so the Dart side waited forever
    // and the app opened to a blank screen. Enabling it blind is worse than
    // leaving it off, because a `executeSql` that also hangs would wedge every
    // later write. The course tree's `ON DELETE CASCADE` therefore does not
    // fire on OHOS; see ADR 0047 for the recorded consequence.
    const config: relationalStore.StoreConfig = {
      name: name,
      securityLevel: relationalStore.SecurityLevel.S1,
    };
    relationalStore.getRdbStore(this.ctx, config)
      .then((store: relationalStore.RdbStore) => {
        this.store = store;
        hilog.info(DOMAIN, TAG, 'Database opened successfully');
        result.success(true);
      })
      .catch((err: Error) => {
        hilog.error(DOMAIN, TAG, 'Failed to open database: %{public}s', err.message);
        result.error('DB_OPEN_ERROR', `open failed: ${err.message}`, null);
      });
  }

  private executeSql(call: MethodCall, result: MethodResult): void {
    if (!this.store) {
      result.error('DB_NOT_OPEN', 'database not open', null);
      return;
    }
    const sql: string = call.argument('sql') as string;
    const params: Array<ESObject> = call.argument('params') as Array<ESObject>;

    this.store.executeSql(sql, params ?? [])
      .then(() => {
        result.success(true);
      })      .catch((err: Error) => {
        // Surface the statement text and the engine's own message. drift wraps
        // this in its own exception, but a silent `true` here is how a failed
        // migration would look like success.
        hilog.error(DOMAIN, TAG, 'executeSql error: %{public}s | sql=%{public}s',
          err.message, sql);
        result.error('EXECUTE_ERROR', `${err.message} | sql: ${sql}`, null);
      });
  }

  private query(call: MethodCall, result: MethodResult): void {
    if (!this.store) {
      result.error('DB_NOT_OPEN', 'database not open', null);
      return;
    }
    const sql: string = call.argument('sql') as string;
    const params: Array<ESObject> = call.argument('params') as Array<ESObject>;

    this.store.querySql(sql, params ?? [])
      .then((rs: relationalStore.ResultSet): void => {
        // Not `getColumnNames()`. On this engine that accessor never returns:
        // `querySql` resolves, the ResultSet arrives, and the call blocks with
        // the event loop still servicing later messages, so the reply to Dart
        // is never sent and the open hangs to a white screen. Confirmed on
        // device (HarmonyOS 7.0.0, API 26) — the last log line before the stall
        // was always this statement, and no reply followed. `columnCount` plus
        // `getColumnName(i)` are the plain per-column accessors and answer.
        const count: number = rs.columnCount;
        if (count === 0) {
          rs.close();
          result.success({ types: {}, rows: [] });
          return;
        }
        const colNames: Array<string> = [];
        for (let i: number = 0; i < count; i++) {
          colNames.push(rs.getColumnName(i));
        }

        // The declared type of every column, so the Dart side can coerce each
        // value the way sqlite3 would. Without it a REAL column holding 2.0
        // crosses the channel as a Dart `int` and drift rejects the row.
        //
        // Read on the first row, not before the loop: these accessors report
        // per-column state for the row the cursor is on, and calling them with
        // no current row never returns — which is what stalled the first query
        // that had any columns at all.
        const types: ESObject = {};
        let typesRead = false;
        const rows: Array<ESObject> = [];
        while (rs.goToNextRow()) {
          if (!typesRead) {
            for (let i: number = 0; i < count; i++) {
              types[colNames[i]] = this.typeNameOf(rs, i);
            }
            typesRead = true;
          }
          const row: ESObject = {};
          for (let i: number = 0; i < count; i++) {
            row[colNames[i]] = this.readColumn(rs, i);
          }
          rows.push(row);
        }
        rs.close();
        result.success({ types: types, rows: rows });
      })
      .catch((err: Error) => {
        hilog.error(DOMAIN, TAG, 'query error: %{public}s | sql=%{public}s',
          err.message, sql);
        result.error('QUERY_ERROR', `${err.message} | sql: ${sql}`, null);
      });
  }

  /**
   * The declared type of a column, as a name that survives the channel.
   *
   * `NULL` is reported as such: a column whose declared type is NULL has no
   * value to convert, and letting the Dart side fall back to a guess is what
   * produced the original string-for-integer bug.
   */
  private typeNameOf(rs: relationalStore.ResultSet, index: number): string {
    const type: number = rs.getColumnTypeSync(index);
    switch (type) {
      case relationalStore.ColumnType.INTEGER:
        return 'integer';
      case relationalStore.ColumnType.REAL:
        return 'real';
      case relationalStore.ColumnType.TEXT:
        return 'text';
      case relationalStore.ColumnType.BLOB:
        return 'blob';
      case relationalStore.ColumnType.UNLIMITED_INT:
        // 64-bit values beyond 2^53 lose precision as a JS number, so they
        // travel as text and the Dart side parses them.
        return 'integer64';
      default:
        return 'text';
    }
  }

  /**
   * Reads one cell with the accessor matching the column's declared type.
   *
   * The accessors are not interchangeable: `getString` on a non-TEXT column
   * throws or coerces depending on the implementation, and the SDK documents
   * that as "the implementation class decides". Trial-and-error ordering
   * therefore silently turns INTEGER columns into strings. `getColumnTypeSync`
   * reports the declared type, so the right accessor is chosen up front.
   */
  private readColumn(rs: relationalStore.ResultSet, index: number): ESObject {
    if (rs.isColumnNull(index)) {
      return null;
    }
    const name: string = this.typeNameOf(rs, index);
    switch (name) {
      case 'integer':
        return rs.getLong(index);
      case 'real':
        // Still a JS number; the Dart side coerces using the reported type.
        return rs.getDouble(index);
      case 'blob':
        // Uint8Array has no direct MethodChannel mapping, so hand it over
        // base64-encoded and let the Dart executor decode.
        return this.toBase64(rs.getBlob(index));
      case 'integer64':
        return rs.getString(index);
      default:
        return rs.getString(index);
    }
  }

  private toBase64(bytes: Uint8Array): string {
    if (!bytes || bytes.length === 0) {
      return '';
    }
    const encoder: util.Base64Helper = new util.Base64Helper();
    return encoder.encodeToStringSync(bytes);
  }

  private beginTransaction(result: MethodResult): void {
    if (!this.store) {
      result.error('DB_NOT_OPEN', 'database not open', null);
      return;
    }
    try {
      if (this.txDepth === 0) {
        this.store.beginTransaction();
      }
      this.txDepth++;
      result.success(true);
    } catch (err) {
      const e = err as Error;
      result.error('TX_BEGIN_ERROR', e.message ?? 'beginTransaction failed', null);
    }
  }

  private commit(result: MethodResult): void {
    if (!this.store) {
      result.error('DB_NOT_OPEN', 'database not open', null);
      return;
    }
    try {
      if (this.txDepth === 1) {
        this.store.commit();
      }
      if (this.txDepth > 0) {
        this.txDepth--;
      }
      result.success(true);
    } catch (err) {
      const e = err as Error;
      result.error('TX_COMMIT_ERROR', e.message ?? 'commit failed', null);
    }
  }

  private rollback(result: MethodResult): void {
    if (!this.store) {
      result.error('DB_NOT_OPEN', 'database not open', null);
      return;
    }
    try {
      if (this.txDepth === 1) {
        this.store.rollBack();
      }
      if (this.txDepth > 0) {
        this.txDepth--;
      }
      result.success(true);
    } catch (err) {
      const e = err as Error;
      result.error('TX_ROLLBACK_ERROR', e.message ?? 'rollBack failed', null);
    }
  }

  private closeDb(result: MethodResult): void {
    this.closeDbSync();
    result.success(true);
  }

  private closeDbSync(): void {
    if (this.store) {
      try {
        if (this.txDepth > 0) {
          this.store.rollBack();
        }
      } catch (e) {
        // An open transaction is about to be discarded with the store; a
        // failure to roll back here must not block closing.
      }
      this.txDepth = 0;
      try {
        this.store.close();
      } catch (e) {
        // Already closed, or the handle is gone with the sandbox.
      }
      this.store = null;
    }
  }
}
