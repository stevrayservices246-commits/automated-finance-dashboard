#!/bin/bash
set -euo pipefail

echo "==> Fixing project path + ensuring backend exists..."

# 1) Try expected location
ROOT="$HOME/quiet-systems"

# 2) If backend isn't there, try to find it anywhere under $HOME
if [ ! -d "$ROOT/backend" ]; then
  echo "==> backend/ not found at $ROOT"
  echo "==> Searching under $HOME for a folder containing backend/package.json ..."

  FOUND="$(find "$HOME" -maxdepth 6 -type f -path "*/backend/package.json" 2>/dev/null | head -n 1 || true)"
  if [ -n "$FOUND" ]; then
    ROOT="$(dirname "$(dirname "$FOUND")")"
    echo "==> Found project root at: $ROOT"
  fi
fi

# 3) If still no backend, create the minimal base structure
if [ ! -d "$ROOT/backend" ]; then
  echo "==> Still no backend/. Creating base project at: $ROOT"
  mkdir -p "$ROOT/backend"/{modules,routes,config,logs,data} "$ROOT/frontend"
  cat > "$ROOT/backend/package.json" <<'PKG'
{
  "name": "quiet-systems-backend",
  "version": "1.0.0",
  "main": "index.js",
  "scripts": {
    "start": "node index.js"
  },
  "dependencies": {
    "express": "^4.18.2",
    "cors": "^2.8.5",
    "helmet": "^7.0.0",
    "dotenv": "^16.3.1",
    "axios": "^1.6.7",
    "googleapis": "^118.0.0",
    "express-rate-limit": "^7.0.0"
  }
}
PKG
  cat > "$ROOT/backend/index.js" <<'INDEX'
require("dotenv").config();
const express = require("express");
const cors = require("cors");
const helmet = require("helmet");

const app = express();
app.use(helmet());
app.use(cors({ origin: true, credentials: true }));
app.use(express.json());

app.get("/health", (req,res)=>res.json({status:"ok", ts:new Date().toISOString()}));

const PORT = process.env.PORT || 3000;
app.listen(PORT, ()=>console.log("Quiet Systems running on port", PORT));
INDEX

  # basic frontend placeholder so /dashboard works
  cat > "$ROOT/frontend/index.html" <<'HTML'
<!doctype html><html><head><meta charset="utf-8"/><meta name="viewport" content="width=device-width,initial-scale=1"/>
<title>Quiet Systems</title></head><body>
<h1>Quiet Systems</h1>
<p>Base frontend created. Patch script will replace this with the full dashboard.</p>
</body></html>
HTML
fi

echo "==> Using project root: $ROOT"
cd "$ROOT"

# 4) If patch-deploy.sh exists, run it from the correct root.
#    If it does NOT exist, tell user what to do.
if [ ! -f "$ROOT/patch-deploy.sh" ]; then
  echo ""
  echo "❌ patch-deploy.sh not found at: $ROOT/patch-deploy.sh"
  echo "✅ Fix: paste your patch block again (the cat > ~/quiet-systems/patch-deploy.sh ... block)"
  echo "   OR move your patch-deploy.sh into: $ROOT"
  echo ""
  echo "Current folder contents:"
  ls -la
  exit 1
fi

echo "==> Running patch-deploy.sh from correct root..."
chmod +x "$ROOT/patch-deploy.sh"
bash "$ROOT/patch-deploy.sh"

echo ""
echo "✅ Done."
echo "Next: start locally:"
echo "  cd $ROOT/backend && npm install && npm start"
