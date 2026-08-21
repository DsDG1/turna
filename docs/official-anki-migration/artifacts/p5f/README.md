# P5-F 施工回执归档

每档灰度放行后在此归档（P4R3 device-receipt 模式：命令 + 输出 + 截图，hash 钉死）：

- `internal-dartdefine.txt` — 内部通道（dart-define 手动开 flag）验证：导入→复习→卸载全流程
- `device-gray-g1.txt` / `.png` — 1% 灰度真机回执
- `device-gray-g4.txt` / `.png` — 100% 灰度真机回执
- `rollback-drill.txt` — flag 关闭回退演练（回旧序 + deleteProjection 清投影）

已完成的 Host 侧施工验证（2026-08-22，工作区）：
- `flutter test --exclude-tags golden` → 1299 passed / 0 failed
- `dart analyze`（改动文件）→ 0 新增 issue
