#!/usr/bin/env python3
"""Render the local support/privacy site; refuse publication-ready output with missing public details."""
import argparse
import html
import json
import shutil
from pathlib import Path
from urllib.parse import urlparse

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--ready", action="store_true", help="Require complete public operator/contact/URL details")
args = parser.parse_args()
config = json.loads((root / "release/site-config.json").read_text())
missing = [key for key in ["operator", "supportEmail", "baseURL", "copyrightHolder"] if not config.get(key)]
email = config.get("supportEmail")
base = config.get("baseURL")
if email and ("@" not in email or any(c in email for c in "\r\n <>\"")):
    raise SystemExit("Invalid support email")
if base and (urlparse(base).scheme != "https" or not urlparse(base).netloc or urlparse(base).query or urlparse(base).fragment):
    raise SystemExit("Use a complete HTTPS base URL without query/fragment")
if args.ready and missing:
    raise SystemExit("Fill release/site-config.json before publishing: " + ", ".join(missing))
output = root / "release/site"
output.mkdir(exist_ok=True)
contact = (f'<p><a href="mailto:{html.escape(email, quote=True)}">{html.escape(email)}</a></p>' if email
           else '<p class="muted">問い合わせ先メール：未設定（公開前に設定）</p>')
values = {"operator": html.escape(config.get("operator") or "運営者名：未設定"),
          "updatedAt": html.escape(config["updatedAt"]), "contact": contact}
titles = {"index": "今日何食べる？｜冷蔵庫から、今日のごはん。", "support": "使い方とサポート｜今日何食べる？", "privacy": "プライバシーポリシー｜今日何食べる？"}
for page, title in titles.items():
    body = (root / f"release/site-source/{page}.html").read_text()
    for key, value in values.items():
        body = body.replace("{{" + key + "}}", value)
    banner = '<aside class="draft" role="note">公開前の確認用原稿です。運営者・問い合わせ先・公開URLを確定するまで公開しないでください。</aside>' if missing else ""
    canonical = f'<link rel="canonical" href="{html.escape(base.rstrip("/") + "/" + page + ".html", quote=True)}">' if base else ""
    robots = '<meta name="robots" content="noindex,nofollow">' if missing else ""
    document = f'''<!doctype html>
<html lang="ja"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>{html.escape(title)}</title><meta name="description" content="冷蔵庫にある食材から献立を選び、不足分を買い物へ。今日何食べる？の使い方と情報の取り扱いをご案内します。">{robots}{canonical}<link rel="stylesheet" href="style.css"></head>
<body><header><div class="wrap"><a class="brand" href="index.html">今日何食べる？</a><nav aria-label="案内"><a href="support.html">サポート</a><a href="privacy.html">プライバシー</a></nav></div></header><main class="wrap">{banner}{body}</main><footer><div class="wrap">© 2026 {html.escape(config.get("copyrightHolder") or "権利者名：未設定")} · 今日何食べる？</div></footer></body></html>
'''
    (output / f"{page}.html").write_text(document)
shutil.copy2(root / "release/site-source/style.css", output / "style.css")
shutil.copytree(root / "release/site-source/assets", output / "assets", dirs_exist_ok=True)
urls = {key: base.rstrip("/") + "/" + filename if base else None
        for key, filename in [("marketingURL", "index.html"), ("supportURL", "support.html"), ("privacyPolicyURL", "privacy.html")]}
(root / "release/app-store/urls.json").write_text(json.dumps(urls, ensure_ascii=False, indent=2) + "\n")
print(json.dumps({"output": str(output), "ready": not missing, "missing": missing}, ensure_ascii=False))
