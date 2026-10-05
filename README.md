# 同心结 PolyRomance — Sovereign Tower（君王之塔）模组

> 作者：**茹鸦reyalp** · 仓库：https://github.com/ReyalpWondery/Sovereign-Tower-PolyRomanceMod
>
> **免责声明**：本模组为玩家自制，与官方 WILD WITS GAMES 无关；仅供学习交流，使用本模组造成的一切后果（如存档异常）由使用者自行承担。

一个面向《Sovereign Tower》（Godot 4.6.2）的可拆装模组：全员同时恋爱、多次婚礼、解除圆桌人数与任务出战上限。

## 功能

**恋爱与婚姻**
- 全员同时恋爱：移除骑士间的多人恋爱嫉妒惩罚（不再掉好感/辞职）
- 多次婚礼：可为 Brunhilda / Gideon / Gwendan / Ligia 任意解锁婚礼仪式（自由时间触发，可重复）
- 绕过 Gideon 婚姻锁：已婚仍可在贵族叛乱事件中联姻（结局时自动还原状态，不影响结局文本）
- F8 模组菜单：查看/调整每名角色的浪漫值、一键恋爱圆满、解锁婚礼、调试按钮（全员入队+数值拉满）

**招募与出战**
- 圆桌人数上限解除：6/8/10 → 99
- 任务出战上限解除：每个任务最多 10 名骑士（仅在圆桌开放期间临时生效，结算前还原，不影响评分与存档）
- The Wolf 与人类 Rufus 共存：拦截治愈剧情中的强制离队
- 圆桌选择栏适配 12 人以上：自动补齐骑士头像并整体缩小排列（自动避开任务栏遮挡），F8 可切换滑轮窗模式

## 安装 / 卸载

1. 将 `PolyRomanceMod` 文件夹放入游戏目录（`sovereign_tower.exe` 所在目录）
2. 双击 `安装模组.bat`（需要 Python 3；首次安装自动备份原始 pck）
3. 启动游戏，按 **F8** 打开模组菜单
4. 卸载：双击 `卸载模组.bat`，从备份完整还原原版 pck

## 技术原理

- 游戏为 Godot 4.6.2（.NET 导出，逻辑全部在 GDScript），主资源包 `sovereign_tower.pck` 未加密
- 安装器（`tools/pck_tool.py`）解析 PCK format v3 目录，**追加**模组文件并重写目录，原始数据不动
- 通过替换两个 `.remap` 重定向入口脚本注入：
  - `panku_manager.gd` → `mod_entry.gd`（保留原 PankuManager 功能）
  - `character_manager.gd` → 修改版（圆桌上限 99）
- 恋爱/婚姻/出战逻辑全部在运行时通过信号与属性修改实现，不改存档结构
- 卸载 = 还原备份文件，零残留

## 目录结构

```
PolyRomanceMod/
├── mod_files/
│   ├── mod_entry.gd                  # 模组主脚本（autoload 注入）
│   ├── character_manager.gd          # 修改版角色管理器
│   └── *.remap                       # 入口重定向
├── tools/
│   ├── pck_tool.py                   # PCK 解析/补丁库
│   ├── install_mod.py                # 安装
│   └── uninstall_mod.py              # 卸载
├── 安装模组.bat / 卸载模组.bat
└── README.txt
```

## 兼容性

- 适配版本：v0.8.13（Godot 4.6.2）。游戏更新后请先卸载、更新、再重新安装
- 存档：不修改存档格式；卸载后已解锁的剧情状态仍保留（属于原版允许的状态）

## License

代码部分 MIT。游戏本身的素材与剧情内容的版权归 WILD WITS GAMES 所有。
