同心结 PolyRomance Mod  v1.3.2
====================================
作者：茹鸦reyalp
仓库：https://github.com/ReyalpWondery/Sovereign-Tower-PolyRomanceMod
免责声明：本模组为玩家自制，与官方 WILD WITS GAMES 无关；仅供学习交流，
使用本模组造成的一切后果（如存档异常）由使用者自行承担。

适用游戏：Sovereign Tower（君王之塔）v0.8.13 / Godot 4.6.2

功能：
【恋爱与婚姻】
1. 全员同时恋爱 —— 移除骑士间的"多人恋爱嫉妒惩罚"（原版中攻略新角色会降低其他
   已攻略骑士的好感，严重时导致骑士辞职离队）。安装后可自由攻略所有角色。
2. 多次婚礼 —— 模组菜单中可为布伦希尔德 / 吉迪恩 / 格温丹 / 莉吉亚
   任意解锁婚礼仪式（在自由时间触发，可重复、可多人）。
3. 绕过 Gideon 婚姻锁 —— 与 Gideon 结婚后，贵族叛乱事件中"迎娶贵族骑士"
   的选项仍然可用（菜单可开关；结局时自动恢复 Gideon 已婚状态，不影响结局文本）。

【招募与出战】
4. 圆桌人数上限解除 —— 原版圆桌最多 6/8/10 人（随章节），模组恒为 99，
   所有骑士均可招募入队（由模组内的 character_manager.gd 覆盖文件实现，始终生效）。
5. 任务出战人数上限解除 —— 原版每个任务只能派 1~4 名骑士，模组在圆桌开放期间
   临时把上限提升到场景最大值 10 人；圆桌结算前自动还原原版数值，
   任务成功率评分与存档完全不受影响（菜单可开关）。
6. The Wolf 与人类 Rufus 共存 —— 原版治愈狼形态会强制 The Wolf 离队，
   模组拦截该离队信号，两种形态可同时留在队中（菜单可开关）。
7. 圆桌选择栏适配 12 人以上 —— 原版只预置 12 个骑士头像，第 13 名起看不到也选不了；
   模组自动补齐头像并整体缩小排列（避开左侧任务栏与右下按钮的遮挡区）；
   也可在 F8 菜单切换为滑轮窗模式（选中者居中、滚动切换）。

【模组菜单（游戏内按 F8）】
- 查看每名可攻略角色的浪漫值，可 +3 / 一键圆满 / 解锁婚礼
- 上述第 3、5、6 项的开关
- 调试按钮：一键全员入队 + 数值拉满（供测试 UI/剧情用，请勿在正式存档上使用）

安装：
1. 把整个 PolyRomanceMod 文件夹放进游戏目录（sovereign_tower.exe 所在目录）。
2. 双击「安装模组.bat」（首次安装会自动备份原始 pck，约需一两分钟）。
3. 启动游戏，按 F8 打开同心结菜单。

卸载：
双击「卸载模组.bat」，游戏即刻恢复原版（模组不改动存档、不改动其他文件）。

注意事项：
- 模组原理是向 sovereign_tower.pck 追加模组文件并重定向两个入口脚本
  （PankuManager autoload 与 CharacterManager 脚本），原始数据全部保留在
  备份文件 sovereign_tower.pck.polyromance_backup 中。
- 游戏更新（pck 变化）后请先卸载再更新，更新后重新安装。
- 存档兼容：模组只改运行时数值与对话解锁状态，不写存档结构。
- 日志位于 %APPDATA%/Godot/app_userdata/Sovereign Tower (VS)/poly_romance.log

文件清单：
- mod_files/mod_entry.gd           模组主脚本（注入为 autoload）
- mod_files/character_manager.gd   修改版角色管理器（圆桌上限 99）
- mod_files/curved_hbox.gd         修改版圆桌头像弧形排列（>12 人自动缩小）
- mod_files/panku_manager.gd.remap / character_manager.gd.remap / curved_hbox.gd.remap  入口重定向
- tools/pck_tool.py                PCK 解析/补丁工具
- tools/install_mod.py / uninstall_mod.py  安装/卸载逻辑
- 安装模组.bat / 卸载模组.bat       一键脚本（需要系统装有 Python 3）
