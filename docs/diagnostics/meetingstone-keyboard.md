# MeetingStone 键盘保护调用诊断 · 2026-10-03

## 已知事实

用户日志：ADDON_ACTION_BLOCKED，插件 MeetingStone，Frame:SetPropagateKeyboardInput()；调用点 Libs/NetEaseGUI-2.0/Widget/AutoHideController.lua:26。

本机文件 SHA256：f9fe58da74c8ad5c66826909ca13a0a4018f941320ec5d3f826962d40b3fe55c。只读核对，无修改集合石或其他插件、无读取账号配置。

该文件 OnKeyDown 在结尾无条件调用 SetPropagateKeyboardInput(not found)，没有战斗判断；普通键也会经过这里，不仅是 Esc。工具箱运行代码未找到此接口调用或对 MeetingStone 的挂钩。

## 独立回放

从仓库根执行（需要 lupa）：

~~~powershell
python -X utf8 tests/diagnostics/replay_meetingstone_keyboard.py "E:/World of Warcraft/_retail_/Interface/AddOns/MeetingStone/Libs/NetEaseGUI-2.0/Widget/AutoHideController.lua"
# 原文件：非战斗 A/Escape PASS，模拟战斗 A/Escape FAIL，退出码 1。

python -X utf8 tests/diagnostics/replay_meetingstone_keyboard.py "E:/World of Warcraft/_retail_/Interface/AddOns/MeetingStone/Libs/NetEaseGUI-2.0/Widget/AutoHideController.lua" --guard-candidate
# 仅内存加入 not InCombatLockdown() 判断：四项 PASS，退出码 0。
~~~

夹具执行安装文件的真实回调，控制器列表为空，不加载工具箱；只模拟“战斗中该 setter 被保护”的约束。每次只改变此调用的战斗判断，没有把候选补丁写回任何插件。

## 假设与结论边界

1. 优先：缺少战斗判断使键盘回调触发保护调用。候选判断在模拟条件下消除了该路径。
2. 次优：必须有可见菜单且按 Esc 才会触发。空列表、普通 A 键同样调用 setter，不支持“只有 Esc”这个限定。
3. 次优：必须加载工具箱才能到此调用点。独立重放不加载工具箱即可走到该行，不支持这个必要条件。

**未还原游戏引擎、实际战斗状态与完整 taint 污染链**，不能据此绝对排除插件交互，也不能声称集合石现场已修复。内存候选只验证这一行，不验证战斗中 Esc 吞键、菜单显隐、同库多副本加载等行为。

建议先更新集合石；若仍复现，在清空旧错误并重新登录后，分别测试仅集合石＋错误收集器和加工具箱的组合，记录战斗状态、按键与集合石菜单是否打开。未默认植入跨插件补丁，也未屏蔽 BugGrabber。工具箱 1.9.12 的三行开关和 Switch 改动不是对此第三方报错的修复。
