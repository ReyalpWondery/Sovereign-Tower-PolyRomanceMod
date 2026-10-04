#!/usr/bin/env python3
"""同心结 PolyRomance 卸载器：从备份还原原始 pck。"""
import os
import shutil
import sys

MOD_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GAME_DIR = os.path.dirname(MOD_ROOT)
PCK = os.path.join(GAME_DIR, "sovereign_tower.pck")
BACKUP = PCK + ".polyromance_backup"


def main():
    if not os.path.isfile(BACKUP):
        print("未找到备份文件，游戏应该本来就是未修改状态，无需卸载。")
        return 0
    print("正在还原原始 pck（约 1.4 GB，需要一两分钟）...")
    shutil.copyfile(BACKUP, PCK)
    os.remove(BACKUP)
    print("卸载完成，游戏已恢复原版。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
