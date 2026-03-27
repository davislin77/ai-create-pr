#!/bin/bash
# auth.sh — 憑證管理：載入、儲存、設定 GitHub / JIRA / Claude 帳號

CREDENTIALS_FILE="$SCRIPT_DIR/.credentials"

# ── 載入 / 儲存 ────────────────────────────────────────────

load_credentials() {
  GITHUB_TOKEN=""
  JIRA_BASE_URL=""
  JIRA_EMAIL=""
  JIRA_API_TOKEN=""

  if [ -f "$CREDENTIALS_FILE" ]; then
    # shellcheck source=/dev/null
    source "$CREDENTIALS_FILE"
  fi
}

save_credential() {
  local key="$1"
  local value="$2"
  touch "$CREDENTIALS_FILE"
  chmod 600 "$CREDENTIALS_FILE"

  if grep -q "^${key}=" "$CREDENTIALS_FILE" 2>/dev/null; then
    # 取代既有的值
    local tmp
    tmp=$(mktemp)
    grep -v "^${key}=" "$CREDENTIALS_FILE" > "$tmp"
    echo "${key}=${value}" >> "$tmp"
    mv "$tmp" "$CREDENTIALS_FILE"
  else
    echo "${key}=${value}" >> "$CREDENTIALS_FILE"
  fi
}

mask_token() {
  local token="$1"
  if [ -z "$token" ]; then echo "(未設定)"; return; fi
  if [ "${#token}" -le 8 ]; then echo "****"; return; fi
  echo "${token:0:4}...${token: -4}"
}

# ── GitHub ────────────────────────────────────────────────

setup_github() {
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "🐙 GitHub 授權設定"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  if command -v gh &>/dev/null; then
    echo "偵測到 GitHub CLI (gh)，即將開啟瀏覽器進行授權..."
    echo ""
    gh auth login --web --git-protocol https
    if [ $? -eq 0 ]; then
      # 取得 token 存起來供備用
      local token
      token=$(gh auth token 2>/dev/null)
      if [ -n "$token" ]; then
        save_credential "GITHUB_TOKEN" "$token"
        GITHUB_TOKEN="$token"
        echo "✅ GitHub 授權成功"
      fi
    else
      echo "⚠️  gh auth login 失敗，改用 Personal Access Token"
      _setup_github_pat
    fi
  else
    echo "未安裝 GitHub CLI，將使用 Personal Access Token"
    _setup_github_pat
  fi
}

_setup_github_pat() {
  echo ""
  echo "即將開啟 GitHub Token 設定頁面..."
  echo "請建立一個有 repo 權限的 Personal Access Token，然後貼回這裡。"
  echo ""
  open "https://github.com/settings/tokens/new?scopes=repo&description=ai-create-pr"
  echo ""
  read -r -p "貼上你的 GitHub Token: " token
  if [ -n "$token" ]; then
    save_credential "GITHUB_TOKEN" "$token"
    GITHUB_TOKEN="$token"
    echo "✅ GitHub Token 已儲存"
  else
    echo "❌ 未輸入 Token"
  fi
}

# ── JIRA ─────────────────────────────────────────────────

setup_jira() {
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "📋 JIRA 授權設定"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""

  # JIRA Base URL（只保留 scheme + host，去除 /browse 等路徑）
  read -r -p "JIRA 網址（例: https://yourcompany.atlassian.net）: " jira_url
  jira_url=$(echo "$jira_url" | grep -oE 'https?://[^/]+')  # 只留 host
  if [ -z "$jira_url" ]; then
    echo "❌ 未輸入 JIRA 網址"
    return 1
  fi
  save_credential "JIRA_BASE_URL" "$jira_url"
  JIRA_BASE_URL="$jira_url"

  # Email
  read -r -p "你的 Atlassian 帳號 Email: " jira_email
  if [ -z "$jira_email" ]; then
    echo "❌ 未輸入 Email"
    return 1
  fi
  save_credential "JIRA_EMAIL" "$jira_email"
  JIRA_EMAIL="$jira_email"

  # API Token
  echo ""
  echo "即將開啟 Atlassian API Token 建立頁面..."
  echo "點選「Create API token」，複製後貼回這裡。"
  echo ""
  open "https://id.atlassian.com/manage-profile/security/api-tokens"
  echo ""
  read -r -p "貼上你的 JIRA API Token: " jira_token
  if [ -z "$jira_token" ]; then
    echo "❌ 未輸入 API Token"
    return 1
  fi
  save_credential "JIRA_API_TOKEN" "$jira_token"
  JIRA_API_TOKEN="$jira_token"

  echo "✅ JIRA 設定已儲存"
}

# ── 一鍵檢查所有憑證 ──────────────────────────────────────

check_all_credentials() {
  load_credentials
  local need_setup=false

  echo ""
  echo "🔑 憑證狀態："
  echo "   GitHub Token : $(mask_token "$GITHUB_TOKEN")"
  echo "   JIRA URL     : ${JIRA_BASE_URL:-(未設定)}"
  echo "   JIRA Email   : ${JIRA_EMAIL:-(未設定)}"
  echo "   JIRA Token   : $(mask_token "$JIRA_API_TOKEN")"
  echo "   Claude       : 沿用 Claude Code 登入帳號 ✓"

  if [ -z "$GITHUB_TOKEN" ]; then
    echo ""
    echo "⚠️  需要設定 GitHub 授權"
    setup_github
    need_setup=true
  fi

  if [ -z "$JIRA_BASE_URL" ] || [ -z "$JIRA_EMAIL" ] || [ -z "$JIRA_API_TOKEN" ]; then
    echo ""
    echo "⚠️  需要設定 JIRA 授權"
    setup_jira
    need_setup=true
  fi

  if [ "$need_setup" = true ]; then
    load_credentials  # 重新載入剛才儲存的憑證
    echo ""
  fi
}

# ── 重設憑證選單 ──────────────────────────────────────────

reset_credentials_menu() {
  echo ""
  echo "🔧 重設憑證"
  echo "  [1] GitHub"
  echo "  [2] JIRA"
  echo "  [3] 全部重設"
  echo "  [0] 取消"
  echo ""
  read -r -p "選擇: " choice
  case "$choice" in
    1) setup_github ;;
    2) setup_jira ;;
    3) rm -f "$CREDENTIALS_FILE"; check_all_credentials ;;
    *) echo "取消" ;;
  esac
  load_credentials
}
