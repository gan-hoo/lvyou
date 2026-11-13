#!/usr/bin/env python3
"""Generates scripts/translations_zh_hant.json from the Simplified Chinese table.

Requires OpenCC:  pip install opencc-python-reimplemented
Run once after editing translations_zh.json, then review the output.
"""
import json, os, re
from opencc import OpenCC

ROOT = os.path.dirname(os.path.abspath(__file__))
cc = OpenCC("s2t")
# Hong Kong / Taiwan wording and Apple's Traditional Chinese terminology.
FIXUPS = [
    ("面容 ID", "Face ID"), ("觸控 ID", "Touch ID"), ("光學 ID", "Optic ID"),
    ("記賬", "記帳"), ("賬", "帳"), ("設置", "設定"), ("默認", "預設"),
    ("導入", "匯入"), ("導出", "匯出"), ("信息", "資訊"), ("視頻", "影片"),
    ("支持", "支援"), ("數據", "資料"), ("用戶", "使用者"), ("文件", "檔案"),
    ("跟隨系統", "跟隨系統"), ("鍵盤", "鍵盤"), ("多任務界面", "App 切換器"),
    ("界面", "介面"), ("搜索", "搜尋"), ("屏幕", "螢幕"), ("菜單", "選單"),
    ("爲", "為"), ("臺", "台"), ("裏", "裡"), ("着", "著"), ("綫", "線"),
    ("周", "週"), ("添加", "新增"), ("創建", "建立"), ("雲盤", "雲碟"),
]

def convert(text: str) -> str:
    out = cc.convert(text)
    for a, b in FIXUPS:
        out = out.replace(a, b)
    # Keep a space between Chinese text and Latin product names, as Apple does.
    out = re.sub(r"([\u4e00-\u9fff])(Face ID|Touch ID|Optic ID)", r"\1 \2", out)
    out = re.sub(r"(Face ID|Touch ID|Optic ID)([\u4e00-\u9fff])", r"\1 \2", out)
    return out

source = json.load(open(os.path.join(ROOT, "translations_zh.json"), encoding="utf-8"))
result = {}
for key, value in source.items():
    if isinstance(value, dict):
        value = value["zh-Hans"]["stringUnit"]["value"]
    result[key] = convert(value)
json.dump(result, open(os.path.join(ROOT, "translations_zh_hant.json"), "w", encoding="utf-8"),
          ensure_ascii=False, indent=2, sort_keys=True)
print(f"{len(result)} Traditional Chinese strings")
