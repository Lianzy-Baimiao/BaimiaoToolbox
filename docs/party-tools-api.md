# 团队工具 API 核对（Retail live）

- 核对日期：2026-10-02；在线读取 Gethe/wow-ui-source 的 `live` 分支指针，确认为 `09b9db7948abc9b9648dedaab51eb0cf3ee67b31`；固定提交的 `version.txt` 为 **12.1.0.69933**。[live 分支指针][live] [版本][version]
- 范围：目标 8 标＋清当前目标；世界标 8 个＋清全部；就位；5／10 秒原生倒数及取消；无信号/ping。MRT MarksBar 只作为交互参考，不复制实现。
- 方法：核对固定提交的 Blizzard UI 源码镜像与本地 MRT MarksBar 交互。本文记录 API 依据与不确定边界，不表示已经进行游戏内实测。
- **证据分级**：**明确**＝固定提交的 API 声明或 Blizzard UI 代码直接可见；**推导/建议**＝据这些代码提出的实现选择；**待验证**＝公开 Lua/API 声明不能证明的引擎、服务器或受污染插件调用行为。Gethe 是 Blizzard 客户端 UI 源码镜像，不包含客户端 C++/服务器实现；“HasRestrictions”本身不提供完整限制清单。[API 声明][party]

## 1. 原生团队倒数：必须使用 DoCountdown

### 明确证据

1. 当前 API 是 `success = C_PartyInfo.DoCountdown(seconds)`：`seconds` 是必填 number，返回 bool；声明带 `HasRestrictions = true` 与 `SecretArguments = "AllowedWhenUntainted"`。[API][party]
2. 团队管理倒数按钮 `RaidFrameCountdownMixin:OnClick` 直接调用 `C_PartyInfo.DoCountdown(10)`。因此“与团队管理一致”的准确入口就是它，而不是逐秒发文字。这里的“团队管理通道”是官方组队倒数机制，不是一个要传给 SendChatMessage 的频道名；该 API 只接收秒数，不接收 RAID / RAID_WARNING / INSTANCE_CHAT 等 chatType。[团队管理点击][managerClick] [签名][party]
3. 官方倒数按钮显示条件为 `isLeader or (isRaid and isAssist)`，启用条件为 `(isLeader or isAssist) and isInGroup`；就位确认采用同样显示、启用条件。其含义是：界面入口给队长、团长和团队助理，且必须在组内。**这是官方 UI 的权限门槛，不是 C++ 权限矩阵的完整证明。**[权限门槛][manager]
4. 原生倒数命令把数字传给 `DoCountdown`，并检查不超过 `Constants.PartyCountdownConstants.MaxCountdownSeconds`；该值在此提交为 **3600**。命令代码没有显式下界校验，不能由此推断所有负数、小数都合法。[命令][countdownSlash] [常量][constant]
5. Blizzard `TimerTracker` 处理 `START_PLAYER_COUNTDOWN` / `CANCEL_PLAYER_COUNTDOWN`，使用 `Enum.StartTimerType.PlayerCountdown`；取消事件把本地计时器时间设为 0。其聊天提示通过 `DisplaySystemMessageInPrimary` 显示系统消息，不是向 `RAID_WARNING` 频道发送逐秒广播。[原生计时及提示][timer]

### 取消参数：0 是应验证的接入值，不把推导写成已实测契约

- **拟采用 `C_PartyInfo.DoCountdown(0)` 取消。**一手支持链：官方命令允许数字 0 进入该 API；取消事件的官方表现使用 `0, 0` 清理倒数。[命令][countdownSlash] [取消事件][timer]
- **证据缺口**：本次核对的 DoCountdown 声明没有写“seconds=0 cancels”，团队管理按钮仅有 `DoCountdown(10)`，取消事件内部的 0 并不等于 C++ 入参契约。因此必须在客户端确认 `DoCountdown(0)` 的返回值及全组取消效果；在验证前不能标“源码明确证实取消参数”。也没有本次一手证据支持用 `nil`、`-1` 替代 0。[API][party] [团队管理点击][managerClick]
- **待验证**：谁能取消其他人发起的倒数、无活动倒数时返回值、重复点击是否覆盖、超短倒数及小数的处理。不要把本地隐藏计时器当成取消了全组倒数。[返回值及参数声明][party]

### 战斗、secret、chat_lockdown：必须分开

| 维度 | 明确证据 | 接入限制 / 未决项 |
| --- | --- | --- |
| 通用 API 限制 | DoCountdown 标记 `HasRestrictions = true`。[party] | **不能**仅凭这一字段断言它是“只能硬件点击”“战斗外专用”或“完全受保护”；也不能据普通 OnClick 就断言插件在所有状态都可调用。需客户端验证。 |
| secret 参数 | `SecretArguments = "AllowedWhenUntainted"`。[party] | 插件应传来自静态配置/用户输入的普通秒数，不接收秘密战斗值。不得假设 pcall、securecall 或安全按钮能洗掉参数 taint/secret。 |
| 聊天锁定查询 | `C_ChatInfo.InChatMessagingLockdown()` 返回聊天 API 安全限制是否生效。[chat] | 与 `InCombatLockdown()` 不是同名同义状态；没有证据可将两者直接等同。 |
| 聊天相关 secret 范围 | `SecretInChatMessagingLockdown` 描述涉及 encounter、challenge mode、PvP match 限制及 dungeon/raid 等通信受限地图。[secret] | 精确状态组合应由客户端查询，不自行把它缩减为“正在打怪”。 |
| DoCountdown 是否受 chat_lockdown 拒绝 | 其声明只有上述通用限制和 secret 参数标记，**没有列出具体 chat_lockdown 条件**。[party] | **待客户端验证**。缺少明确标记不等于允许；此报告不声称查到了其完整引擎限制表，也不凭该标记推断其返回值是 secret。 |
| 遭遇开始自动取消 | Timer.lua 有 `COUNTDOWN_CANCEL_ENCOUNTER_START` 提示分支。[timer] | 表明官方 UI 支持这一取消情形；不等于“所有战斗都会自动取消”或“战斗中调用一定成功/一定失败”。 |

**实现建议（非引擎事实）**：与官方入口一样要求在组内且玩家为 leader/assistant；以用户点击调用，秒数取普通正整数并限制在产品设定及 3600 以内，保留取消值 0；处理 `success == false`。在客户端复核前可保守禁用战斗中、聊天锁定期间的新倒数并给出原因，但应标为本插件策略，而非宣称已证实的 API 定律。失败时不偷偷改发聊天、不调用其他插件的 /pull 作为回退。[party] [manager] [constant] [chat]

## 2. 与 RAID_WARNING、/pull 的区别

| 途径 | 一手事实 | 对本功能的结论 |
| --- | --- | --- |
| `C_PartyInfo.DoCountdown` | 官方团队管理直接调用；原生 TimerTracker 响应玩家倒数开始/取消事件。[managerClick] [timer] | 是本次要求的倒数，不需要把其模拟为一串聊天消息。 |
| `RAID_WARNING` | RaidWarningFrame 接收 `CHAT_MSG_RAID_WARNING`，显示传入文本并播放警告音。[warning] | 文字“10、9、8”仍是聊天警告，不是原生玩家倒数。发聊 API 自有 `HasRestrictions`、`RestrictedForMacroChatMessages`、secret 参数约束，不能当作倒数失败时的无条件通道。[chatSend] |
| 插件消息广播 | `C_ChatInfo.SendAddonMessage` 把指定前缀的 payload 发给注册该前缀的其他客户端，且 `SecretArguments = "NotAllowed"`。[chatSend] | 这是插件协议通道，不等于官方玩家倒数，也不能广播 secret。是否显示、如何同步取决于接收插件。 |
| `/pull` | 当前 DBM 自己注册该命令，转至 `DBM:CreatePullTimer`；当前实现最终直接调用 `C_PartyInfo.DoCountdown(timer)`。[dbmCommands] [dbmTimers] | **不能笼统写“/pull 只是插件广播”**。它是插件拥有的命令，具体行为由版本和插件决定；当前 DBM 已包装原生倒数。本插件仍应直接调用官方 API，不依赖 DBM/BW 是否安装、命令占用或插件私有前置条件。 |

补充：本次固定核对的 DBM 提交为 `61a104843db8c0fe6ee0383327d2ef44e001ccbd`。其 CreatePullTimer 有 LFG 坦克例外、PvP/战斗/遭遇门槛及 0<秒数<3 的拒绝条件；这些是 **DBM 的实现规则，不可冒充 Blizzard API 权限说明**。DBM 的 break timer 路径则使用自己的同步消息；不应将其与 pull 路径混写。[dbmTimers] [dbmBreak]

## 3. 地面标记：SecureActionButtonTemplate 支持 set / clear

### 已确认的安全动作

- 模板继承 `SecureFrameTemplate`，并使用 `SecureActionButton_OnClick`；不要用普通 OnClick 覆盖这个处理器。源码另外明确将 `InsecureActionButtonTemplate` 限定在 `not InCombatLockdown()` 时执行安全动作，两种模板不是等价替代品。[template]
- `SECURE_ACTIONS.worldmarker` 读取 `marker` 和修改键/鼠标键对应的 `action`；`set` 调 `PlaceRaidMarker(marker or 1)`；`clear` 调 `ClearRaidMarker(marker)`；默认 `toggle` 会读取 `IsRaidMarkerActive` 决定设置或清除。[secure]
- `LeftButton` 映射后缀 1，`RightButton` 映射后缀 2；源码说明了 `action1`、`shift-action2` 等属性以及通配符。因此 **`type="worldmarker"` + `action1="set"` + `action2="clear"` 有直接支持**，无需伪造宏或模拟点击。[modified] [suffix]

**接入建议（非运行代码）**：战斗外创建 `SecureActionButtonTemplate`；为每个按钮配置 `type="worldmarker"`、普通数字 `marker`、`action1="set"`、`action2="clear"`；注册 `AnyDown` 和 `AnyUp`。

注册按下/抬起的理由：当前安全点击代码依据 `useOnKeyDown` 或 `ActionButtonUseKeyDown` 选择执行阶段；只注册一个不匹配阶段可能看似“按钮不工作”。不要手工再执行第二遍设置/清除。[click]

### 清全部的合法表达：不填 marker，而不是臆造索引

1. **明确**：官方团队管理清全部地面标记调用 `ClearRaidMarker()`；官方清标记命令在 ALL 分支调用 `ClearRaidMarker(nil)`，注释明写 `Clear all world markers`。[worldClear] [clearSlash]
2. **源码推导出的安全按钮方式**：独立 `worldmarker` 按钮，`action="clear"`，**不设置 marker 属性**。安全动作读取到 nil 后正好传入官方清全部形式。确保没有 `marker1`、`*marker*` 或启用属性继承导致其取到单个标记值。[secure] [suffix]
3. **不要用 `marker=0`、9 或 MAX_RAID_MARKERS 当作已证实的清全部哨兵。**生成文档虽写该参数默认值为 MAX_RAID_MARKERS，并标 `Nilable=false`，但官方调用点明确使用省略参数/nil。应遵循实际调用证据，而不是根据默认值自行猜数值意义。[markers] [worldClear] [clearSlash]
4. 地面标记清全部与单位标记清全部不是同一个 API：当前 `RemoveRaidTargets()` 的文档明确说明“Removes all assigned raid target markers”；官方单位标记重置按钮也调用它。[markers] [worldClear]

### 安全、权限和 secret 边界

- `PlaceRaidMarker` / `ClearRaidMarker` 均有 `HasRestrictions` 和 `AllowedWhenUntainted`；安全按钮选择正确执行路径，**不代表赋予无权限玩家标记权限**。官方共用标记面板门槛为“非团队，或团长／助理”；单人、随机队列及目标地图的最终引擎限制仍需客户端验证。[markers] [secure] [markerPermission]
- **战斗外完成创建、属性、布局和显示策略配置**；战斗中不要从普通插件代码改安全按钮属性、移动/重排或随意隐藏其受保护层级。Show/Hide/StartMoving 等具有受保护函数声明；受保护对象是否允许调用由调用上下文决定。具体父子保护传播/布局方案仍须客户端验收。[template] [frames] [frameRestriction]
- `IsRaidMarkerActive` 明确标记 `SecretInChatMessagingLockdown = true`。不要在不安全 Lua 中根据该结果分支决定 `set/clear`，也不要把它拿去构造聊天消息。本交互使用明确的左 set / 右 clear，不需要插件先读活动状态。[markers] [secure] [secret]
- 同样，不应将 Blizzard 无污染 UI 中可见的直接 PlaceRaidMarker 调用机械复制为插件普通 OnClick，并据此宣布战斗可用；模板执行路径和插件受污染调用路径的结果要分别验证。[worldClear] [template]

## 4. SetRaidTarget 与 DoReadyCheck

### 单位目标标记

- `SetRaidTarget(target, userIndex)` 是当前全局 API；带 `HasRestrictions` 和 `AllowedWhenUntainted`。官方按钮设置指定索引，右键/移除按钮用 `SetRaidTarget("target", 0)` 清当前目标标记。[markers] [worldClear]
- **官方 UI 权限门槛可证实**：标记面板只在 `not isRaid or isLeaderOrAssist` 时显示，即小队不要求队长，团队要求团长／助理；目标按钮再以 `CanBeRaidTarget("target")` 检查可标记性。不要把倒数／就位的 leader/assistant 条件一刀切用于小队标记，也不能由面板可见推断所有目标及特殊队列都获授权；客户端／服务器仍做最终判定。[标记面板权限][markerPermission] [targetEnable] [markers]
- **现代接入优先使用安全目标标记动作**：当前 `SECURE_ACTIONS.raidtarget` 明确支持 `action="set"`、`"clear"`、`"clear-all"`。目标 8 标按钮采用 `type="raidtarget"`、`unit="target"`、固定 marker、左键 set／右键 clear；独立清当前目标按钮用 clear。不要在插件普通 OnClick 里直接调用 SetRaidTarget 并假定战斗可用；内置安全动作中的 secret 比较应留在官方安全执行链。[安全目标标记动作][secureTarget]
- `GetRaidTargetIndex` 标记 `SecretReturns = true`。不要直接复制官方 `SetRaidTargetIcon` 的读取后比较/toggle 实现到插件受污染路径；明确左键设置索引、右键清除 0 可避免这一不必要的 secret 分支。是否需要高亮当前图标，应单独设计安全的数据展示，而不是直接 if/比较 secret 返回值。[markers] [targetToggle]
- 清“当前目标”用索引 0；清“所有单位标记”是 `RemoveRaidTargets()`；清“全部地面标记”是 `ClearRaidMarker()`。三者不可混为一谈。[worldClear] [markers]

### 就位确认

- 使用 `C_PartyInfo.DoReadyCheck()`；生成声明无参数、无声明返回值，带 `HasRestrictions = true`。旧全局 `DoReadyCheck()` 仍是转调该命名空间函数的兼容包装，新功能无需依赖旧名称。[party] [兼容包装][deprecatedReady]
- 官方就位命令先检查 `UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")`；团队管理按钮另要求组内，显示为队长或团队助理。可直接采用这个 UI 门槛，但其服务器权限、节流、战斗/chat lockdown 拒绝方式仍须实测。[readySlash] [manager]
- `READY_CHECK` 事件明确有 `SecretInChatMessagingLockdown = true`，负载包括发起者名字和剩余时间。不要将该负载无条件比较、拼接或转发到聊天；“事件负载会 secret”与“发起 API 一定被禁止”是两个不同结论。[readyEvent] [secret]

## 5. 本次确定的实现建议

- 目标 8 标＋清当前目标：使用 `raidtarget` 安全动作；不读取 secret 来自行模拟 toggle。`RemoveRaidTargets()` 仅作为清全部单位标记的 API 区分记录，**不额外扩展当前需求**。[secureTarget] [markers]
- 世界标 8 个＋清全部：使用 `worldmarker` 安全动作，左 set／右 clear；清全部独立按钮不配置任何 marker 值或继承值。世界标与单位标的索引顺序不同，采用官方映射核对，不直接复用图标序号。[secure] [worldClear] [markerOrder]
- 就位、5 秒、10 秒：用户点击后调用命名空间 API。倒数分别传普通常量 5 / 10；与团队管理一样先做组内及 leader/assistant 门槛，处理倒数返回 false。只让官方倒数事件及 UI 负责组内展示，不发送 RAID_WARNING 或插件同步，不包含 ping。[party] [manager] [timer]
- 取消：保留独立操作设计，候选入参 0；**首轮客户端验证通过前，不承诺“取消已支持”**。不能用隐藏本地计时器代替全组取消。[countdownSlash] [timer]
- 战斗限制：倒数（包括取消）和就位先按战斗中不可发起的保守策略实现；chat lockdown 单独判定，不声称官方 API 是绕过通信限制的通道。任何失败均不回退聊天或 /pull。安全标记按钮应战斗外预建，配置／布局更改延后至脱战。[party] [chat] [template]

### 战斗限制的补充线索（不混入已直读的一手事实）

Warcraft Wiki 对 **2026-03-25 暴雪开发者公告**的转录明确列出：DoCountdown、DoReadyCheck 等 API 将不再允许插件在战斗中调用（拟热修 12.0.1）。转录指向 WoWUIDev 的暴雪公告原帖；本次未能直接读取 Discord 原帖正文，因此这是**历史官方公告的二手转录线索**，不是当前 12.1.0 全状态实测或已直读原帖。它支持上述保守禁用战斗操作的建议，但不能据此推出 chat lockdown 的全部规则。当前 live 直接证据仍是 `HasRestrictions` 及官方 UI 调用点。[公告原帖入口，未直读正文][combatOriginal] [实际读取的转录][combatTranscript] [party]

## 6. 交付前的客户端验证清单（未执行）

以下是由上述证据缺口导出的验收项，不是已通过测试的声明：

1. **倒数权限**：单人、普通小队成员/队长、团队普通成员/助理/团长、LFG 坦克分别发起；记录 DoCountdown 的 bool 返回值、错误反馈和其他成员实际显示，不从 DBM 权限例外推断引擎行为。[party] [manager] [dbmTimers]
2. **取消**：发起后调用 `DoCountdown(0)`；确认跨客户端取消、取消别人倒数、无倒数时行为及重复发起覆盖。未通过前，取消功能视为待定，而不是本地隐藏成功即算完成。[countdownSlash] [timer]
3. **限制矩阵**：野外战斗；副本非遭遇战斗；遭遇战；M+ 已开始；PvP；副本脱战。分别记录 InCombatLockdown、InChatMessagingLockdown、API 结果。退出战斗不代表通信限制必定解除。[party] [chat] [secret]
4. **安全按钮**：两种 ActionButtonUseKeyDown 设置、左右键、战斗前后点击、战斗内收到布局/配置变化；不得重设受保护属性，不得双执行。[click] [template] [frames]
5. **标记**：逐个设置/清除地面标记、无 marker 清全部；无目标/不可标记目标、左右键单位标记、RemoveRaidTargets；验证各角色权限及图标索引映射，不能把单位图标顺序直接当作地面标记顺序。[worldClear] [markers]
6. **secret**：chat lockdown 下不对 IsRaidMarkerActive 或 GetRaidTargetIndex 做不安全分支/比较；不处理或转发 READY_CHECK 的秘密负载。[markers] [readyEvent] [secret]
7. **就位确认**：组内权限、正在就位确认时再次点击、战斗/通信受限时点击及受污染错误；不要假定 DoReadyCheck 有 bool 返回值。[party] [readySlash]

## 来源（暴雪源码固定提交；第三方源码仅证明自身行为）

[version]: https://github.com/Gethe/wow-ui-source/blob/09b9db7948abc9b9648dedaab51eb0cf3ee67b31/version.txt
[party]: https://github.com/Gethe/wow-ui-source/blob/09b9db7948abc9b9648dedaab51eb0cf3ee67b31/Interface/AddOns/Blizzard_APIDocumentationGenerated/PartyInfoDocumentation.lua#L155-L175
[manager]: https://github.com/Gethe/wow-ui-source/blob/09b9db7948abc9b9648dedaab51eb0cf3ee67b31/Interface/AddOns/Blizzard_CompactRaidFrames/Mainline/Blizzard_CompactRaidFrameManager.lua#L423-L465
[managerClick]: https://github.com/Gethe/wow-ui-source/blob/09b9db7948abc9b9648dedaab51eb0cf3ee67b31/Interface/AddOns/Blizzard_CompactRaidFrames/Mainline/Blizzard_CompactRaidFrameManager.lua#L1234-L1263
[countdownSlash]: https://github.com/Gethe/wow-ui-source/blob/09b9db7948abc9b9648dedaab51eb0cf3ee67b31/Interface/AddOns/Blizzard_ChatFrameBase/Shared/SlashCommands.lua#L1612-L1618
[timer]: https://github.com/Gethe/wow-ui-source/blob/09b9db7948abc9b9648dedaab51eb0cf3ee67b31/Interface/AddOns/Blizzard_FrameXML/Timer.lua#L92-L196
[constant]: https://github.com/Gethe/wow-ui-source/blob/09b9db7948abc9b9648dedaab51eb0cf3ee67b31/Interface/AddOns/Blizzard_APIDocumentationGenerated/PartyConstantsDocumentation.lua#L50-L57
[secure]: https://github.com/Gethe/wow-ui-source/blob/09b9db7948abc9b9648dedaab51eb0cf3ee67b31/Interface/AddOns/Blizzard_FrameXML/SecureTemplates.lua#L608-L624
[modified]: https://github.com/Gethe/wow-ui-source/blob/09b9db7948abc9b9648dedaab51eb0cf3ee67b31/Interface/AddOns/Blizzard_FrameXML/SecureTemplates.lua#L6-L29
[suffix]: https://github.com/Gethe/wow-ui-source/blob/09b9db7948abc9b9648dedaab51eb0cf3ee67b31/Interface/AddOns/Blizzard_FrameXML/SecureTemplates.lua#L98-L138
[click]: https://github.com/Gethe/wow-ui-source/blob/09b9db7948abc9b9648dedaab51eb0cf3ee67b31/Interface/AddOns/Blizzard_FrameXML/SecureTemplates.lua#L793-L823
[template]: https://github.com/Gethe/wow-ui-source/blob/09b9db7948abc9b9648dedaab51eb0cf3ee67b31/Interface/AddOns/Blizzard_FrameXML/SecureTemplates.xml#L4-L17
[markers]: https://github.com/Gethe/wow-ui-source/blob/09b9db7948abc9b9648dedaab51eb0cf3ee67b31/Interface/AddOns/Blizzard_APIDocumentationGenerated/RaidMarkersDocumentation.lua#L9-L105
[worldClear]: https://github.com/Gethe/wow-ui-source/blob/09b9db7948abc9b9648dedaab51eb0cf3ee67b31/Interface/AddOns/Blizzard_CompactRaidFrames/Mainline/Blizzard_CompactRaidFrameManager.lua#L1037-L1066
[clearSlash]: https://github.com/Gethe/wow-ui-source/blob/09b9db7948abc9b9648dedaab51eb0cf3ee67b31/Interface/AddOns/Blizzard_ChatFrameBase/Shared/SlashCommands.lua#L828-L835
[targetEnable]: https://github.com/Gethe/wow-ui-source/blob/09b9db7948abc9b9648dedaab51eb0cf3ee67b31/Interface/AddOns/Blizzard_CompactRaidFrames/Mainline/Blizzard_CompactRaidFrameManager.lua#L1079-L1087
[readySlash]: https://github.com/Gethe/wow-ui-source/blob/09b9db7948abc9b9648dedaab51eb0cf3ee67b31/Interface/AddOns/Blizzard_ChatFrameBase/Shared/SlashCommands.lua#L1224-L1228
[chat]: https://github.com/Gethe/wow-ui-source/blob/09b9db7948abc9b9648dedaab51eb0cf3ee67b31/Interface/AddOns/Blizzard_APIDocumentationGenerated/ChatInfoDocumentation.lua#L292-L301
[chatSend]: https://github.com/Gethe/wow-ui-source/blob/09b9db7948abc9b9648dedaab51eb0cf3ee67b31/Interface/AddOns/Blizzard_APIDocumentationGenerated/ChatInfoDocumentation.lua#L516-L576
[secret]: https://github.com/Gethe/wow-ui-source/blob/09b9db7948abc9b9648dedaab51eb0cf3ee67b31/Interface/AddOns/Blizzard_APIDocumentationGenerated/SecretPredicatesDocumentation.lua#L63-L72
[readyEvent]: https://github.com/Gethe/wow-ui-source/blob/09b9db7948abc9b9648dedaab51eb0cf3ee67b31/Interface/AddOns/Blizzard_APIDocumentationGenerated/PartyInfoDocumentation.lua#L838-L847
[warning]: https://github.com/Gethe/wow-ui-source/blob/09b9db7948abc9b9648dedaab51eb0cf3ee67b31/Interface/AddOns/Blizzard_RaidWarning/RaidWarning.lua#L81-L86
[targetToggle]: https://github.com/Gethe/wow-ui-source/blob/09b9db7948abc9b9648dedaab51eb0cf3ee67b31/Interface/AddOns/Blizzard_UnitFrame/Mainline/TargetFrame.lua#L688-L694
[frames]: https://github.com/Gethe/wow-ui-source/blob/09b9db7948abc9b9648dedaab51eb0cf3ee67b31/Interface/AddOns/Blizzard_APIDocumentationGenerated/SimpleFrameAPIDocumentation.lua
[frameRestriction]: https://github.com/Gethe/wow-ui-source/blob/09b9db7948abc9b9648dedaab51eb0cf3ee67b31/Interface/AddOns/Blizzard_APIDocumentationGenerated/RestrictedActionsDocumentation.lua#L10-L24
[live]: https://api.github.com/repos/Gethe/wow-ui-source/branches/live
[dbmCommands]: https://github.com/DeadlyBossMods/DeadlyBossMods/blob/61a104843db8c0fe6ee0383327d2ef44e001ccbd/DBM-Core/modules/Commands.lua#L89-L100
[dbmTimers]: https://github.com/DeadlyBossMods/DeadlyBossMods/blob/61a104843db8c0fe6ee0383327d2ef44e001ccbd/DBM-Core/modules/UserTimers.lua#L262-L282
[dbmBreak]: https://github.com/DeadlyBossMods/DeadlyBossMods/blob/61a104843db8c0fe6ee0383327d2ef44e001ccbd/DBM-Core/modules/UserTimers.lua#L249-L259

[markerPermission]: https://github.com/Gethe/wow-ui-source/blob/09b9db7948abc9b9648dedaab51eb0cf3ee67b31/Interface/AddOns/Blizzard_CompactRaidFrames/Mainline/Blizzard_CompactRaidFrameManager.lua#L520-L526
[secureTarget]: https://github.com/Gethe/wow-ui-source/blob/09b9db7948abc9b9648dedaab51eb0cf3ee67b31/Interface/AddOns/Blizzard_FrameXML/SecureTemplates.lua#L585-L606
[deprecatedReady]: https://github.com/Gethe/wow-ui-source/blob/09b9db7948abc9b9648dedaab51eb0cf3ee67b31/Interface/AddOns/Blizzard_DeprecatedPartyInfo/Deprecated_PartyInfo.lua#L20-L22
[markerOrder]: https://github.com/Gethe/wow-ui-source/blob/09b9db7948abc9b9648dedaab51eb0cf3ee67b31/Interface/AddOns/Blizzard_CompactRaidFrames/Mainline/Blizzard_CompactRaidFrameManager.lua#L1-L12
[combatOriginal]: https://discord.com/channels/327414731654692866/1481702172319027331
[combatTranscript]: https://warcraft.wiki.gg/wiki/Patch_12.0.5/API_changes#2026-03-25
