#!/usr/bin/env python3
from pathlib import Path

root = Path(__file__).resolve().parents[1]
tool = (root / "src/routes/cn/tool.ts").read_text(encoding="utf-8")
load = (root / "src/routes/cn/load.ts").read_text(encoding="utf-8")
mail = (root / "src/routes/web/mail.ts").read_text(encoding="utf-8")
server = (root / "src/cn-server.ts").read_text(encoding="utf-8")
gacha = (root / "src/routes/api/gacha.ts").read_text(encoding="utf-8")

assert "generateViewerIdSession(accountId)" in tool
assert "token: String(accountId)" not in tool
assert "body.viewer_id || body.keychain || 1" not in load
assert "await getSession(String(viewerId))" in load
assert "${okMsg}" not in mail and "${errMsg}" not in mail
assert 'process.env.CN_LISTEN_HOST ?? "127.0.0.1"' in server
assert "done(parseError, undefined)" in server
assert '"Player data missing."' in gacha
print("server security regression checks passed")
