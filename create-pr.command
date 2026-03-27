#!/bin/bash
# create-pr.command — 在 macOS Finder 雙擊執行
# 根據 JIRA 票與 git branch 產出 PR 描述 markdown

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

source "$SCRIPT_DIR/lib/auth.sh"
source "$SCRIPT_DIR/lib/jira-project.sh"
source "$SCRIPT_DIR/lib/repo-config.sh"
source "$SCRIPT_DIR/lib/git-helper.sh"
source "$SCRIPT_DIR/lib/jira.sh"
source "$SCRIPT_DIR/lib/claude-api.sh"

PROMPT_TEMPLATE="$SCRIPT_DIR/prompts/create-pr.md"
RESULTS_DIR="$SCRIPT_DIR/results"
mkdir -p "$RESULTS_DIR"

TOTAL_START=$SECONDS

# ── Spinner ───────────────────────────────────────────────

spin() {
  local pid=$1
  local chars="⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"
  local i=0
  local start=$SECONDS
  while kill -0 "$pid" 2>/dev/null; do
    local elapsed=$(( SECONDS - start ))
    local min=$(( elapsed / 60 ))
    local sec=$(( elapsed % 60 ))
    printf "\r   ⏳ Claude 產生中 ${chars:i++%${#chars}:1} %02d:%02d " "$min" "$sec"
    sleep 0.1
  done
  local elapsed=$(( SECONDS - start ))
  printf "\r   ✓ 完成 (${elapsed}s)                      \n"
}

step_time() {
  echo "$(( SECONDS - $1 ))s"
}

# ── 相依性檢查 ────────────────────────────────────────────

check_deps() {
  local missing=()
  command -v jq   &>/dev/null || missing+=("jq")
  command -v git  &>/dev/null || missing+=("git")
  command -v curl &>/dev/null || missing+=("curl")

  if [ ${#missing[@]} -gt 0 ]; then
    echo "❌ 缺少必要工具：${missing[*]}"
    echo ""
    echo "請安裝 Homebrew 後執行："
    echo "  brew install ${missing[*]}"
    echo ""
    echo "按任意鍵關閉..."
    read -n 1
    exit 1
  fi

  if ! command -v claude &>/dev/null; then
    echo "❌ 找不到 claude CLI"
    echo ""
    echo "請先安裝 Claude Code：https://claude.ai/download"
    echo "安裝後確認可執行：claude --version"
    echo ""
    echo "按任意鍵關閉..."
    read -n 1
    exit 1
  fi
}

# ── 主程式 ────────────────────────────────────────────────

clear
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  🚀 AI PR 描述產生器"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

check_deps

# Step 0: 憑證檢查與設定
check_all_credentials

echo ""
read -r -p "🔧 重設憑證？（直接 Enter 跳過）[r]: " reset_choice
if [ "$reset_choice" = "r" ]; then
  reset_credentials_menu
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Step 1: 使用者輸入
echo "📝 請輸入 PR 資訊"
echo ""

# JIRA 專案選擇 + 票號數字（設定 TICKET 變數，例如 OW-1234）
select_jira_ticket

if [ -z "$TICKET" ]; then
  echo "❌ 未取得票號"
  echo "按任意鍵關閉..."; read -n 1; exit 1
fi

read -r -p "Feature Branch（來源 branch）: " SOURCE_BRANCH
if [ -z "$SOURCE_BRANCH" ]; then
  echo "❌ 未輸入 source branch"
  echo "按任意鍵關閉..."; read -n 1; exit 1
fi

read -r -p "Target Branch（合併目標，預設 main）: " TARGET_BRANCH
TARGET_BRANCH="${TARGET_BRANCH:-main}"

# Repository 選擇（設定 REPO_PATH & REPO_TYPE）
select_repo

if [ -z "$REPO_PATH" ]; then
  echo "❌ 未選擇 repository"
  echo "按任意鍵關閉..."; read -n 1; exit 1
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Step 2: 取得 JIRA 資訊
echo "📋 [1/3] 取得 JIRA 票資訊..."
STEP_START=$SECONDS
fetch_jira_ticket "$TICKET"
echo "   ($(step_time $STEP_START))"
echo ""

# Step 3: 取得 git 資訊
STEP_START=$SECONDS
if [ "$REPO_TYPE" = "github" ]; then
  echo "🐙 [2/3] 從 GitHub API 取得變更資訊..."
else
  echo "📂 [2/3] 從本地 git 取得變更資訊..."
fi

fetch_git_info

FILE_COUNT=$(echo "$GIT_FILES"   | grep -c . 2>/dev/null || echo 0)
COMMIT_COUNT=$(echo "$GIT_COMMITS" | grep -c . 2>/dev/null || echo 0)
echo "   ✓ ${COMMIT_COUNT} commits | ${FILE_COUNT} 個檔案 ($(step_time $STEP_START))"

if [ -z "$GIT_COMMITS" ] && [ -z "$GIT_FILES" ]; then
  echo ""
  echo "⚠️  未偵測到 ${SOURCE_BRANCH} 相對於 ${TARGET_BRANCH} 的變更"
  read -r -p "   是否仍然繼續？ [y/N]: " cont
  [ "${cont,,}" != "y" ] && exit 0
fi

echo ""

# Step 4: 組合 prompt 並呼叫 Claude
STEP_START=$SECONDS
echo "🤖 [3/3] 呼叫 Claude (claude -p)..."

PROMPT_CONTENT=$(cat "$PROMPT_TEMPLATE")
PROMPT_CONTENT="${PROMPT_CONTENT//\{\{TICKET\}\}/$TICKET}"
PROMPT_CONTENT="${PROMPT_CONTENT//\{\{JIRA_TITLE\}\}/$JIRA_TITLE}"
PROMPT_CONTENT="${PROMPT_CONTENT//\{\{JIRA_DESCRIPTION\}\}/$JIRA_DESCRIPTION}"
PROMPT_CONTENT="${PROMPT_CONTENT//\{\{JIRA_ACCEPTANCE\}\}/$JIRA_ACCEPTANCE}"
PROMPT_CONTENT="${PROMPT_CONTENT//\{\{JIRA_URL\}\}/$JIRA_URL}"
PROMPT_CONTENT="${PROMPT_CONTENT//\{\{SOURCE_BRANCH\}\}/$SOURCE_BRANCH}"
PROMPT_CONTENT="${PROMPT_CONTENT//\{\{TARGET_BRANCH\}\}/$TARGET_BRANCH}"
PROMPT_CONTENT="${PROMPT_CONTENT//\{\{GIT_COMMITS\}\}/$GIT_COMMITS}"
PROMPT_CONTENT="${PROMPT_CONTENT//\{\{GIT_FILES\}\}/$GIT_FILES}"
PROMPT_CONTENT="${PROMPT_CONTENT//\{\{GIT_STAT\}\}/$GIT_STAT}"

PROMPT_TMPFILE=$(mktemp)
echo "$PROMPT_CONTENT" > "$PROMPT_TMPFILE"

TIMESTAMP=$(date +%y%m%d%H%M%S)
OUTPUT_FILE="$RESULTS_DIR/PR_${TICKET}_${TIMESTAMP}.md"
TMPFILE=$(mktemp)

call_claude "$PROMPT_TMPFILE" "$TMPFILE" &
spin $!
CLAUDE_EXIT=$?
rm -f "$PROMPT_TMPFILE"

if [ $CLAUDE_EXIT -ne 0 ] || [ ! -s "$TMPFILE" ]; then
  echo "❌ Claude 執行失敗"
  echo "按任意鍵關閉..."; read -n 1; exit 1
fi

# Step 5: 儲存結果
TOTAL_ELAPSED=$(( SECONDS - TOTAL_START ))
TOTAL_MIN=$(( TOTAL_ELAPSED / 60 ))
TOTAL_SEC=$(( TOTAL_ELAPSED % 60 ))

USAGE_FILE="${TMPFILE}.usage"
INPUT_TOKENS=$(jq -r  '.input_tokens  // 0' "$USAGE_FILE" 2>/dev/null || echo 0)
OUTPUT_TOKENS=$(jq -r '.output_tokens // 0' "$USAGE_FILE" 2>/dev/null || echo 0)
CACHE_READ=$(jq -r    '.cache_read    // 0' "$USAGE_FILE" 2>/dev/null || echo 0)
COST=$(get_cost "$USAGE_FILE" 2>/dev/null || echo "0.0000")
rm -f "$USAGE_FILE"

REPO_SOURCE_LABEL="本地 📂"
[ "$REPO_TYPE" = "github" ] && REPO_SOURCE_LABEL="GitHub 🐙"

cat "$TMPFILE" > "$OUTPUT_FILE"

rm -f "$TMPFILE"

# ── 顯示結果 ──────────────────────────────────────────────

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

head -30 "$OUTPUT_FILE"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
printf "✅ 已儲存至 results/PR_%s_%s.md\n" "$TICKET" "$TIMESTAMP"
echo ""
printf "⏱  總耗時    %02d:%02d\n" "$TOTAL_MIN" "$TOTAL_SEC"
printf "📊 Tokens    input  %d\n" "$INPUT_TOKENS"
printf "             output %d\n" "$OUTPUT_TOKENS"
if [ "$CACHE_READ" -gt 0 ]; then
printf "             cache  %d（已快取，不計費）\n" "$CACHE_READ"
fi
printf "💰 本次費用  \$%s USD\n" "$COST"
echo ""

read -r -p "📂 開啟 results 資料夾？ [Y/n]: " open_choice
open_choice="${open_choice:-Y}"
if [[ "$open_choice" =~ ^[Yy]$ ]]; then
  open "$RESULTS_DIR"
fi

echo ""
echo "按任意鍵關閉..."
read -n 1
