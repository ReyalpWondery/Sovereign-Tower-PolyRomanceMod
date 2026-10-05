#!/usr/bin/env python3
"""同心结 PolyRomance 安装器：备份原 pck 并注入模组文件。"""
import os
import shutil
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from pck_tool import patch_pck, Pck

MOD_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GAME_DIR = os.path.dirname(MOD_ROOT)
PCK = os.path.join(GAME_DIR, "sovereign_tower.pck")
BACKUP = PCK + ".polyromance_backup"

FILES = {
    "res://mods/poly_romance/mod_entry.gd": os.path.join(MOD_ROOT, "mod_files", "mod_entry.gd"),
    "res://mods/poly_romance/character_manager.gd": os.path.join(MOD_ROOT, "mod_files", "character_manager.gd"),
    "res://mods/poly_romance/curved_hbox.gd": os.path.join(MOD_ROOT, "mod_files", "curved_hbox.gd"),
    "res://systems/autoloads/panku_manager.gd.remap": os.path.join(MOD_ROOT, "mod_files", "panku_manager.gd.remap"),
    "res://systems/autoloads/character_manager.gd.remap": os.path.join(MOD_ROOT, "mod_files", "character_manager.gd.remap"),
    "res://scenes/roundtable/curved_hbox.gd.remap": os.path.join(MOD_ROOT, "mod_files", "curved_hbox.gd.remap"),
}


def main():
    if not os.path.isfile(PCK):
        print("错误：找不到 " + PCK)
        print("请把 PolyRomanceMod 文件夹放在游戏目录（sovereign_tower.exe 所在目录）内再运行。")
        return 1

    if os.path.isfile(BACKUP):
        print("检测到已有备份，跳过备份步骤（游戏可能已安装过模组）。")
    else:
        print("正在备份原始 pck（约 1.4 GB，需要一两分钟）...")
        shutil.copyfile(PCK, BACKUP)
        print("备份完成：" + BACKUP)

    print("正在注入模组文件...")
    patch_pck(PCK, FILES)

    pck = Pck(PCK)
    data = pck.read_file("res://mods/poly_romance/mod_entry.gd")
    assert b"PolyRomance" in data
    remap = pck.read_file("res://systems/autoloads/panku_manager.gd.remap").decode("utf-8")
    assert "mods/poly_romance/mod_entry.gd" in remap
    remap2 = pck.read_file("res://systems/autoloads/character_manager.gd.remap").decode("utf-8")
    assert "mods/poly_romance/character_manager.gd" in remap2
    remap3 = pck.read_file("res://scenes/roundtable/curved_hbox.gd.remap").decode("utf-8")
    assert "mods/poly_romance/curved_hbox.gd" in remap3
    print("模组安装成功！启动游戏后按 F8 打开同心结菜单。")
    print("如需卸载，运行「卸载模组.bat」即可还原原始文件。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
