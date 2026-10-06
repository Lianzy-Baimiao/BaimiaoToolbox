## 1.9.20 — 2026-10-07

## English
### Static spell-sequence reminders by default
- Skill cooldowns and charge counts are now opt-in. Open /bmrotation → Display and layout → Show skill cooldowns and charges to enable them.
- Existing profiles switch to static mode once on upgrade; subsequent manual choices are preserved. Plans, icons, names, notes, layout, and specialization handling remain available.
- Turning cooldowns off unregisters cooldown/charge/player-cast listeners, stops pending refresh work, and clears cooldown/charge overlays instead of continuing to query behind hidden visuals.
- When enabled, normal, replacement-spell, and charge-recovery cooldowns are supported. Targeted event refreshes retain bounded recovery for late data.

### Less repeated work
- Reduced synchronous login initialization and unnecessary rebuilds in quick buttons and settings-related UI.
- Bloodlust ready-state monitoring primarily wakes on aura/lifecycle events, with low-frequency recovery checks retained. Battle-resurrection cooldown handling filters unrelated events when safe; countdowns, music, and combat restrictions remain supported.
- Reduced redundant coordinate, quick-button, reminder, Auction House, and Mythic+ refresh work with state-aware scheduling and cache invalidation.

### Diagnostics
- Startup capture has a settings switch and is disabled by default. Enabling applies after a reload; disabling stops the capture. Completed captures do not keep sampling in the background.
- Expanded opt-in /bmperf reports distinguish recent CPU from session averages and expose selected callback/query costs. Reports can be saved for inspection after reload. Native counters and covered callbacks are not a complete per-module CPU breakdown.

### Installation and validation
- 1,154 offline regression tests passed. A live static-mode capture confirmed zero Rotation cooldown queries/refreshes during tracing while other modules received cooldown events. No fixed whole-addon CPU percentage is promised.
- Retail only; English, Simplified Chinese, Traditional Chinese, and Korean remain supported.
- Fully exit the game, replace the addon folder, then restart. Keep SavedVariables; do not reset all settings. Only the cooldown default is migrated once.
- The ZIP contains runtime files and licenses only: no audio, private captures, tests, or publishing documents.

---

## 中文
### 循环提示默认改为静态显示
- 技能冷却与充能层数改为默认关闭。需要时在 /bmrotation → 显示与布局 → 显示技能冷却与充能 中开启。
- 已有配置升级后只切换为静态模式一次，之后保留手动选择；方案、图标、名称、备注、布局与专精切换继续可用。
- 关闭时退订冷却／充能／玩家施法监听，停止待执行刷新并清除冷却和充能显示，不再只是隐藏界面而继续后台查询。
- 开启后支持普通技能、替换技能以及充能恢复冷却；事件定向刷新保留数据晚到时的有界恢复。

### 减少重复工作
- 减少快捷按钮及设置相关界面的同步登录初始化与不必要重建。
- 嗜血就绪态主要由光环及生命周期事件唤醒，同时保留低频恢复校验；战复冷却在安全条件下过滤无关事件，保留倒计时、音乐和战斗限制处理。
- 通过按状态调度和缓存失效，减少坐标、快捷按钮、提醒、拍卖行与史诗钥石界面的重复刷新。

### 性能诊断
- 启动采集增加设置开关，默认关闭；开启后重载生效，关闭立即停止，采集完成后不继续后台采样。
- 扩展按需运行的 /bmperf 报告，区分近期 CPU 与会话平均，提供指定回调／查询耗时，并可保存报告供重载后检查。原生计数和回调覆盖不是完整模块 CPU 分账。

### 安装与验证
- 1154 项离线回归测试通过；本次实机静态模式追踪中，循环冷却查询／刷新为 0，同期其他模块仍收到冷却事件。不承诺整个插件固定 CPU 百分比。
- 仅支持正式服，保留英文、简体中文、繁体中文与韩语。
- 请完全退出游戏后覆盖插件文件夹，再启动游戏；保留 SavedVariables，无需清空设置，仅对冷却默认值做一次迁移。
- ZIP 仅包含运行文件与许可证，不含音频、私人采集、测试或发布说明文档。

---

## 1.9.19 — 2026-10-06

## English
### Bloodlust music
- Added playlists with up to 20 tracks: sequential playback, shuffled playback, or one randomly selected track per Bloodlust trigger.
- Reorder, remove, and preview tracks. One duration control edits the selected track, or the legacy single-track duration when the playlist is empty.
- Playback timers stop with the active Bloodlust session. Audio files are not bundled; configure your own source or use registered shared media.

### Background work and lifecycle
- Quick-button cooldowns share one managed refresh timer instead of per-button frame updates.
- Coordinates sample more slowly while stationary and resume faster updates when moving. Target distance refreshes independently, including when only the target moves.
- Saved disabled modules now run their cleanup after login initialization. Mythic+ unregisters events when disabled and avoids new refresh tasks from inactive native-window hooks; combat-safe restoration is preserved.
- Coordinate and Bloodlust modules now remove remaining event listeners when disabled and restore them when re-enabled.
- Added opt-in /bmperf compare: a roughly 210-second alternating comparison of selected refresh bodies. /bmperf cancel stops the test; results distinguish native addon time from its percentage denominator. This is not a complete module profiler or a guaranteed CPU reduction.

### Target distance
- Removed the persisted client-build-wide range disable. Range checks now respect target/context restrictions and secret values; a blocked context does not disable every other context across future logins.
- Restricted or unavailable range data remains unknown. No protected API restrictions are bypassed.

### Auction House
- Added Liquid Luster (271887) to Potions, with a versatility label and icon fallback for 271886/271887. The catalog now contains 86 presets.
- Replaced outdated Thunderous Drums (219905) with Void-Touched Drums (244639) in Common. Existing personal favorites and restock lists are not rewritten.

### Installation and validation
- Retail only. English, Simplified Chinese, Traditional Chinese, and Korean remain supported.
- 642 offline regression tests passed. Live-client target distance was confirmed working by the user; no fixed CPU or memory saving is claimed.
- Exit the game, replace the addon folder, and restart. Keep SavedVariables. The ZIP contains runtime files and licenses only, without audio or publishing documents.

---

## 中文
### 嗜血音乐
- 新增最多 20 首的音乐列表，支持列表顺序、随机顺序，以及每次嗜血随机选一首播放。
- 支持调序、删除和试听；统一为一个播放时长控件，有列表时编辑选中曲目，无列表时编辑原单曲时长。
- 播放计时器随本次嗜血结束而停止。安装包不附带音频，请自行配置来源或使用已注册的共享媒体。

### 后台工作与生命周期
- 快捷按钮冷却改用单个受管理的共享刷新计时器，替代逐按钮逐帧检查。
- 坐标静止时降低采样频率，移动时恢复快速更新；目标距离独立刷新，玩家不动而目标移动时也能更新。
- 登录初始化后落实已保存的模块关闭状态；史诗钥石停用时注销事件，关闭状态的原生窗口钩子不再创建无用刷新任务，保留战斗中的安全延迟恢复。
- 补齐坐标和嗜血模块停用时的残留事件清理，重新启用时恢复监听。
- 新增按需运行的 /bmperf compare：约 210 秒交替对照指定刷新函数体。/bmperf cancel 可取消；区分插件原生耗时与百分比分母，不是全模块精确分析，也不承诺固定 CPU 降幅。

### 目标距离
- 移除持久化的“整个客户端版本停止测距”记录；按目标、场景和秘密值限制决定是否测距，不再因一次拦截封住以后登录的全部测距场景。
- 受限或不可用的距离仍视为未知，不绕过受保护 API 限制。

### 拍卖行
- 药水新增液态光泽（271887），显示全能属性，并为 271886/271887 提供图标兜底；内置预设增至 86 项。
- 常用分类将过时的掣雷之鼓（219905）替换为虚触战鼓（244639），不改写已有个人收藏和补货清单。

### 安装与验证
- 仅支持正式服，保留英文、简体中文、繁体中文和韩语支持。
- 642 项离线回归测试通过；目标距离已由用户实机确认恢复正常。不承诺固定 CPU 或内存节省。
- 完全退出游戏后覆盖插件文件夹，再启动游戏；保留 SavedVariables。ZIP 仅含运行文件及许可证，不含音频和发布说明文档。

## 1.9.18 — 2026-10-06

Upgrade notes: 1.9.17 → 1.9.18

## English
### Settings
- Reorganized settings groups and collapsible sections across several modules, reduced duplicate headings, and separated display, appearance, and behavior options.
- Single-line fields save on Enter or focus loss; multiline editors retain explicit Save controls.
- The workspace and module settings pages are created on demand instead of building every editor at login.

### Auction House and memory
- Coalesced bursts of item-data refreshes and limited processing to data requested by the helper, avoiding rebuilds caused by unrelated item events.
- Tracked-recipe caches are invalidated when relevant unresolved reagent data arrives; bag changes use targeted inventory refreshes.
- Reduced repeated list, callback, and temporary allocations when reopening the Auction House, with reusable display and sampling data.

### Background work and diagnostics
- Coordinates and Bloodlust monitoring use lifecycle-managed refresh timers, cancelled when disabled. Reduced redundant display writes and temporary allocations in several modules.
- Quick buttons skip repeated clears and unchanged public numeric cooldown writes, preserving query frequency, retry behavior, and restricted-data handling.
- Outside combat and dungeon/raid instances, successful negative Bloodlust aura queries are briefly reused with event invalidation and periodic fallback. Definitely unrelated public incremental aura events can skip a full refresh; removals, full updates, and uncertain data retain the existing path.
- Added opt-in /bmperf: a 30-second diagnostic with separate native recent metrics and selected callback timing, event breakdowns, and internal quick-cooldown refresh timing. Use /bmperf cancel to stop; entering combat ends it automatically. Results are not saved to SavedVariables.
- Native percentages depend on the denominator and overlapping rolling windows; diagnostics do not cover every callback. No fixed memory ceiling or CPU reduction is promised.

### Installation and validation
- Fully exit the game, replace the BaimiaoToolbox folder, and restart to load the new Diagnostics.lua. Preserve SavedVariables; no settings reset is needed.
- Retail only; Simplified Chinese, Traditional Chinese, English, and Korean. New settings and diagnostic messages are localized.
- 593 offline tests and Lua 5.1 syntax checks for all 25 runtime Lua files passed. Offline checks do not replace live-client testing across combat restrictions and addon combinations.
- Auction purchases still require a click for each item; this is not unattended buying. No music files are bundled.

---

## 中文
### 设置界面
- 重组多个模块的设置分组与折叠区域，减少重复标题，明确显示、外观和行为选项的层次。
- 单行输入框回车或失焦保存；多行编辑保留显式保存，减少重复操作提示。
- 工作台及模块设置页按需创建，不再登录时一次构建全部设置界面。

### 拍卖行与内存
- 合并突发物品信息刷新，仅处理助手实际请求的数据，避免无关物品事件反复重建界面。
- 追踪配方只在相关未就绪材料信息到达时失效缓存；背包变化优先更新库存显示。
- 减少重复打开拍卖行时的列表、回调和临时对象分配，复用可复用的显示与采样数据。

### 后台刷新与诊断
- 坐标和嗜血监控改用有生命周期管理的定时刷新，停用时取消相应计时器；减少部分模块的重复显示写入与临时分配。
- 快捷按钮跳过重复清空和未变化的公开数值冷却写入，保留查询频率、失败重试和受限数据处理。
- 嗜血在脱战且非地下城/团队副本时短暂复用成功的“无光环”查询；相关事件立即失效，保留定时兜底。确定无关的公开增量光环事件可跳过全量刷新；移除、完整更新及不确定数据仍走原流程。
- 新增按需运行的 /bmperf：30 秒内分别采集原生近期指标与指定回调耗时，包含事件明细和快捷冷却内部刷新。/bmperf cancel 可取消，进入战斗自动结束；结果不写入存档。
- 原生百分比受分母与滚动窗口影响；诊断并不覆盖所有回调。此次不承诺固定内存上限或 CPU 降幅。

### 安装与验证
- 完全退出游戏后覆盖安装 BaimiaoToolbox 文件夹，再启动游戏，以加载新增 Diagnostics.lua。保留 SavedVariables，无需重置设置。
- 正式服；简体中文、繁体中文、英文和韩语。新增设置与诊断文字同步本地化。
- 593 项离线测试及 25 个运行 Lua 文件的 Lua 5.1 语法检查通过；离线验证不能代替全部客户端、战斗限制和插件组合的实机验证。
- 拍卖行购买仍需逐项点击，不是无人值守购买；不附带音乐文件。

## 1.9.17 — 2026-10-05

Upgrade notes: 1.9.16 → 1.9.17 · 2026-10-05

## English

### Localization

- Added English, Traditional Chinese, and Korean alongside Simplified Chinese. The interface automatically follows the game client: zhCN, zhTW, enUS/enGB, or koKR; other client languages fall back to English.
- Each language has a separate Lua catalog with 994 messages covering the workspace, module settings, panels, help, and chat output. No manual language selector or Japanese catalog is added.
- Preserved existing custom names, favorites, search terms, templates, and saved category IDs. Native game names use client-localized data where available.
- Added English/Traditional Chinese action aliases and ST branch syntax while keeping legacy commands compatible. Auction controls allow more space for longer translations; Korean uses client-native fonts.

### Auction House stacking

- Attached the companion to the native Auction House window instead of repeatedly copying frame levels. The panel and its controls now follow the native window's raising/lowering, strata, and visibility together, fixing inconsistent overlap with target portraits and addons such as Decursive.
- Fixed inherited scaling to keep matching heights. Standalone previews and settings transitions remain available; reattachment is deferred during combat, and closing cancels pending display requests. No native or third-party frame levels are changed.

### Tooltip readability

- Split long tracked-restock, retry, craft-count, mount, and other help text into readable lines in all four languages; added missing word wrapping for dynamic warnings and custom text.
- Kept material-quality help short and multiline. Restock search buttons remain tooltip-free; native item and spell tooltips are unchanged.

### Light theme

- Reworked light surfaces with neutral gray/white backgrounds, darker text, and restrained accents; reduced tinted backgrounds and slider glare.
- Removed black outlines/shadows from light-panel text without changing saved font-outline preferences or unrelated UI fonts.
- Fixed stale dark borders after editing, hovering, or switching themes; improved theme-aware status, dropdown, and stat-label colors.

### Upgrade and validation

- Fully exit the game before installing, then restart to load the new locale files. Keep existing SavedVariables; no settings reset is required. Retail only.
- 503 offline tests and Lua 5.1 syntax checks for all 24 runtime Lua files passed. The reported auction stacking scenario was confirmed in game; this does not represent visual testing on every language client or addon combination.
- Purchase behavior is unchanged: each item still requires a purchase click. This is not unattended buying.

---

## 中文

### 多语言

- 在简体中文基础上新增英文、繁体中文、韩语界面，自动跟随客户端：zhCN、zhTW、enUS/enGB、koKR；其他客户端语言回退英文。
- 每种语言使用独立 Lua 文件，覆盖工作台、模块设置、功能面板、帮助与聊天消息，共 994 条。不增加手动语言切换或日语文件。
- 保留已有方案名、收藏、搜索词、模板和分类存档标识；物品、法术等名称优先使用客户端本地化数据。
- 新增英文 / 繁体动作别名与 ST 分支语法，兼容旧命令；为较长译文调整拍卖行控件空间，韩语使用客户端原生字体。

### 拍卖行窗口层级

- 助手真正挂接到原生拍卖行窗口，不再反复复制层级数值；面板与按钮整体跟随原生窗口升降、分层和显隐，修复与目标头像、Decursive 等界面遮挡顺序不一致的问题。
- 修正继承缩放，保持与拍卖行等高；保留独立预览及设置切换，战斗中延后重新挂接，关闭时取消待显示请求。不修改原生窗口或其他插件的层级。

### 鼠标提示排版

- 追踪补货、重试购买、制作次数、坐骑等长说明按语义分行，四种语言同步调整；动态警告和自定义文本补齐自动折行。
- 材料品质提示保持简短、多行；补货搜索按钮继续不显示鼠标说明，原生物品 / 法术提示不变。

### 浅色主题

- 使用中性灰白背景、深色文字和更克制的强调色，减少偏色底板与滑块高光。
- 去除浅色面板文字的黑色描边和阴影，保留已有轮廓字体偏好，不修改无关界面字体。
- 修复编辑、悬停和切换主题后的边框残留，优化状态文字、下拉箭头及属性标签的主题配色。

### 升级与验证

- 请完全退出游戏后安装，再重新启动以加载新增语言文件。保留 SavedVariables，无需清空设置；仅支持正式服。
- 503 项离线测试及全部 24 个运行 Lua 文件的 Lua 5.1 语法检查通过。本次反馈的拍卖行遮挡场景已获游戏内确认，不代表所有语言客户端和插件组合均已实机验证。
- 购买流程不变：仍需每项点击购买，不是无人值守购买。

## 1.9.16 — 2026-10-05

Upgrade notes: 1.9.15 → 1.9.16 · 2026-10-05

## English

### New Auction House companion

- Added a dedicated settings page and **/bmah** panel with light/dark themes; no Yishier dependency.
- Quick search includes **85 presets in 11 visible categories**, including profession missives. Personal favorites have their own list and count. Flasks, potions, gems, enchants, and missives display color-coded Chinese stat abbreviations.
- Save multiple restock plans with target quantities, optional per-item price caps, and a session budget. Disabled entries are hidden from shopping lists, not deleted from settings. A cap/budget of zero means no configured limit.
- **Tracked-recipe restocking** reads tracked crafting/recrafting recipes. Choose all or one recipe, craft count, and material quality; the default is the highest tier actually available. Duplicate materials are merged, with matching-quality bag/bank inventory and known incoming mail deducted. Optional reagents, sparks, currencies, and finished-item quality are not selected or guaranteed. Manual restock plans do not count bank inventory.
- Prices are queried automatically, but **each item requires a purchase click**. A final quote is confirmed only within the amount authorized by that click. After success, the next item is queried without starting another purchase. Supports commodities only, not unattended buying. Price increases, expired quotes, and insufficient funds do not submit an order; unresolved orders keep their in-transit quantities to reduce duplicate purchases.

### Usability and presentation

- Each manual/tracked restock row has a search button that opens the native buying page and clears stale categories/filters, without purchasing. Search buttons have no verbose hover text; material-quality help uses three short lines.
- Quality labels use native reagent icons and actual tiers rather than assuming a gold icon means five stars.
- The companion docks to the Auction House's right side and follows movement, height, scale, and frame layer. Dragging preserves its relative offset. Opening settings hides the companion until settings close.

### Install and compatibility

- Fully exit the game, install the **BaimiaoToolbox** folder from **BaimiaoToolbox-1.9.16.zip** into `World of Warcraft/_retail_/Interface/AddOns/`, then restart to load the new modules. Do not use GitHub's automatic Source code archives as the addon package.
- Keep existing SavedVariables; no settings reset is required. Retail only; the in-game interface remains Simplified Chinese only. No required external addon and no bundled audio.
- Game restrictions still apply. Automatic quote confirmation and rendering across other addons need in-game verification; try small quantities of low-cost materials first.

**Validation:** 459 offline tests and Lua 5.1 syntax checks for all 19 runtime Lua files passed. These checks do not replace live-client acceptance.

---

## 中文

### 新增拍卖行助手

- 新增独立设置页及 **/bmah** 面板，支持深浅主题，不依赖 Yishier。
- 快捷搜索提供 **85 项预设、11 个直接可见的分类**，新增公函；个人收藏独立管理与计数。合剂、药水、宝石、附魔和公函显示彩色属性简写。
- 清单补货支持多套方案、目标库存、可选单项限价和本次预算。停用项目不再占购买列表，仍可在设置中启用；限价 / 预算为 0 表示不限。
- **追踪配方补货**读取普通制作及再造的追踪配方，可选全部或单个配方、制作份数与材料品质，默认材料实际最高档。合并重复材料，按精确品质扣除背包、银行可见库存及已知邮件；不代选可选材料、火花和货币，不保证成品品质。普通清单不计银行。
- 自动查询价格，**每项点一次购买**；最终报价不高于本次点击授权金额才确认，成功后只查询下一项，不自动开始下一笔付款。仅支持商品类物品，不是无人值守购买；涨价、过期或余额不足时不提交。真实未决订单保留在途数量，降低重复采购风险。

### 交互与显示优化

- 两种补货清单每行均有搜索按钮：打开原生购买页并清除旧分类 / 筛选，只搜索、不购买。搜索按钮移除啰嗦的鼠标说明，品质提示压缩为三行。
- 材料品质使用客户端原生图标和实际档位，不再将金色图标误写为五星。
- 助手默认贴在拍卖行右侧，同步移动、高度、缩放和窗口层级；拖动后保留相对偏移。打开设置时隐藏助手，关闭设置后恢复，避免交叉显示。

### 安装与兼容性

- 完全退出游戏，将 **BaimiaoToolbox-1.9.16.zip** 中的 **BaimiaoToolbox** 文件夹安装到 `World of Warcraft/_retail_/Interface/AddOns/`，再重新启动以加载新增模块。不要使用 GitHub 自动生成的 Source code 压缩包安装。
- 保留 SavedVariables，无需清空设置。仅面向正式服，游戏内界面仍仅提供简体中文；无需必装的外部插件，安装包不含音频。
- 仍遵守游戏限制。报价自动确认及跨插件显示效果需游戏内验证，首次建议少量低价材料试用。

**验证：**459 项离线测试及全部 19 个运行 Lua 文件的 Lua 5.1 语法检查通过，不代替真实客户端验收。

## 1.9.15 — 2026-10-04

Upgrade notes: 1.9.14 → 1.9.15 · 2026-10-04

## English

### New small utilities

- **Copy character name:** Use supported player, friend, or chat context menus to open a preselected `Name-Realm` field, then press Ctrl+C. Multiple online Battle.net characters can be selected individually; BattleTags are not copied.
- **Instance information:** A text-only reminder shows instance difficulty, loot specialization, and lowest equipped-item durability. Durability at 30% or below is highlighted. No background or border.
- **Queue-ready reminders:** Text notifications for Dungeon/Raid Finder and battleground/arena queue confirmations, with an optional extra sound. Instance and queue reminders each have their own hold time (1–30 seconds), fade time (0–10 seconds), and preview.
- **Trade receipts:** After the game confirms a successful trade, a local chat message summarizes the partner, gold, items, and enchantment service. Cancelled trades do not produce receipts. Nothing is sent to chat channels or saved as a trade ledger.
- Each utility has its own switch and is enabled by default within the Small Tools module. Queue sounds respect the game's main sound, volume, and background-audio settings; the addon does not force sound through mute or change global audio settings. Queue confirmations are never accepted automatically.

### Global appearance

- Added **Appearance Settings** in the workspace sidebar. One account-wide font-outline switch controls the addon's non-settings text, including overlays, shortcut labels, cooldown numbers, Mythic+ panels, and reminder strips.
- The first upgrade inherits the existing coordinate-overlay outline preference. Module font sizes and colors remain unchanged. Settings pages, Blizzard UI, and other addons are not affected.

### Mythic+ and party keystones

- Expanded party-keystone sharing with AngryKeystones and LibOpenRaid-compatible messages, alongside existing LibKeystone, Keystone Group List, and current-party keystone-link support. Only current-party data is used, with message validation, throttling, and bounded decompression.
- Long dungeon names use compact Chinese aliases in party rows; full names remain available in tooltips.
- Dungeon summaries now show all available weekly runs in a compact format such as `2 runs +17/+15`. Long lists end with an ellipsis instead of occupying extra rows. The summary tooltip lists every available run, including repeated levels, elapsed time, and timed/overtime status, without a team roster. Other views retain their existing team tooltips.

### Quick buttons

- Configure all five mount categories on one compact page: flying, repair, auction house, passenger, and underwater. Choose mouse/modifier combinations for each category, leave one unbound, or restore defaults. Assigning an occupied combination swaps the assignments; these are button click bindings, not global keyboard bindings.
- Extension entries now use an editable row list with type, name/ID, optional short label, move-up/down, delete, and add-row controls. Common actions use a dropdown. The type column is wider and stays on one line.
- Existing extension text and settings are preserved. Improved toy recognition, including item `253629`, with asynchronous item-data handling and support for full-width Chinese colons in legacy entries.

### Spell-sequence reminders

- Separate skill IDs or names with whitespace; standalone punctuation and arrows between them are accepted. Compact `>` / `+` sequences and repetition markers remain supported. Use spell IDs for names containing spaces.
- Support labels such as `单体 383328 /AOE 53385`: both skills appear at once, with single-target/AOE captions above their icons. Labels apply to the next skill; the addon does not choose a branch automatically.
- All skill icons stay on **one horizontal line**. Long sequences automatically scale down to fit the screen without changing the saved scale preference. Removed the per-row setting and the 24-icon cap; the 2048-byte input limit remains.
- Each specialization's individual plans can store notes and independently choose whether to display them below the skill line. Notes may wrap; skill icons do not. Existing plans and notes are preserved.
- This remains a passive sequence reminder with cooldown cues, not a dynamic DPS recommendation engine or automatic casting tool.

### Installation, compatibility, and validation

1. Fully exit the game, then install the `BaimiaoToolbox` folder from **BaimiaoToolbox-1.9.15.zip** into `World of Warcraft/_retail_/Interface/AddOns/`. Restart the client so the new runtime files are loaded. Do not use GitHub's automatic Source code archives as the install package.
2. Keep your SavedVariables; no configuration reset is required. Open `/bm` to review the new utilities and appearance setting.
3. Retail only; the in-game interface is currently Simplified Chinese only. No external addon is required to load it. Party-keystone availability depends on compatible sharing or a real link from a current party member; missing information is not treated as “no keystone.”
4. No audio files are bundled. Optional bloodlust music needs a separately configured source. The private, modified LibDeflate component retains its zlib license; the addon's own code remains MIT-licensed.

**Validation:** 366 offline tests and Lua 5.1 syntax checks for all 15 runtime Lua files passed. Offline checks do not replace in-game verification of rendering, sound, trade events, or cross-addon sharing.

---

## 中文

升级说明：1.9.14 → 1.9.15 · 2026-10-04

### 新增小工具

- **复制角色名：**在支持的玩家、好友或聊天右键菜单中打开已选中的“名字-服务器”，手动按 Ctrl+C 复制。战网多角色可逐个选择，不复制战网昵称。
- **进本信息：**纯文字显示副本难度、拾取专精和最低装备耐久，耐久不高于 30% 时醒目标色；没有背景或边框。
- **排队就绪提醒：**地下城 / 团队查找器及战场 / 竞技场队列待确认时显示文字，可选额外提示音。进本与排队提醒分别设置停留时间（1–30 秒）、渐隐时间（0–10 秒），并提供预览。
- **交易完成回执：**游戏确认交易成功后，在本机聊天框显示交易对象、金币、物品及附魔服务摘要；取消交易不生成回执。不向聊天频道发送，也不建立交易账本。
- 四项功能在小工具模块内独立开关、默认启用。排队提示音遵循游戏主声音、音量和后台声音设置，不强制突破静音或修改全局声音设置，也不会自动接受队列邀请。

### 全局外观设置

- 工作台左侧新增 **外观设置**，将轮廓字体抽离为账号共享开关，统一控制插件所有非设置界面的文字，包括屏幕提示、快捷按钮、冷却数字、大秘境面板和提示小条。
- 首次升级继承原坐标喊话的轮廓选择，保留各模块字号和颜色；不修改设置页、游戏原生界面或其他插件字体。

### 大秘境与队友钥石

- 队友钥石新增 AngryKeystones 和 LibOpenRaid 兼容消息支持，保留 LibKeystone、Keystone Group List 及当前队友分享钥石链接的识别。仅使用当前小队数据，并加入消息校验、节流和解压大小限制。
- 队友钥石行采用长副本名简称：纳洛拉克的洞穴 → 洞穴、虚空之痕竞技场 → 竞技场、塞塔里斯神庙 → 神庙、红玉新生法池 → 红玉。鼠标提示仍保留全名。
- 副本汇总紧凑显示所有可获取的本周记录，例如 `2次 +17/+15`；次数较多时末尾省略，不额外占行。汇总鼠标提示列出全部记录，包括重复层数、用时和限时 / 超时状态，不再显示队伍名单；其他视图原有的队伍提示不变。

### 快捷按钮

- 飞行、修理、拍卖行、载人、水下五类坐骑集中在同一紧凑页面；可自选鼠标与修饰键组合、设为不绑定或恢复默认。选择已占用组合时交换绑定；仅作用于按钮点击，不修改游戏全局键盘绑定。
- 扩展内容改为逐条编辑：每行包含类型、名称 / ID、可选短名，以及上移、下移、删除操作；支持新增行，常用动作通过下拉选择。类型列加宽，文字保持单行。
- 保留原扩展内容与设置；修复“奥术秘社的私人钥匙”（物品 ID `253629`）等玩具识别，兼容异步物品加载和旧条目中的全角冒号。

### 循环提示助手

- 技能 ID / 名称按空白分隔，中间独立的标点和箭头均可使用；继续兼容紧凑 `>` / `+` 写法及次数标记。含空格的技能名称请使用技能 ID。
- 支持 `单体 383328 /AOE 53385`：两个技能同时显示，并在图标上方分别标注单体 / AOE。标注只作用于紧随的技能，不自动判断或选择分支。
- **所有技能图标固定在同一横行**，过长时自动缩小以适应屏幕，不修改用户保存的缩放值。移除每行数量设置和 24 图标上限，保留 2048 字节输入限制。
- 每个专精的每个方案可独立填写备注，并选择是否显示在技能行下方。备注可以换行，技能图标不会换行；原方案和备注继续保留。
- 仍为带冷却信息的被动顺序提示，不是动态输出推荐，也不会自动施法。

### 安装、兼容性与验证

1. **完全退出游戏**，将 **BaimiaoToolbox-1.9.15.zip** 内的 `BaimiaoToolbox` 文件夹安装到 `World of Warcraft/_retail_/Interface/AddOns/`，再重新启动客户端，以加载新增运行文件。不要使用 GitHub 自动生成的 Source code 压缩包安装。
2. 保留 SavedVariables，无需清空或重置配置。输入 `/bm` 检查新增小工具及外观开关。
3. 仅支持正式服，当前游戏内界面仅提供简体中文。插件本体无需必装的第三方插件；队友钥石仍依赖兼容同步或当前队友提供的真实链接，未获取数据不等于没有钥石。
4. 安装包不含音频文件，嗜血音乐需单独配置来源。内嵌的私有修改版 LibDeflate 保留 zlib 许可证，插件自有代码仍使用 MIT 许可证。

**验证：**366 项离线测试及全部 15 个运行 Lua 文件的 Lua 5.1 语法检查通过。离线验证不代替真实游戏内的显示、声音、交易事件或跨插件同步验收。

## 1.9.14 — 2026-10-03

本次公开版本合并 1.9.9–1.9.14 的本地迭代，包含队友钥石、小工具集合、标记助手、超时染色及紧凑界面。

- README 精简为功能清单、安装与入口说明；删除图片、装饰图标、版本日志及冗长示例，不改动插件图标或独立 CHANGELOG 历史。
- 坐标喊话“屏幕显示”：坐标 / 移速 / 目标距离三个开关同排，锁定 / 轮廓字体同排，三种颜色同排，字号 / 缩放双列；保留原设置读写与角色锁定逻辑。
- 小工具集合：两个右键菜单开关同排，标记助手的三类功能同排、三个显示 / 锁定选项同排；缩放和重置位置并排。仅队长显示、三行启用及标记 / 倒数行为不变。
- 共享布局新增按单元格宽度排布的 Row；窄面板自动换行，以同排最高控件计算后续位置。Switch 仍为 26×14、13 号标签，文字命中区域限制在各自单元格；仅行内滑块轨道按宽度适配，其他模块布局不变。
- 217 项离线回归与 12 个运行文件 Lua 5.1 语法检查通过；新增并排锚点、点击边界、窄宽度回退、滑块 / 颜色回调、分页稳定性和 README 精简检查。离线示意图不代替游戏内字体和点击验证。
- 相比上一公开版本 1.9.8，新增三个运行文件；升级后建议完全退出客户端再进入。已正常加载本地 1.9.11 或之后版本可 /reload。保留用户配置，新包不含音乐文件；旧版本残留的 media/lust_ball.ogg 不再使用，可手动删除。

## 1.9.13 — 2026-10-03（本地迭代，合并于 1.9.14）

- 修复队友钥石姓名栏仅 34 像素导致“XX…”：向左扩展 66 像素，姓名宽度 100、行宽 192，层数 / 副本列、右边界、按钮及其他区域锚点不变。当前钥石和评分保留间隔，长钥石标题按需在 14–18 号间适配，未组队时恢复原字号 / 宽度。
- 标记助手新增默认关闭的“仅队长显示”开关。开启后仅在本人为小队队长或团长时显示，不包含团队助理和单人；队长转移 / 队伍变化自动刷新，战斗期间延后脱战处理，不改变标记和倒数权限。
- 按要求删除私人音乐文件及其共享媒体注册 / 播放回退，不再作为默认项。旧内置曲目选择迁移为自定义，保留已填路径、声道和循环设置；其他共享声音与自定义播放仍可用，嗜血触发和出本清理逻辑未改变。增加忽略规则防止误加入。
- 208 项离线回归及 12 个运行文件 Lua 5.1 语法检查通过；新增姓名 / 标题避让、队长开关与音频移除回归，更新离线预览。实际游戏字体、权限和安全动作仍需客户端验收。
- 已加载 1.9.11 / 1.9.12 可覆盖后 /reload；更早版本需完全退出重进。本地安装与新包不含私人音频；旧 Git 历史、旧备份与旧包未改写或清理。未提交 Git 或发布 Release。

## 1.9.12 — 2026-10-03（本地迭代，合并于 1.9.14）

- 标记助手新增“目标标记”“地面标记”“团队管理（就位 / 倒数）”三个独立开关，默认全开，保留已有设置。关闭行后其余行自动上移，单行工具条高度 60，三行仍为 118；三行全关时隐藏整条，不留标题空壳。
- 所有受保护子按钮与工具条的显隐 / 高度 / 锚点变更均在脱战后执行；关闭管理行不再响应旧回调，隐藏行时清理其悬停提示，不影响其他提示框。不改动安全动作与原生倒数接口。
- 共享 Switch 从 32×18 缩为 26×14，方形滑块 8×8；文字保持 13 号，点击区高度至少 18 并包含文字，保留长标签折行、明暗主题、禁用及战斗锁定。
- 197 项离线回归通过，覆盖三行全部八种组合、战斗延后、设置读写、工具栏重启与较小开关命中范围；12 个运行文件 Lua 5.1 语法检查通过。更新离线示意图，实际游戏效果仍需验收。
- 单独核对用户报告的 MeetingStone AutoHideController.lua:26 保护调用：安装文件按键回调无条件调用 SetPropagateKeyboardInput；只读隔离重放及内存战斗判断对比已记录。未修改集合石、未屏蔽报错、未声称还原完整游戏污染链；此工具箱版本不是集合石修复补丁。
- 从已正常加载的 1.9.11 升级可 /reload；更早版本因 1.9.11 的新增运行文件仍需完全退出并重进。未提交 Git 或发布 Release。

## 1.9.11 — 2026-10-03（本地迭代，合并于 1.9.14）

- 史诗钥石地下城页签在“设置 / 刷新”下方常驻最多四行小队队友钥石，不新增入口、折叠或额外面板，不显示本人和团队成员；其他元素坐标及窗口尺寸不变，仅收窄当前钥石 / 评分的文字宽度以免重叠。
- 队友姓名职业染色，层数与副本紧凑排列，悬停显示全名。独立实现 LibKS / WA-KeyStGrList 同步格式，并支持队友在小队频道分享的钥石链接；无数据、明确无钥石、离线分别显示，不猜测或持久化队友历史。跨服严格匹配，离组 / 换人 / 过图 / 开始和完成挑战时清理，发送受节流及战斗限制。
- 小工具集合新增标记助手：安全按钮手动设置 / 清除目标八标及地面八标；就位确认、5 / 10 秒倒数及取消调用原生团队管理接口，不含信号系统，不通过聊天或第三方计时协议发送倒数。默认组队时显示，支持锁定、缩放和角色独立位置；战斗中延后布局和显隐变更。
- 共享 Switch 从 44×24 缩为 32×18，方形滑块缩为 12×12，保留 13 号标签、文字点击与明暗主题。工作台顶部标题及其他既有行为不变。
- 193 项离线回归及 12 个运行文件 Lua 5.1 语法检查通过；新增队友钥石、标记及布局示意和 API 边界文档。安全按钮执行、原生倒数 / 取消及插件组合仍需游戏内验证。新增两个 TOC 文件，覆盖后需完全退出客户端并重进。

## 1.9.10 — 2026-10-02（本地迭代，合并于 1.9.14）

- 纠正工作台紧凑化方向：恢复首页标题、品牌标识及原有横幅。只压缩单个功能卡片：238×104、说明为 11 号单行文字，保留 15 号功能名与可点击按钮。
- 工作台为 1000×660，三列七模块与底部入口一屏可见，1280×720 无需额外缩小；长设置页保留滚动和分页行为。
- 所有共享设置复选框统一改为 44×24 直角矩形 Switch，18×18 方形滑块，无默认勾选图案；开启 / 关闭有位置与颜色双重区别，支持明暗主题、悬停、禁用和点击标签。长标签的点击范围不覆盖下一项。
- 保留配置读写与回调，战斗锁定时不写入设置；不修改邀请、大秘境记录、最佳队伍或嗜血音乐逻辑。
- 164 项离线回归与 10 个运行文件 Lua 5.1 语法检查通过；更新明确标注为示意图的首页 / 开关预览。真实字体、点击命中与插件组合仍需游戏内验收。已安装本地 1.9.9 可覆盖后 `/reload`，无新增运行文件。

## 1.9.9 — 2026-10-02（本地迭代，合并于 1.9.14）

- 工作台收紧为 1000×620，删除宣传横幅，改为三列 238×116 功能卡片。七个模块、开关及底部入口均在首页可见，无需滚动；1280×720 下无需额外缩小，长设置页仍正常滚动。
- 副本概览、本周记录、副本汇总、本周最高层数与提示框的超时层数使用主题暗色；限时层数保留游戏稀有度颜色。当前持有钥石不属于失败记录，颜色不受影响。
- 修复染色链路只传层数、汇总只保留最高数字而丢失限时状态的问题；同层同时有限时和超时优先显示限时状态，未知用时不误判超时。赛季成绩使用自己的用时，周成绩不覆盖赛季判断。不修改最佳队伍选择规则。
- 新增独立模块“小工具集合”：右键公会邀请、多角色在线选择角色邀请组队，两个开关独立保存。公会邀请支持角色全名及战网好友角色选择，仅本人具备权限时显示；不向自己、已知已入会角色或 NPC 提供入会动作。
- 使用暴雪 Menu.ModifyMenu 追加菜单，不替换原菜单。战网好友完整枚举在线游戏账号，区分好友索引 / 战网账号 ID / 游戏账号 ID；排除离线、非魔兽、不同版本及跨地区角色，点击时重新核对角色及权限。仅手动点击发起邀请，不群发、不自动邀请、不绕过游戏限制。
- 158 项离线回归与 10 个运行文件 Lua 5.1 语法检查通过；其中新增 23 项覆盖工作台密度、超时染色及右键邀请。实际右键菜单、组队、公会权限及插件组合仍需游戏内验证。新增 TOC 文件建议完全退出客户端后重新进入；保留原配置与嗜血音乐逻辑。

## 1.9.8 — 2026-10-02

- 用户确认 1.9.7 大秘境音乐已能播放；本次保留该触发路径，修复备用“嗜血中”状态没有副本边界、出本仍继续倒数的问题。备用推定仅小队/团队副本内生效，轮询和音乐计时器都检查；野外只认真实可读的增益。
- 离开世界时停播，进入世界重新建基线，区域变化立即刷新；公开疲惫时间能证明为旧数据时不启动推定，避免过图后晚加载制造假触发。修复载入期间关模块、入场后重开留下旧载入标记的边界。
- 本周记录与本周副本汇总优先选本周最佳，卡片仍优先选赛季高分最佳。首选不足两名公开姓名、另一份最佳有队友信息时，整条切换到另一份最佳，并同步来源、层数、评分、用时；绝不拼接不同场次的名单。
- API 仅提供一人资料或部分姓名时，在现有队伍标题中短标注；不增加长说明或虚构队友。新增按需命令 `/bmmp team`，输出最近悬停副本的选择来源及各最佳记录公开可读的名单/姓名数量。
- 新增 17 项后续回归，更新本周/赛季分源预期，完整 135 项离线测试与 9 个运行文件 Lua 5.1 语法检查通过。出本状态已离线复现并修复；用户随后提供的诊断显示，本周与赛季限时最佳各 1 人、赛季超时最佳 5 人；本版在该情况下不改选另一场超时队伍，限时最佳队员缺失仍为已知限制。嗜血出本修复的游戏内效果待确认。

## 1.9.7 — 2026-10-02

- 针对大秘境增益查询返回空值、只显示疲惫冷却而从未请求播放的路径，增加“本机新获得公开疲惫”的约 40 秒备用触发；可读真实增益优先，推定倒计时明确带“约”。不读取或运算秘密光环/时间字段。
- 登录、进入世界和重新启用时先建立疲惫基线，旧疲惫不触发；查询失败或秘密结果不当成“确认没有”。死亡、疲惫移除、到期与模块关闭会停止备用音乐/循环。
- 音乐状态与显示文字、行开关和单人/小队/团队显示开关解耦；嗜血期间切换音乐启用开关立即生效。手动停止/试听不会在下一次轮询被自动播放抢回，试听取消旧循环。
- 修复共享媒体库暂未加载时被永久缓存为缺失；保留原有声音、声道和用户配置。
- 新增按需命令 `/raidcd music`，区分未检测到、资源未找到、接口失败、客户端拒绝与已接受请求；接受请求不等于可听见，不自动刷屏或写入存档。
- 新增 20 项实际模块离线音乐回归，完整测试 118 项通过；受限 API 为模拟输入，尚无本次用户副本的现场采样，实际大秘境播放仍待游戏内验证。大秘境 UI 保持 1.9.6 不变。

## 1.9.6 — 2026-10-02

- 修复删除说明后仍保留页脚高度的问题：默认窗口从 840×494 缩至 840×462，内容区 820×422；左右面板共用底线，底部内边距为 8 像素。
- 将可见外框移到内缩内容区，底边距原窗口底部 8 像素；独立的不透明 HIGH 图层仍覆盖至原生底部，避免重新露出旧副本图标。
- 本周记录 / 副本汇总改为一体式分段选择栏：选中底色、主题色下划线与数量；切换不改变列表尺寸，重置滚动位置，不足十条时不再提示滚轮。
- 未学会、冷却、状态未知、传送关闭、战斗中均使用同位置的非安全状态框；仅已学会且冷却就绪时显示强调色安全传送按钮。不可用时清除施法属性，状态变化时关闭过期提示；不在战斗中修改安全按钮。
- 回归根因：原页脚只隐藏未收回高度，左右高度独立硬编码，冷却分支仅检查技能是否学会。新增共同底线、边框/遮罩隔离及完整状态切换测试。
- 完整离线测试 98 项通过；布局示意图同步更新，新增副本汇总视图。真实客户端视觉与受保护操作仍待游戏内验收。

## 1.9.5 — 2026-10-02

- 精简悬停详情：卡片仅显示最佳成绩、用时和队伍；本周记录先显示本次层数 / 用时 / 状态 / 评分，再单独显示最佳队伍。移除日期、词缀、重复赛季 / 本周摘要和“队伍成员”标题。
- 最佳队伍改为双列对齐：左侧职业色姓名，右侧柔和色专精 / 职业；最佳来源标题保留并使用强调色，避免将最佳队伍误认为每一条记录的实际队伍。
- 传送按钮仅提示传送状态，不再附整份队伍信息；宝库提示缩为两句。
- 删除页底常驻说明及设置中史诗钥石入口下方等解释段落，保留功能控件；战斗期间仅显示“战斗中暂不可传送”。
- 新增提示行数 / 双列、传送与宝库短提示、设置去说明及战斗短提示回归；完整离线测试 90 项通过，另附明确标注的双列提示示意图。

## 1.9.4 — 2026-10-02

- 修复副本卡片非传送区域仍提示“点击传送”：卡片仅显示副本与最佳队伍详情，传送操作提示仅出现在真正的传送按钮上；安全点击逻辑不变。
- “兼容与说明”精简为“兼容与刷新”，删除说明段落、分组标题及插件加载状态，仅保留“隐藏 Kogo 旧本周看板”开关和“重新请求游戏数据”按钮；移除模块顶部的共用介绍文字。
- 增加传送按钮与卡片之间切换悬停、设置页控件精简及操作可用性的回归；完整离线测试 87 项通过。

## 1.9.3 — 2026-10-02

- 最佳队伍提示中的队员姓名按职业染色，职业 / 专精保留柔和文字色；优先游戏职业色 API，兼容标准职业颜色表，未知或受限颜色保持中性，不修改原始名单。
- 顶部“设置”“刷新”改为同一行并排放置，间距 6 像素；不再上下分散，保留当前钥石与标题的独立空间。
- 新增职业色、颜色回退 / 重置、按钮聚拢与避让的回归测试；完整离线测试 85 项通过，客户端视觉效果仍需游戏内确认。

## 1.9.2 — 2026-10-02

- 收紧大秘境页布局：默认窗口从 920×602 调整为 840×494，占用面积减少约 25%；缩小卡片间距、图标与宝库区，保留两列八张副本卡和十条可见记录，不靠整体缩放挤压内容。
- 卡片、传送按钮、记录与宝库的悬停提示改为跟随鼠标；记录补充完成日期、评分与用时详情，滚动和刷新时清除旧行提示。
- 直接展示最佳成绩对应的队伍姓名、职业与专精：优先赛季最高分成绩，缺少赛季最佳时用本周最佳。单独标注“赛季限时最佳队伍 / 赛季超时最佳队伍 / 本周最佳队伍”，不冒充所悬停历史记录的队伍，不做逐条匹配或额外保存队伍历史。
- 本周记录在限时 / 超时前新增用时与限时，例如“(25:24/32) 限时”；时间缺失显示未知，副本汇总页仍显示次数与最高层数。
- 新增鼠标锚点、最佳队伍选择、受限字段、时间格式、紧凑布局及滚动提示的回归场景；完整离线测试 82 项通过。真实鼠标跟随、字体排版与传送仍需客户端验收。

## 1.9.1 — 2026-10-02

- 修复史诗钥石页底部仍露出原生 8 个副本图标：新内容层使用与原生图标相同的 HIGH 图层、较高层级，并覆盖到内容区底部；不删除或永久隐藏原生控件。
- 当前钥石改为更大字号与主题强调色，删除赛季评分后的“数据来自游戏”。
- 修复零售版传送已学会检测，优先读取 C_SpellBook.IsSpellKnown，保留旧 API 兼容；安全传送按钮与内容层对齐，避免被面板挡住。仍只允许玩家左键手动施法。
- 钥石层数、副本评分、角色赛季总评分分别采用对应游戏 API 的颜色；卡片、本周记录与汇总统一展示，超时状态单独着色。
- 修复切到 PvP 后窗口背景变窄：退出钥石页只还原仍由本模块控制的尺寸与缩放，不再覆盖目标页签刚设置的宽度。
- 补充 HIGH 图层、现代法术书 API、PvP 切页顺序、战斗切换与颜色降级的回归场景；完整离线测试 73 项通过。真实施法、客户端渲染和插件组合仍需游戏内验收。

## 1.9.0 — 2026-10-02

- 新增独立「大秘境信息优化」模块，统一系统史诗钥石地下城页签的卡片布局与左右区域风格。
- 自主显示当前钥石、赛季评分、本周词缀、赛季副本成绩、本周记录与副本汇总；记录可滚动，副本数量增加时可翻页。
- 地下城宝库进度直接读取游戏，不从记录推测奖励；空记录与数据待同步分开标注。
- 新增安全点击副本传送，区分未学会、未收录、冷却及战斗状态；战斗中不修改安全按钮属性与布局。
- 无 EUI / AngryKeystones 依赖；默认临时隐藏 Kogo 旧本周面板，不修改其它插件配置。AK 的预测日程不在新布局中显示，其它功能保留。
- 设置拆分为显示与布局、副本与传送、兼容与说明；支持明暗主题、缩放、排序与单独隐藏本周看板，关闭可恢复原布局。
- 增加 Lua API/界面桩离线回归测试，以及明确标注的布局示意图；仍需游戏内测试渲染、传送和插件组合。

## 1.8.3 — 2026-10-01

- 修复水下等专门用途未绑定、无默认候选或绑定未收藏坐骑时错误回退到随机收藏坐骑的问题；现在提示重新绑定，只有飞行用途保留随机回退。
- 嗜血/战复监控新增独立「显示嗜血行」开关，默认开启，兼容已有配置。
- 仅显示战复时自动上移并收紧高度；两行都关闭时隐藏监控框。
- 使用独立轮询框，关闭两行显示不影响嗜血音乐检测，模块总开关仍停止轮询处理与音乐。
- 补充用途回退、显式绑定、自动候选、行布局及隐藏后音乐测试。

## 1.8.2 — 2026-10-01

- 展开/收起文字按钮平时隐藏，悬停主坐骑图标时显示。
- 鼠标离开后延迟 0.45 秒隐藏，移动到控制钮或返回图标时取消隐藏，方便跨越间距点击。
- 保留中键切换与战斗延后逻辑，隐藏控制钮不影响已展开的安全按钮。
- 补充悬停、移出、重新进入、战斗后隐藏状态的离线测试。

## 1.8.1 — 2026-10-01

- 快捷按钮展开/收起改为图标外独立文字按钮，增大点击区域并显示扩展条目数量。
- 横向布局控制钮位于主图标上方，纵向位于右侧；展开和收起时位置不跳动。
- 支持中键点击主坐骑图标切换扩展按钮，不触发召唤坐骑。
- 战斗中明确显示「待展开 / 待收起」，脱战后生效；再次点击取消等待。
- 同步设置中的收起状态与悬停提示，补充点击、战斗延后、布局和显隐离线测试。

## 1.8.0 — 2026-10-01

- 重整坐标喊话、快捷按钮、光环/宠物提醒、嗜血/战复监控设置，按常用任务拆分分页。
- 坐骑五种用途独立子页，显示对应组合键；扩展内容与外观布局分离。
- 提醒器的高级法术识别、监控的循环音乐参数单独收纳；真实喊话与本地测试明确区分。
- 提取共享分页组件，选中页增加主题色指示条，保留循环助手设置及现有配置。
- 坐标与快捷按钮缩放改为百分比输入，兼容原倍率存档；长状态提示预留多行高度。
- 增加分页、坐骑绑定隔离、旧倍率存档兼容测试；原四模块设置以外代码保持不变。

## 1.7.1 — 2026-10-01

- 新增「锁定后隐藏背景与边框」开关，解锁后恢复背景，不影响技能及冷却显示。
- 新增 50%–200% 整体百分比缩放，默认 100%；按缩放后的可用屏幕宽度自动换行。
- 保留原有配置，补充锁定背景、主题切换与缩放边界离线测试。

## 1.7.0 — 2026-10-01

- 移除仅惩戒显示限制，屏上自动匹配当前角色专精；未选专精时隐藏。
- 编辑器增加职业与专精选择，每个专精独立保存六套方案；编辑对象与实际显示分离。
- 惩戒素材仅在惩戒档预置，其他专精默认为空；保留冷却、关闭按钮、鼠标提示及分页。
- 非破坏性迁移旧六套方案并保留备份，支持恢复到所选专精空槽，不覆盖已有配置。
- 新增自动切换、跨职业编辑隔离、无专精状态和幂等迁移离线测试。

## 1.6.1 — 2026-10-01

- 循环助手设置改为三个主 Tab，方案编辑内提供六套方案切换，不再堆叠成长页面。
- 未锁定卡片增加单条关闭按钮，仅取消显示、不删除方案；设置勾选同步更新。
- 未锁定时技能图标支持原生技能提示、从图标拖动整条；锁定后继续完整鼠标穿透。
- 新增分页、关闭/恢复、提示与锁定交互的离线测试；保留既有配置与位置。

## 1.6.0 — 2026-10-01

- 新增循环提示助手：三套惩戒骑素材预设、六套可编辑方案、独立显示开关。
- 图标原生冷却圈与倒计时、可读取的充能数；兼容 12.x DurationObject，避免运算受限值。
- 卡片支持独立拖动、锁定穿透、大小/换行/透明度、名称开关与明暗主题。
- 首页支持五模块与滚动；新增解析、显示、冷却等离线测试。
- 保留原有四模块逻辑与配置；不自动施法、不做下一技能推荐。

## [1.5.0] - 2026-10-01

### 新增
- 独立工具箱工作台：左侧导航、首页功能卡片、模块状态及快捷设置入口。
- 浅色 / 深色主题切换、角色级主题与窗口位置记忆、窗口自适应缩放。
- 配置窗口战斗锁定遮罩及 Lua 5.1 离线界面构建测试。

### 变更
- 保留四个模块原有设置与安全执行逻辑，统一卡片、按钮、输入框和细滚动条外观。
- 修正长复选框说明的折行间距，提高单行输入框可读性。
- `/bm`、小地图和系统设置入口打开同一个工作台，避免重复创建模块设置控件。

# 更新日志

本文件记录白描工具箱的版本变更。格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)。

## [1.4.0] - 2026-09-26

### 新增
- 快捷按钮：**展开 / 收起扩展按钮**。有扩展按钮时，主按钮生长方向那条边上会出现一个小箭头，
  点一下就把那排扩展按钮收起（只藏按钮、不清配置），再点展开；箭头方向随状态翻转
  （收起时指向生长方向＝“点我展开”，展开时指回主按钮＝“点我收起”）。
  - 设置页「扩展按钮」区新增「收起扩展按钮」勾选；命令 `/qm collapse`、`/qm expand`、`/qm toggle`。
  - 小箭头是普通按钮（非安全框），战斗中也能点：会立即翻箭头，那排安全按钮则等脱战后再真正显隐
    （安全框的显隐在战斗锁定期被系统禁止，沿用既有的“脱战自动补”机制）。

### 修复
- 坐标喊话：**测距触发 `ADDON_ACTION_BLOCKED`（IsItemInRange）刷屏 BugSack**。12.x 里
  `C_Item.IsItemInRange` 这类测距接口可能是受保护函数，从插件（非硬件事件）路径调用会被系统
  拦截；这不是 Lua 报错，外层 `pcall` 拦不住，0.1s 一次的刷新会把它刷成一长串。现在监听
  `ADDON_ACTION_BLOCKED`，一旦发现本插件“刚发起测距、随即被拦”，就停用测距兜底并按客户端
  版本持久化：本次登录不再重试，换游戏版本才自动再探一次。距离显示退回“未知区间”（0-100 码），
  坐标 / 移速不受影响。

## [1.3.1] - 2026-09-22

### 修复
- 快捷按钮：扩展按钮在副本 / 大秘境里报错
  `bad argument #1 to 'SetCooldown' (… Secret values are only allowed during untainted execution)`
  —— 12.x 在受限内容里会把冷却值变成“秘密值”，插件不能再把 start / duration 直接喂给
  `SetCooldown`。现在改成分路：法术优先走 `C_Spell.GetSpellCooldownDuration` 返回的
  DurationObject（由引擎自己解析，插件不碰数值），对象通道不可用时退回数值通道、且先判
  `issecretvalue` 再比较；物品 / 玩具没有对象通道，秘密环境下宁可不画冷却圈也不报错。
  顺带用 `isActive`（NeverSecret）当闸门，不在冷却时直接清圈，不再无谓重画。
- 快捷按钮：按**名称**填背包物品（`物品:xxx`）永远识别失败 —— 12.x 的容器函数在
  `C_Container` 命名空间，代码却写在 `C_Item` 上，恒为 nil。现在按 `C_Container` → 全局函数
  依次探测。

## [1.3.0] - 2026-09-22

### 新增
- 快捷按钮：`/qm diag` 控件自检 —— 把设置页关键控件（三个按钮 + 配置输入框）上每个 FontString 的
  **文本 / 字体 / 标记 / 阴影 / 行距 / 个数** 打出来，用来定位"字被画了两遍"这类问题
  （正常应当每个按钮只有 1 个 FontString）
- 快捷按钮扩展按钮：**扩展按钮**——设置里每行输入一条技能 / 玩具 / 物品，会在主坐骑按钮旁按选定方向
  （上 / 下 / 左 / 右，默认向右）长出一排与主按钮同尺寸（44×44，缩放跟随）的按钮，
  带冷却圈与悬停提示，点击直接使用：
  - 写法支持前缀 `技能:` `玩具:` `物品:`（或 `spell:` `toy:` `item:`），后接 ID 或名称；
    省略前缀时纯数字按 技能→玩具→物品 依次识别，纯名称先查玩具再查法术书（最后查背包）
  - 玩具可直接写物品 ID 或名称；网上常见的“使用法术 ID”（如 战团银行距离抑制器 法术 460905）
    会按同名玩具自动识别成玩具，避免填了 ID 却点了没反应
  - 施法 / 用玩具 / 用物品都是受保护动作，插件不能直接调用（CastSpellByID / UseToy /
    UseItemByName 都会被拒），因此按钮继承 SecureActionButtonTemplate，用 `type` 配合
    `spell` / `toy` / `item` 属性交给安全系统执行
  - 安全属性只能在非战斗锁定下写入：战斗中改动会挂起，脱战后自动补上（设置页有状态提示）
  - 玩具 / 技能数据变动、登录切换会自动重新解析（同名玩具未收集时只能显示为法术按钮）
  - 按钮与主按钮视觉一致：图标铺满整格 + 同样的边缘裁切，逐格串锚、间距 6（不再出现
    “离主按钮一个按钮宽”的缝），悬停用 HIGHLIGHT 层白色高亮
  - 也能填**快捷动作**（受保护动作，走安全按钮的 `macro` 属性，与本机 EllesmereUI 处理
    /logout 的做法一致）：`小退`（/logout，回到角色选择）、`退组`（/run C_PartyInfo.LeaveParty()）、
    `重载界面`（/reload）、`退出游戏`（/quit）；支持别名（登出/离队/重载…）和 `动作:小退` 前缀写法

### 优化（使用体验）
- 设置界面：**修掉长说明压住下一个控件的问题** —— 构建设置页时面板还没布局好，
  `GetStringHeight()` 会把折行文字当成一行、预留高度不够；现在按「行宽 / 字号」再估一次折行数取较大值
  （宁可多留白也不压住控件），所有模块的长说明都受益
- 快捷按钮：设置里的说明/诊断**不再往聊天频道刷字** —— 「检查配置」「详细说明」以及输入框的写法说明
  都改成**悬停提示框**（悬停或点击即显示）；只有你自己敲 `/qm check`、`/qm help` 才输出到聊天框
- 快捷按钮：文案跟功能对齐 —— 模块简介、主按钮悬停提示、设置区标题都补上了"快捷动作"及按钮名单
- 快捷按钮扩展按钮：**按钮下方可显示短名**（动作名 / 名字前几个字），按钮多了不用悬停也能分辨；
  设置里可关（默认开）
- 快捷按钮扩展按钮：短名默认 **2 个字**、**截断后不加省略号**（标签更干净、宽度完全可预期）——
  中文一个字宽≈字号，2 个字在「按钮 44 + 间距 6 = 50px」的槽里余量充足；字数上限做成设置项（2–6 可调）。
  默认值改放代码里兜底（不再写进存档），并把上一版误回填的默认值 3 一次性清掉——
  真想用 3 个字，设置里把滑块拖回去即可
- 快捷按钮扩展按钮：新增行尾 `#短名` 自定义标签（如 `玩具:216665 #银行`、`退组 #退队`），
  不受字数上限限制；「填入示例」也已按新写法给样例
- 快捷按钮：每个用途的坐骑**可以直接填名字或 mountID**，不必再"先骑上目标坐骑再抓取"；
  填了没匹配到的名字会在设置页直接标红提示（和扩展按钮的状态行同一套路）
- 快捷按钮设置页瘦身：扩展按钮的长说明移到「详细说明」按钮 / `/qm help` 按需打印，页面只留两行要点
- 工具：`tools/publish_github.ps1` 与 `tools/fix_github_mojibake.ps1` 里的版本号更新到 1.3.0（发布用）
- 快捷按钮扩展按钮：动作图标换成**逐一目视验证过画面**的贴图 —— 小退=炉石、退组=一队人、
  重载界面=齿轮、退出游戏=传送门（之前退组用的是"离开队伍"法术的图，实际是个齿轮）
- 快捷按钮扩展按钮：新增 `@图标ID` 语法（法术或物品 id 都行），例如 `退组 @135824` 随时换图标；
  指定的 id 取不到时会回落到该动作的默认贴图，不会变成隐形按钮
- 快捷按钮扩展按钮：新增「检查配置」按钮与命令 `/qm check`，逐行告诉你每行认成了什么、
  哪一行没识别（附怎么改）；设置页新增「填入示例」一键写入示例配置（框非空时不覆盖）
- 快捷按钮扩展按钮：单人点「退组」会提示「当前没有队伍」，不再像"按钮坏了"
- 嗜血/战复监控：小队里读不到共享池时显示「战复：?」，不再把"读不到"说成"没有战复"

### 文档
- README 补上「快捷按钮 · 示例配置（可直接复制）」：扩展按钮的每行写法（技能 / 玩具 / 物品 / 快捷动作）、
  `@图标ID` 与 `#短名` 用法、各用途坐骑填法、常用命令表；并写明"玩具的使用法术 ID 会按同名玩具识别"
- 发布脚本：每次发布都会刷新 GitHub 的 **About（描述 + 主题）**，Release 支持"已存在就更新"，
  重复发布不再报错；顺带修掉 release 正文中文编码导致 "Problems parsing JSON" 的坑

### 修复
- 设置界面：**多行输入框那条滚动条没藏掉**（截图里输入框右侧那两个金色圆钮）—— 上一版只按
  "Slider 里的 Button"去藏，模板结构一变就漏。现在改成「滚动框里除 EditBox 以外一律藏掉」，
  不管它是什么类型；滚动条没了就**用滚轮滚**（EditBox 默认不吃滚轮，已补上）
- 设置界面：**中文行距太紧、相邻两行贴着，看着像"字叠在一起"** —— 正文（`L:Text`）与多行输入框
  都加了 2px 行距（`SetSpacing`，你机器上多个插件在用这个 API），高度估算同步按 18px/行算
- 设置界面：按钮文字去掉**字体阴影与 OUTLINE/THICK 之类标记** —— 深色卡片底上这些只会让字发虚、
  像"重影"
- 设置界面：多行输入框刷新内容后会把滚动位置留在末尾，**第一行常被截成半行**、压在下一行上；
  现在内容一变就自动滚回顶部；输入框加高到 110
- 坐标喊话：**路点失败会连累整条喊话**——`C_Map.SetUserWaypoint` 在部分地图/副本里会失败，原来是
  直接中断，消息根本发不出去。现在路点两条调用都走 pcall：落点失败只是 `{waypoint}` 变空，消息照发
- 坐标喊话：目标名（`UnitName`）在 12.x 也可能是“秘密值”，原来直接拼进模板会报错 → 读不到就自动省略 `{target}`
- 坐标喊话：射程库（LibRangeCheck）报错时不再拖垮整行刷新，改为退回内置射程表；近档物品失效时
  显示 `<40码` 而不是误导性的 `0-40码`
- 坐标喊话：0.1s 刷新加了兜底，任何意外报错只提示一次，不会每秒刷 10 条 BugSack
- 坐标喊话 / 快捷按钮：模块被总开关关掉后不再空收事件（目标变化、修饰键、上下马等）；
  重新启用时会正确补回（Core 重新启用只调 OnToggle，不调 OnEnable）
- 嗜血/战复监控：**武僧等没有战复的职业也显示「战复 1」**——共享池的兜底逻辑把「不在冷却」
  当成 1 次战复来算，但 `C_Spell.GetSpellCooldown(20484)` 对**没学复生的人同样有数据**，
  于是自己完全不会战复时也凭空算出 1 次。现在共享池**只认充能**（`GetSpellCharges`，与本机
  EllesmereUI / MRT 的读法一致）；自己职业的单发战复（代祷 / 灵魂石）也要先确认已学会；
  队伍里没人会战复时显示「战复：无」
- 快捷按钮扩展按钮：**动作按钮“看不见”**（小退/退组只有悬停提示、没有图标）——退组的图标
  写死了贴图名 `achievement_guildperk_havegroup_willtravel`，而该贴图并不存在（图标 CDN 返回
  404），WoW 对缺失贴图是**静默不加载**，按钮就成了「能悬停出提示、但看不见」的隐形按钮。
  现在动作图标改为按法术 id 在运行时取（`C_Spell.GetSpellTexture`；8690 炉石 / 148416 离开队伍 /
  225809 时间回溯 / 110911 离开载具，id 均取自当前补丁 DB2 SpellName），并带问号兜底图标，
  以后不会再出现隐形按钮
- 光环/宠物提示器：**射击猎一直被误报“没有宠物”**——旧逻辑靠“独来独往”天赋判断，但该天赋在
  **11.1.0 已被移除**，写死的 id 155228 永远匹配不到。现在改成两条：
  1) 射击专精（specID 254）直接豁免——射击从 7.0.3 起就是“不带宠物作战”的设计
     （官方补丁说明：Marksmanship hunters no longer fight with a pet），宠物只是可选项；
     设置里给了开关，想让它照常提醒可以关掉豁免
  2) “独来独往”法术 id 改为可维护的列表（默认 `155228,164273,295390`，后两个取自当前
     DB2 SpellName(zhCN) 里名为“独来独往”的条目），跟骑士光环 id 一样放进设置页可改
- 读不到专精信息时不会静默漏报：取不到 specID 就按“需要宠物”处理，宁可提醒
- 快捷按钮扩展按钮：**点击没反应**——安全按钮「注册的点击阶段」必须和 `useOnKeyDown`
  配对，之前只 `RegisterForClicks("LeftButtonUp")` 未设该属性，安全系统按
  `ActionButtonUseKeyDown` 的默认值（按下）判定，阶段不匹配就直接返回且不报错。
  现按本机两个现役实现（TeleportMenu / EllesmereUIDataBars）的做法显式写死为
  「抬起 + `useOnKeyDown=false`」，并显式 `EnableMouse(true)`
- 快捷按钮扩展按钮：按钮没有紧挨主按钮（锚点已在前一个按钮的边上，却又按
  `i×(44+6)` 加了一次偏移，第 1 个整整远了 50px）→ 改为逐格串锚，间距 6
- 快捷按钮扩展按钮：看起来比主按钮小（图标内缩 3px + 卡片边框）→ 图标改为
  `SetAllPoints` + 与主按钮相同裁切，去掉边框皮肤

### 变更
- **模块改名：快捷坐骑 → 快捷按钮** —— 功能早就不只是坐骑了（还带技能 / 玩具 / 物品 / 小退·退组等自定义按钮）。
  模块 id 仍是 `quickmount`（存档键名不动，**设置与绑定都不会丢**），命令 `/qm`、`/bmmount` 照旧

## [1.2.0] - 2026-09-20

### 修复
- 快捷坐骑：右键行为与说明统一（右键=水下坐骑，Alt+右键=打开设置）
- 光环/宠物提示器：射击猎「独来独往」天赋下不再误报「没有宠物」
- 坐标喊话：战斗中通报给出明确提示（12.x 系统限制）
- 快捷坐骑：战斗中召唤给出明确提示
- 嗜血/战复监控：补充循环播放模式下声道生效范围的说明
- 设置控件：单个控件刷新出错不再连累后面的控件（表现为输入框/数值框空白）

### 新增
- 小地图按钮：左键打开设置、右键列出模块，可沿小地图边缘拖动，可关闭
- 命令别名：`/bmcoord` `/bmmount` `/bmremind` `/bmraidcd`，避免短命令被其它插件占用
- `/bm diag`：滑块自检，便于排查显示问题
- `/bm minimap`：切换小地图按钮显示

### 优化
- 设置界面控件全面扁平化：自绘滑块（拖动 / 滚轮 / 步进按钮 / 直接输入数值）、
  卡片式输入框与按钮、单行输入框改为「FontString 显示 + 点击编辑」，
  修复部分环境下 EditBox 文字不渲染的问题
- 坐标喊话：内容无变化时跳过重排，降低每 0.1s 刷新的开销
- 快捷坐骑：坐骑列表缓存，仅在获得新坐骑 / 上下马时重建
- 各模块初始化相互隔离（pcall），单个模块出错不影响其它模块
- 关闭模块时彻底停止其计时器与事件监听
- 默认值合并结果按会话缓存，避免每次取存档都递归合并
- 修复默认值合并标记被写入存档、导致后续新增默认键无法补齐的问题

### 变更
- 界面位置 / 锁定等布局设置改为**按角色保存**（首次自动从账号档迁移，老用户无感）
- 嗜血音乐「声道」与坐标喊话「喊话频道」由循环按钮改为下拉选择
- 音乐悬停试听不再向聊天框刷屏（点「试听」按钮仍有一次确认）

## [1.1.0] - 初始公开版本

- 坐标喊话、快捷坐骑、光环/宠物提示器、嗜血/战复监控四个模块
- 模块化框架：注册即接入设置界面，存档按模块隔离
- 自绘设置界面布局器（分组卡片、颜色选择、下拉、多行输入）
- 12.x 「秘密值」兼容处理（战斗中不可读的数据自动降级）
