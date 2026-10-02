# 白描工具箱：CurseForge 发布核查与填写清单

核查日期：2026-10-03（Asia/Shanghai）  
项目：白描工具箱 / BaimiaoToolbox；面向 World of Warcraft 正式服，中文 UI，代码许可证 MIT。

## 1. 结论与研究边界

- **网站项目名使用英文 BaimiaoToolbox；summary 与 description 使用英文，若另附中文则放在英文之后。**这是网站内容要求，不等于插件必须实现英文 UI。[S1][S2]
- **预览截图由用户在游戏内自行截取，本资料不代做截图，也不建议跳过用户计划上传的实机图。**创建指南对普通 mods 的 Additional Images 为可选，但审核政策对 visual mods 要求准确的游戏内样图。用户提供真实界面截图即可避免把离线示意当实机；项目图标另见下一项。[S1][S2]
- **项目图标（Logo / Avatar）不是预览截图，仍需准备。**最新审核政策要求 400×400，不能是纯色、NSFW 或侵权图；提交指南推荐原创 PNG。仓库现有猫图标是游戏内用的 128×128 TGA，不能直接当作符合上述网站规格的文件，其来源/授权亦未证实。[S1][S3]
- **没有必需第三方运行依赖，但不宜笼统写“完全没有可选集成”。**TOC 声明 LibSharedMedia-3.0 为 OptionalDeps；代码在库缺失时降级。队友钥石需要兼容消息或队友分享链接，不能凭空读取队友背包。平台 required / optional / embedded 关系须按实际依赖填写，Required 会触发客户端下载。[S2][S4][S8]
- **首个正式文件建议选择 Release、非 Experimental 项目；项目和文件均要通过审核。**不要把保存项目资料、项目 Approved 或 GitHub 已发布等同于 CurseForge 已可下载。[S2][S4][S5]
- **版本建议：Retail + 12.1.0，仅限后台有该选项且用户实际游戏验收通过。**本机 exe 版本号只是安装版本证据；TOC 中所有 Interface 值都不是实测保证。文件 flavor 和 supported versions 由作者正确标记，不声明 Classic 支持。[S2][S7][S9]

### 方法与限制

通过匿名网络 GET 阅读下列 CurseForge 官方帮助正文与 Blizzard 官方政策；并再次直接核对核心审核政策的英文、图标、外部下载、截图及音频要求。GitHub 发布由本次任务完成，另以匿名下载复算发行包 SHA-256。没有登录或操作 CurseForge，也没有生成预览截图。

CurseForge 公开分类页 https://www.curseforge.com/wow/addons 的直接请求返回 HTTP 403；未进入登录后的创建表单。因此**具体分类枚举、名称占用、字段长度限制、当前可选 game-version 列表没有独立确认**。本文不伪造上述信息。帮助文档年代不同、个别段落互相冲突，见第 5 节；以最新政策、实际表单校验和审核反馈交叉核对，不承诺审核时长或通过结果。

## 2. 当前发布物与仓库事实（不是平台政策）

| 项目 | 核对结果 / 证据性质 |
| --- | --- |
| 发布代码提交 | v1.9.14 标签指向 40867ccd70fd1ca332118b433484155dc335d885。发布后已 pull 用户上传预览图和 README 的提交 64b4a73 / a5f2df6；未移动版本标签或覆盖已发布附件。 |
| GitHub 进度 | v1.9.14 已正式发布；公开 Releases API 返回 draft=false，latest=v1.9.14，附件匿名下载 HTTP 200。 |
| CurseForge 进度 | 本次仅准备资料，未代用户创建项目或上传。用户账号内是否已有草稿未查询。 |
| 版本 | [BaimiaoToolbox.toc](../BaimiaoToolbox.toc) 的 Version 为 1.9.14；Interface 为 120000, 120001, 120005, 120007, 120100。 |
| 本机客户端 | 只读 E:/World of Warcraft/_retail_/Wow.exe 的 VersionInfo：FileVersion=12.1.0.69933；ProductVersion=Version 12.1.0.69933。没有据此宣称已运行客户端验收。 |
| 语言与入口 | [README](../README.md)、TOC 和模块：中文 UI，/bm 或小地图按钮打开工作台；模块独立开关；功能配置账号共享，位置/锁定按角色保存。 |
| 依赖 | TOC 无 RequiredDeps / Dependencies 声明，有 OptionalDeps: LibSharedMedia-3.0；[RaidCooldowns.lua](../Modules/RaidCooldowns.lua) 的 GetLSM / ResolveSoundFile 做缺失处理，没有把该库打包。 |
| 代码许可 | [LICENSE](../LICENSE) 为 MIT，Copyright (c) 2026 白描 (Lianzy-Baimiao)。这不单独证明第三方图片或音频的权利来源。 |
| 当前媒体 | media 目录实际仅有 cat_icon.tga；读取 TGA 头得到 128×128、24 bpp。未在已读 README / LICENSE / 相关说明中找到足以确认猫图版权来源的材料。 |
| 音频调整 | [CHANGELOG](../CHANGELOG.md) 与 [raid-music.md](raid-music.md)：当前版本移除私人音频及原内置曲目注册/回退，保留共享声音和自定义路径能力。 |
| 历史状态 | 已核实公开 GitHub releases 仍保留 v1.9.8 及更早原包，不改历史。当前文件删除不等于旧提交、旧包、用户旧安装中的副本消失。 |

### 已发布 ZIP 的最终记录

以下是本次任务实际发布与校验的记录；已从公开下载地址回读附件并重新计算 SHA-256。

- Release：https://github.com/Lianzy-Baimiao/BaimiaoToolbox/releases/tag/v1.9.14
- 下载：https://github.com/Lianzy-Baimiao/BaimiaoToolbox/releases/download/v1.9.14/BaimiaoToolbox-1.9.14.zip
- 文件名：BaimiaoToolbox-1.9.14.zip
- 大小：195705 字节；22 个文件（不计目录条目）。
- SHA256：845526af256617cdaa1b10d9045b3ba405798ccb041c7c20aeb4daf22271401b
- GitHub 上传 digest 与本地摘要一致；匿名下载 HTTP 200，下载内容的 SHA-256 亦一致。此处记录的是**已发布最终包**，不是 CHANGELOG 状态修改前的临时包。用户后来更新的 README 预览图仅在 main 分支，不在这个不可变的发行附件内；不要为文档变动悄悄覆盖同版本附件。

**以上 GitHub release / 下载链接仅用于本仓库的发行核对，不要复制进 CurseForge 项目说明作为外部下载入口。**官方禁止 external download links；专用 Source 和 Issues Tracker 字段是另一回事，见第 7 节。[S1][S3]

## 3. 创建项目：字段逐项填写

官方创建入口：https://authors.curseforge.com/#/projects/create/choose-game 。以下是将来由用户操作的清单，本次没有访问登录流程或创建项目。[S2]

“政策要求”指明确的内容/审核规则；“官方流程”指帮助文章列出的字段与步骤，不表示已实测当前表单的每一个必填星号；“建议”是针对本项目的选择。

| 字段 | 本项目填写 / 操作 | 要求、依据与注意 |
| --- | --- | --- |
| Game | World of Warcraft | 官方流程：选游戏后显示相应字段。不要选其他游戏。[S2][S3] |
| Name / Title | **BaimiaoToolbox**（推荐）；备选 Baimiao Toolbox | 政策：名称用英文；不得夹带游戏名、class 名称、游戏/文件版本等技术信息。创建指南要求名称独特，重名会被拒。不要填“白描工具箱”、颜色转义码或“BaimiaoToolbox WoW Retail 1.9.14”；具体名称占用尚未核实。[S1][S2] |
| Summary | 第 8 节任选一条英文短句 | 政策：清楚概括功能，英文在其他语言之前；官方偏好一句话，避免直接复制 description。没有在已读一手文档中找到统一的字符上限，按表单校验裁剪，不编造“必须 N 字符”。[S1][S3] |
| Description | 粘贴第 8 节英文 Markdown，预览排版 | 政策：清楚解释实际增加/改变的功能，不能只写“很多小工具”，不能用 GitHub README 链接替代本站说明；需语法正确，英文先行。中文 UI 限制在首段显著披露。[S1][S2] |
| Project License | MIT / MIT License（按表单实际名称） | 官方流程：从下拉框选许可证，必要时可用 Custom；本项目应与 LICENSE 一致。如无 MIT 项才考虑粘贴完整 MIT 文本到 Custom，不能凭空换成 All Rights Reserved。代码 MIT 不免除素材权利和署名义务。[S2][S3][S1] |
| Class / 项目类型 | Addons / Add-ons（若表单提供；以表单为准） | 官方流程：Class 是根分类，会影响文件类型及客户端支持；本项目是 addon，不是整合包、材质包或库。[S2] |
| Main category | 建议 Miscellaneous，名称以表单为准 | 官方流程：选能代表主要功能的类别，不靠无关分类引流。此具体枚举未获官方表单确认，见下表。[S2][S3] |
| Additional categories | 建议 Combat、Buffs & Debuffs、Chat & Communication；Map & Minimap 可选 | 官方流程：最多 4 个附加分类，可以不选；只选实际相关项。具体枚举未确认，不能把建议名称冒充官方必选项。[S2][S3] |
| Logo Image / Avatar | 单独准备有权使用的 **400×400 PNG**，不是截图 | 政策要求 400×400、非纯色/NSFW/侵权；当前政策提示避免 WebP。提交指南推荐原创 PNG、不要复用其他项目头像或泛用游戏 logo。未证实版权的猫图不能直接声称“原创 MIT”。[S1][S3] |
| Images / Gallery | **由用户上传自己截取的游戏内预览图** | 本资料不制作截图。图片应准确反映实际效果；icon 与 Gallery 分开准备。官方对 visual mods 有样图要求。[S1][S2] |
| Experimental | 常规公开发行建议不要勾选 | 官方：Experimental 不同步到 App，也不出现在网站搜索中；适合测试，但不是“审核已通过并公开发行”的替代方案。[S3][S4] |
| Allow Comments | 建议开启；或明确使用 GitHub Issues | 官方建议开放反馈渠道，而非要求必须使用某个评论系统。[S1][S3] |
| Source / Issues Tracker | 见第 7 节 URL | 官方支持外部源码站和外部 issue tracker；这些并非必须开通的新服务。[S3] |
| Donation Method | 暂留空 | 没有捐赠安排不需提供；若以后设置，使用后台支持的方式，说明页中的捐赠推广放底部，且不得在游戏内索捐或提供付费插件功能。[S1][S3][S10] |

### 分类选择依据（均为建议，具体选项以创建表单为准）

| 候选类别 | 对应功能 | 取舍 |
| --- | --- | --- |
| Miscellaneous（主类别） | 多个可独立开关的小工具，而非单一功能替代品 | 综合工具箱的保守主类别。 |
| Combat（附加） | 嗜血/战复状态、技能顺序卡片 | 不宣传自动战斗或实时最优施法推荐。 |
| Buffs & Debuffs（附加） | 缺失光环/宠物提醒、嗜血状态 | 比泛加不相关职业类别更贴近功能。 |
| Chat & Communication（附加） | 坐标喊话、手动邀请及小队信息 | 以表单确有该项为前提。 |
| Map & Minimap（可选第四项） | 坐标信息、小地图入口 | 相关性弱于地图增强插件；没有必要用满 4 个附加名额。 |

未确认本表枚举或当前是否存在“Utilities”“Dungeons & Raids”等替代项；不建议根据印象填写不存在的分类。选择有实质功能对应的项即可，官方并不要求用满四项。[S2][S3]

## 4. 上传文件：Retail、依赖与 ZIP

### 4.1 文件表单

| 字段 | 建议值 / 操作 | 官方依据 |
| --- | --- | --- |
| Upload file | 已发布的 BaimiaoToolbox-1.9.14.zip；实际上传前核对仍是最终包 | WoW 处理器检查真正的 .zip；通用创建说明上限为小于 2GB。不是把 .rar / .7z 改扩展名。[S2][S6] |
| Display Name | BaimiaoToolbox 1.9.14 | 此字段可选，用版本区分文件是建议；**网站项目标题不放版本，但文件名/显示名可以放**。[S1][S2] |
| Release Type | 游戏内验收通过后选 Release | Release 默认分发；Beta / Alpha 是测试通道，不应为获得默认分发而把未经验收文件伪装成稳定版。官方通道说明存在旧文档冲突，见第 5 节。[S2][S4] |
| Game flavor / Supported Version | **Retail + 12.1.0**，仅在后台有该选项且验收通过时选择 | 支持版本可多选，作者须正确维护 TOC 和文件标签；不选 Classic / Classic Era 或其他未测试版本。若表单通过版本选项隐含 flavor，而无单独 Retail 开关，则核对结果显示为 Retail。[S2][S7][S9] |
| Changelog | 第 8 节累积版本说明 | 政策要求说明相对上一版本的变化；本次是首次上 CurseForge，可同时标明 First CurseForge release 与 Changes since 1.9.8，避免把 1.9.14 当作只有最后一轮排版调整。[S1][S2] |
| Related Projects / Default Relations | 无 Required；LibSharedMedia-3.0 可选关系如需展示则匹配真实项目 | Required 会自动下载；项目级默认关系会应用到文件。不要填不存在的项目 slug/ID。[S2][S4][S8] |
| Release Options | 建议选审核通过后手动发布 / 延后发布（若表单提供） | 官方允许通过审核后自动上线或由作者另选发布时间；手动发布便于最终核对，但不代替审核。[S2][S4][S8] |

**版本证据的边界：**本机客户端 12.1.0.69933 支持把“12.1.0”作为当前验收目标；并不证明所有功能、其他语言客户端或所有 12.x 历史版本均可用。TOC 的 120000 / 120001 / 120005 / 120007 / 120100 是当前包的声明，不是 CurseForge 的 game-version ID，也不是测试报告。上传 API 的 gameVersions 使用平台 ID，文档中的示例 ID 不能拿来填写；本次不获取 token、不查询受认证的后台版本列表。[S7][S8]

### 4.2 零必需依赖，不等于零可选集成

- **Required Dependency：留空。**没有为加载本插件必须安装的第三方 addon；不把 EUI、AngryKeystones、MRT、DBM、BigWigs、WeakAuras 或开发测试环境 Python/lupa 列作必需依赖。依据为 TOC、[MythicPlus.lua](../Modules/MythicPlus.lua)、[PartyKeystones.lua](../Modules/PartyKeystones.lua) 及相关说明，而非平台对本插件的认证。
- **LibSharedMedia-3.0：可选。**[RaidCooldowns.lua](../Modules/RaidCooldowns.lua) 通过 LibStub 可用时读取已注册声音，无库时仍可运行；自定义声音需用户自己配置。本包不内嵌该库，也不附音乐。若平台上找到并确认对应项目，可以标 Optional Dependency；未确认前不用猜 slug/ID，说明文字足以披露，不要错标 Required 或 Embedded Library。平台允许这些关系类型。[S4][S8]
- **小队钥石：数据来源条件。**[party-keystones.md](party-keystones.md) 说明独立实现 LibKS / WA-KeyStGrList 消息，亦接收当前队友分享的钥石物品链接；不复制/内嵌对应第三方库。没有数据时“待同步”，并非所有队友装任意插件都保证互通。应写“compatible sharing”，不要写“automatically scans every party member's bags”。
- 游戏 TOC 中的 OptionalDeps、包里是否真的嵌入库、CurseForge 的项目/文件关系是三个核对对象。**不要只因为填了平台依赖就宣称 ZIP 已带库或游戏加载顺序已改变。**官方分别说明平台关系与 TOC 的加载职责。[S4][S7][S8]

### 4.3 WoW ZIP 的正确结构

官方 WoW Addon Processor 的原文：[S6]

> “Assure all Root items in the zip are folders”
>
> “At least 1 root folder contains a file of the form: ROOTFOLDER/ROOTFOLDER.toc”
>
> “name is case sensitive and must not be empty”

因此本项目应保持 **ZIP 根下是 BaimiaoToolbox/ 文件夹，里面是 BaimiaoToolbox.toc**。不要在 ZIP 根散放 TOC、README 或 LICENSE，不要加一层“版本号/源码仓库名”包装。源码平台自动生成的 Source code 压缩包不应未经检查就拿来替代整理好的发行包。[S6][S7]

已校验的 22 文件清单如下，12 个 Lua 均来自 TOC 加载表：

~~~text
BaimiaoToolbox-1.9.14.zip
└── BaimiaoToolbox/
    ├── BaimiaoToolbox.toc
    ├── Core.lua
    ├── Workspace.lua
    ├── Modules/
    │   ├── CoordShout.lua
    │   ├── Reminder.lua
    │   ├── QuickMount.lua
    │   ├── RaidCooldowns.lua
    │   ├── RotationGuide.lua
    │   ├── MythicPlusData.lua
    │   ├── PartyKeystones.lua
    │   ├── MythicPlus.lua
    │   ├── MarkerAssist.lua
    │   └── SmallTools.lua
    ├── media/
    │   └── cat_icon.tga
    ├── README.md
    ├── CHANGELOG.md
    ├── LICENSE
    └── docs/
        ├── mythicplus.md
        ├── party-keystones.md
        ├── party-tools-api.md
        ├── raid-music.md
        └── smalltools.md
~~~

- 算术：12 Lua + 1 TOC + 1 TGA + 3 根文档 + 5 docs = 22。
- 已校验该发行包不含 tests、previews 或音频；**本研究文件 curseforge-publishing.md 不属于上述 22 文件，不能为了这份资料擅自重打包已发布 ZIP**。
- 平台检查：ZIP 不应包含路径穿越条目（../）或黑名单文件；官方特别提示 __MACOSX / .DS_Store 可能被处理器拒绝。[S6][S4]
- 工程建议：继续用明确文件清单，排除 .git、缓存、备份、私人媒体；这不是断言所有这些名称都是官方黑名单。README / LICENSE / CHANGELOG 放在 addon 目录内，而不是 ZIP 根。
- **不要误套 Minecraft 的“zip contents directly / 不含 root folders”规则。**该条在 Minecraft 专节，而 WoW 专用处理器恰恰要求根目录项为文件夹。[S1][S6]
- **不要把 Sims 的“只允许功能所需文件、排除 txt instructions”原样套到 WoW。**那是 Sims 专节；已读 WoW 要求没有禁止随包附相关 Markdown 和许可证。本清单保留用户已确认的五份 docs，不增图、不删文档。[S1][S6]

## 5. 审核、可见性与发布顺序

### 将来由用户执行的操作清单

1. [ ] 先解决第 9 节的图标/素材权利缺口、确认实际客户端验收结果；不收集截图。
2. [ ] 在官方作者后台选 World of Warcraft，填写第 3 节字段，选择正常公开项目而非 Experimental，保存。[S2][S4]
3. [ ] 上传最终 ZIP 并填写版本、Release Type、changelog、依赖和 Release Options；新项目至少有一个文件才会进入项目审核。[S2][S5]
4. [ ] 等项目及文件审核。New 不代表公开；项目 Approved 后仍须文件 Approved。文件 Under Review 的流程可能要先等项目页面审核。[S5]
5. [ ] 收到 Changes Required，按通知修改并重新提交，进入 Changes Made。遇到 Under manual review，不反复重传；遇到拒绝先看理由，必要时联系支持，**不要删除并重建项目试图绕过审核**。[S1][S5]
6. [ ] 如果选择了手动/延后发布，通过审核后再确认发布时间；核对公开页面、下载与客户端 Retail 分支是否正确。审核通过和“已到设定发布时间”是两个条件。[S2][S4][S8]
7. [ ] 后续版本更新只发布有实际变化的文件并写 changelog；不得靠重复上传、无功能变化或刻意拆碎更新来刷曝光。[S1]

### 不应隐藏的官方文档差异

- **App 是否需要 Release：**2024 创建指南说至少一个 Release 才同步 App；2026-07-09 的文件类型文章专门写新项目经批准的 Release **或 Beta** 可同步，只有 Alpha 的项目仍可在网站存在。但同一篇前面的 Release 段落仍残留“必须至少一个 Release 才在网站和客户端可用”的旧式表述。不能断言“Beta 永远不可见”或“Alpha 绝对不能上网站”。本项目计划稳定公开发行时用经验证的 Release，可避开这处冲突；测试版可见性若实际需要则再问官方。[S2][S4]
- **图标尺寸：**提交建议写“至少 400×400，较大会缩小”，较新的审核政策写“all avatars need to be 400x400”。因此直接提供恰好 400×400 PNG，兼顾两者；不要承诺 128×128 TGA 可用。[S1][S3]
- **Experimental 不是秘密存储：**官方只明确不参与 App 同步和网站搜索，并未承诺链接绝对私密。不要把“不在搜索中”当作保密或撤回既有下载副本的机制。[S4]
- **审核没有本文可保证的 SLA。**WoW FAQ 给出工作时段/排队说明，但不是针对这个项目的批准承诺，不能据此保证某小时内上架。[S9]

## 6. 不要写进上架宣传的错误承诺

以下基于本仓库实现和验收边界，不是新的平台禁词清单：

- 不写“English UI”“fully localized”或“支持所有客户端语言”。只提供英文网站说明，不代表实现了英文界面。
- 不写“支持所有 12.x / Classic”。版本标签按实际验收选择。
- 不写“实时读取所有队友钥石/背包”。消息和链接来源可能缺失或过期。
- 不写“自动打标、自动邀请、智能循环、一键自动输出”。[RotationGuide.lua](../Modules/RotationGuide.lua) 按职业/专精保存用户自定义顺序，预置三套惩戒骑方案，是可编辑静态顺序卡片/被动冷却展示，不是动态 DPS 循环引擎，不替玩家施法；[smalltools.md](smalltools.md) 中邀请与标记由用户点击，受权限和战斗限制。
- 不写“自带嗜血音乐”“全部素材原创 MIT”“猫图已获授权”。当前包没有音频；图片版权尚待证明。
- 不写“所有 UI、taint、安全动作和第三方插件组合均已实测”。CHANGELOG 的离线回归不替代真实客户端测试，也不是 CurseForge/Blizzard 的认证。

## 7. 源码、Issue URL、外链与捐赠

### 可直接填写的功能链接

~~~text
Source:
https://github.com/Lianzy-Baimiao/BaimiaoToolbox

Issues Tracker:
https://github.com/Lianzy-Baimiao/BaimiaoToolbox/issues
~~~

链接与仓库 origin 一致；GitHub API 已确认仓库公开、has_issues=true、license=MIT。没有创建测试 issue。官网建议开放沟通渠道，支持外部源码仓库和外部 issue tracker。[S1][S3]

### 外链边界

1. **政策要求：不放外部文件下载链接。**因此不把 GitHub releases/latest、release asset、网盘/镜像下载按钮放进 CurseForge description；不能直接整段复制含 GitHub 安装包链接的 README。[S1]
2. **允许的功能字段：Source / Issues。**官方专门支持源码和外部问题跟踪，并非禁止一切 GitHub 链接。使用仓库首页和 issues，不用直链 ZIP 冒充源码链接。[S3][S1]
3. **政策要求：主要功能/使用说明要在 CurseForge 内完整呈现。**私人站点、跨站作品集/托管推广、捐赠及推广横幅应放 description 底部且大小合理；政策允许无推广内容的功能/依赖徽章放顶部。本文保守地把 Source / Issues 也放说明末尾，不放任何推广徽章。[S1]
4. **不需要捐赠就留空。**若以后设置，官方有 Donation Method 字段；说明页中的捐赠/合作内容放底部，避免推广捐赠者专属付费功能。[S3][S1]
5. **WoW 另受 Blizzard 规范约束：**插件免费、代码公开可读不混淆、不能带广告或在游戏内索捐；索捐只限插件网站/分发站。不能把支付作为下载、功能解锁或访问插件的条件。CurseForge 同时要求项目遵守游戏方 EULA/ToS。[S10][S1]

## 8. 可直接粘贴的英文候选

以下说明对应当前 1.9.14。它们刻意不含外部下载、未确认的素材授权、中文项目标题、Classic 承诺或“已通过官方审核”字样。图标权利若需署名，必须在取得真实材料后补到说明末尾；不要发明署名。

### Title

推荐：

~~~text
BaimiaoToolbox
~~~

备选（仅在名称可用且用户偏好带空格时）：

~~~text
Baimiao Toolbox
~~~

### Summary

推荐（概括功能；语言限制在 description 首段披露）：

~~~text
Modular tools for Mythic+, quick actions, reminders, coordinates, and party utility.
~~~

备选（在列表中即披露中文界面）：

~~~text
A Chinese-language toolbox for Mythic+, quick actions, reminders, and party utility.
~~~

### Description（Markdown）

~~~markdown
BaimiaoToolbox brings a set of independently configurable utility modules to World of Warcraft Retail.

**Language:** The in-game interface is currently available only in Simplified Chinese. There is no English UI translation; this English page explains the addon's features and limitations.

## Features

- **Coordinates and sharing:** View coordinates, movement speed, and target distance, with customizable coordinate-sharing messages.
- **Quick actions:** Organize mount shortcuts and buttons for spells, items, toys, and common actions.
- **Aura and pet reminders:** Display customizable reminders for missing auras or pets.
- **Bloodlust and battle resurrection:** Track available status information and battle-resurrection charges. Optional sound playback can use media already registered by other addons or a user-configured sound path. No music files are included.
- **Configurable spell-sequence reminders:** Save custom spell sequences by class and specialization, with passive cooldown cues and three Retribution Paladin presets. These are sequence reminders, not a dynamic DPS rotation engine; there is no automatic casting.
- **Mythic+ information:** View dungeon results, weekly records, Great Vault progress, shared party keystones, and shortcuts for learned dungeon teleports.
- **Party utilities:** Use manual guild-invite and character-selection menu actions, target and world markers, ready checks, and native group countdowns, subject to the game's permissions.

## Getting started

Install the addon for your Retail game instance. For manual installation, place the BaimiaoToolbox folder in World of Warcraft/_retail_/Interface/AddOns/ so that BaimiaoToolbox.toc is directly inside that folder.

Open the workspace with /bm or the minimap button, then enable the modules you want. Feature settings are shared across the account; frame positions and lock settings are saved per character.

When upgrading from version 1.9.8 or earlier, fully exit and restart the game so that the newly added files are loaded.

## Compatibility and limitations

- This release targets Retail, not Classic or Classic Era. Use the game versions listed on the file page.
- No third-party addon is required to load BaimiaoToolbox. LibSharedMedia-3.0 integration is optional and is not bundled.
- Party keystones require compatible addon sharing or a keystone item link shared by a current party member. The addon cannot directly inspect another player's bags, and unavailable data is not treated as an empty keystone slot.
- Some information may be unavailable because of game API restrictions. Protected actions, group permissions, and combat restrictions still apply; this addon does not bypass them.
- Music is optional and must be configured separately. This package contains no audio files.

## Support and source

Please report issues with the addon version, Retail client version, enabled modules, steps to reproduce, and any Lua error text.

Issue tracker: https://github.com/Lianzy-Baimiao/BaimiaoToolbox/issues

Source code: https://github.com/Lianzy-Baimiao/BaimiaoToolbox

Code license: MIT. See LICENSE in the addon package.
~~~

### Changelog（首次 CurseForge 文件，覆盖上一公开版 1.9.8 以来变化）

~~~markdown
## 1.9.14 — First CurseForge release

This release combines the updates made since the previous public version, 1.9.8.

### Added

- Party keystones in the Mythic+ panel, using compatible addon messages or keystone links shared by current party members.
- Manual guild-invite and character-selection actions in supported context menus.
- A marker toolbar with target markers, world markers, ready checks, and native group countdowns.
- Independent toolbar-row switches and an optional leader-only display setting.

### Improved

- A more compact workspace and settings layout, including side-by-side coordinate and utility options.
- Wider party-member names and better handling of long keystone titles.
- Clearer visual distinction between timed and overtime Mythic+ results.
- Combat-deferred toolbar layout updates and more consistent settings controls.

### Changed

- Removed the previously bundled private audio file and its built-in media registration and fallback. No audio files are included in this release.
- Preserved optional shared-media and custom-sound support; users must configure their own sound source.
- Simplified the README and retained existing user settings.

### Upgrade notes

- Retail only. The in-game UI is Simplified Chinese only.
- Fully exit and restart the game when upgrading from 1.9.8 or earlier because this release adds runtime files.
- Users already running the local 1.9.11–1.9.13 builds can reload the UI after updating.
- An old installation may still contain media/lust_ball.ogg. This version no longer uses it; you may remove that leftover file manually.
~~~

**发布前措辞检查（建议）：**“First CurseForge release”只在确实是该平台首个文件时保留；后续版本用对应增量变更。不要用官方政策引用或上述中文内部风险记录塞满面向玩家的 changelog；实际变化说明是审核要求。[S1]

## 9. 现存风险与仅需用户提供的缺失资料

### 必须先澄清 / 确认的资料

1. **项目图标与猫图权利。**需要一份符合网站规格的 400×400 PNG，以及其原创/许可来源；如果继续使用猫图，还需要能确认 media/cat_icon.tga 有权随包再分发的来源与必要署名。两者可以是同一设计的不同文件，但没有证据时不能默认。只补网站图标不能自动消除发行包中猫图的权利疑问；若需替换包内素材，另行由用户决定版本/重打包，不由本研究修改。[S1][S3]
2. **实际 Retail 12.1.0 验收结论。**需要用户确认当前包在该客户端的基本加载、/bm、常用模块及受保护操作可用；不用提供截图。若有未通过项，先处理或诚实选择测试发布范围，不能靠 TOC 数值当作全部版本已测试。[S2][S7]

### 不需用户重新提供的内容

- 项目中英文名称、公开仓库、MIT LICENSE、功能清单、源码 URL、Issue URL 候选、发行版本、最终 ZIP 清单/大小/SHA：已具备。
- 账号密码或 token：无需在对话中提供。用户在官方后台自行登录即可，本资料不要求凭据或旧历史清理。
- 预览截图：用户已决定自己实机截取，无需由助手制作；用户将自行添加至项目页面，与项目图标区分。[S1][S2]
- 捐赠链接、独立官网、宣传横幅：不打算使用就留空，不是此项目的缺失资料。[S3]
- CurseForge 的项目 ID、最终 slug、具体分类列表和版本列表：待用户实际创建/选择时产生或确认，不编造，也不要求现在先提供凭据。[S2][S8]

### 风险登记

| 风险 | 当前事实与处理边界 |
| --- | --- |
| 中文 UI 造成误解 | 英文网站说明不代表英文界面；候选 description 首段已披露。官方要求英文内容和准确功能说明，但未在已读条款中要求插件必须实现英文 UI。[S1][S2] |
| 猫图版权未证实 | 图像头只能证明尺寸/格式，不能证明作者或授权。MIT 文件不能自动给第三方素材授权；版权许可/明确许可及适当署名是审核要求。未证实不等于已判侵权，但也不能给“版权无风险”的结论。[S1] |
| 私人音频在旧公开历史/原包中可能仍可取得 | 当前包已删除，不代表历史已清理。GitHub Releases API 显示 v1.9.8 及更早附件仍公开保留；本研究未逐个下载检查，不逐一断言哪些旧包含哪段音频，但也不能说旧音频已不可见。未取得权利证明前不重传旧包、不写“全历史音频均已清除/已授权”。CurseForge 要求音乐拥有权或再分发权并署名；Blizzard 同样禁止未经授权分发版权音频。[S1][S10] |
| 老用户残留文件 | 覆盖安装不必然删除旧 media/lust_ball.ogg；当前代码不再使用它。英文 changelog 提醒用户可手动删除；本研究不删除用户安装或 Git 历史。 |
| 功能/安全限制宣传过度 | 静态技能顺序卡片不是智能施法；手动邀请/标记不绕过权限；钥石不直接检查他人背包；嗜血备用计时可能是推定。准确说明功能是审核要求，具体边界以仓库模块及 docs 为依据。[S1] |
| 离线测试被误称游戏实测 | 本次发版前已重跑 217 项离线回归及 12 Lua 语法检查；拉取 README 后调整图片测试，217 项再次通过。这些不等同于所有客户端、字体、受保护动作或插件组合实测。 |
| 包内 docs 链接到未打包 previews | smalltools.md 等仍可能引用 previews 下的布局示意；22 文件包排除了 previews，离线阅读会遇到缺图。这是文档体验问题，不是本研究认定的 WoW 审核硬性拒绝项。遵从不加截图的范围，不为补链接重打包。 |
| 截图准确性 | 用户自行提供真实游戏截图；不使用仓库的离线布局示意冒充实机。官方对 visual mods 有样图条件，AI 改造且可能误导的展示图需要明确披露。[S1][S2] |
| 文档和表单演进 | 分类页 403、未登录表单，不能保证具体枚举/字符限制；Beta 与 Release 可见性文字冲突已披露。实际提交前核对，不用社区猜测冒充现行官方规定。[S2][S4] |

**边界结论：**当前已有可填写的大部分文字与发行物资料；主要剩余输入是**有据可查的图标/素材权利**及**Retail 12.1.0 游戏内验收结论**。没有执行上架，不保证审核结果，也不擅自改写旧公开历史。

## 10. 官方来源与关键原文索引

以下链接均在本次研究中直接获取正文；“更新”是页面自身显示时间，不是本研究判断其每段内容都已全面更新。每项平台/游戏方规则在上文就近引用这些来源；仓库事实另链接本地文件，不冒充官方规则。

| 编号 | 官方文档；页面更新时间 | 可复查的关键原文 / 用途 |
| --- | --- | --- |
| [S1] | Moderation Policies；2026-09-08 | “Names must be in English.”；description/summary 的英文应先于其他语言；“All avatars need to be 400x400 pixels.”；“External download links for files are not allowed.”；“Files must include a change log…”；Licensed Music、Content Copyright、visual mods 样图及推广放底部。 |
| [S2] | Creating and Submitting a Project；2024-09-24 | Name、Summary、Description、License、Class、分类、Logo；“Additional Images…only REQUIRED for texture packs or sims projects, but not mods”；文件上传、2GB、版本、Required Dependency、审核与 Release Options。 |
| [S3] | Project Submission Guide and Tips；2024-12-23 | “minimum 400*400 px (1:1 scale) .png”；原创图标、最多四附加分类、反馈渠道、Donation Method、Source、Issues Tracker；功能页完整性与捐赠说明。 |
| [S4] | File & Project Types and Additional Fields；2026-07-09 | “A Release File or Beta must be uploaded and approved…”；仅 Alpha 项目网站可用；Default Relations、Experimental、文件状态、发布选项。保留与旧段落冲突，不擅自删掉例外。 |
| [S5] | Project Statuses 101；2024-09-24 | “It must have at least one file to be reviewed”；项目 Approved 后“once your file is approved as well”；人工审核勿重复提交。 |
| [S6] | CurseForge File Processor Errors - Per Game；2024-02-28 | WoW 专节要求 ZIP、根项全是目录、ROOTFOLDER/ROOTFOLDER.toc；命名区分大小写；通用路径穿越/黑名单检查。 |
| [S7] | Multi-TOC for World of Warcraft Addons；2024-02-28 | TOC 父目录同名、Interface/flavor、作者负责正确标签；“When uploading the file you can tag which versions are supported”。本文未把该页链接的社区资料当作官方一手证据。 |
| [S8] | CurseForge Upload API；2026-09-27 | gameVersions 是平台版本 ID；可选 relations；optionalDependency / requiredDependency / embeddedLibrary；isMarkedForManualRelease。这里只读取说明，未生成 token 或调用上传 API。 |
| [S9] | World of Warcraft Addons - FAQ and Troubleshooting；2026-07-07 | Retail / Classic / Classic Era 按实例安装；待审核项目可能搜索不到；flavor 不匹配警告。 |
| [S10] | Blizzard：UI Add-On Development Policy；官方帖 2018-11-19，内含 2009 政策 | “Add-ons must be free of charge.”；“Add-on code must be completely visible.”；“Add-ons may not solicit donations.”；网站索捐与游戏内索捐的区别；未经授权不能分发版权音频。 |

[S1]: https://support.curseforge.com/support/solutions/articles/9000197279-moderation-policies
[S2]: https://support.curseforge.com/support/solutions/articles/9000197241-creating-and-submitting-a-project
[S3]: https://support.curseforge.com/support/solutions/articles/9000199552-project-submission-guide-and-tips
[S4]: https://support.curseforge.com/support/solutions/articles/9000197242-file-project-types-and-additional-fields
[S5]: https://support.curseforge.com/support/solutions/articles/9000197905-project-statuses-101
[S6]: https://support.curseforge.com/support/solutions/articles/9000210425-curseforge-file-processor-errors-per-game
[S7]: https://support.curseforge.com/support/solutions/articles/9000209856-multi-toc-for-world-of-warcraft-addons
[S8]: https://support.curseforge.com/support/solutions/articles/9000197321-curseforge-upload-api
[S9]: https://support.curseforge.com/support/solutions/articles/9000198422-world-of-warcraft-addons-faq-and-troubleshooting
[S10]: https://us.forums.blizzard.com/en/wow/t/ui-add-on-development-policy/24534
