#!/bin/bash
# git-helper.sh — 取得 git 變更資訊（支援本地 folder 與 GitHub API）
#
# 呼叫 fetch_git_info 後會設定以下全域變數：
#   GIT_COMMITS — commit 列表（oneline 格式）
#   GIT_FILES   — 變動檔案列表（含 A/M/D/R 狀態）
#   GIT_STAT    — 統計摘要（幾個檔案、新增/刪除幾行）

fetch_git_info() {
  if [ "$REPO_TYPE" = "github" ]; then
    _fetch_git_info_github
  else
    _fetch_git_info_local
  fi
}

# ── 本地 git 指令 ─────────────────────────────────────────

_fetch_git_info_local() {
  local prev_dir="$PWD"
  cd "$REPO_PATH" || { echo "❌ 無法進入 $REPO_PATH"; return 1; }

  # 嘗試同步遠端（非阻斷性）
  git fetch --quiet origin 2>/dev/null

  # Commits（優先用 origin/ 前綴，避免本地 branch 落後問題）
  GIT_COMMITS=$(git log "origin/${TARGET_BRANCH}..${SOURCE_BRANCH}" \
    --oneline --no-merges 2>/dev/null)
  if [ -z "$GIT_COMMITS" ]; then
    GIT_COMMITS=$(git log "${TARGET_BRANCH}..${SOURCE_BRANCH}" \
      --oneline --no-merges 2>/dev/null)
  fi

  # 變動檔案
  GIT_FILES=$(git diff --name-status "origin/${TARGET_BRANCH}...${SOURCE_BRANCH}" 2>/dev/null || \
              git diff --name-status "${TARGET_BRANCH}...${SOURCE_BRANCH}" 2>/dev/null)

  # 統計摘要
  GIT_STAT=$(git diff --stat "origin/${TARGET_BRANCH}...${SOURCE_BRANCH}" 2>/dev/null || \
             git diff --stat "${TARGET_BRANCH}...${SOURCE_BRANCH}" 2>/dev/null)

  cd "$prev_dir"
}

# ── GitHub Compare API ────────────────────────────────────

_fetch_git_info_github() {
  # 從 URL 解析 owner/repo
  local owner_repo
  owner_repo=$(echo "$REPO_PATH" | sed 's|https://github\.com/||' | sed 's|\.git$||' | sed 's|/$||')

  local response

  # 優先用 gh CLI（已含 auth），fallback 用 curl + GITHUB_TOKEN
  if command -v gh &>/dev/null && gh auth status &>/dev/null 2>&1; then
    response=$(gh api \
      "repos/${owner_repo}/compare/${TARGET_BRANCH}...${SOURCE_BRANCH}" \
      --paginate 2>&1)
  else
    response=$(curl -s \
      -H "Authorization: Bearer ${GITHUB_TOKEN}" \
      -H "Accept: application/vnd.github+json" \
      "https://api.github.com/repos/${owner_repo}/compare/${TARGET_BRANCH}...${SOURCE_BRANCH}")
  fi

  # 錯誤處理
  local api_error
  api_error=$(echo "$response" | jq -r '.message // empty' 2>/dev/null)
  if [ -n "$api_error" ]; then
    echo "❌ GitHub API 錯誤：${api_error}" >&2
    GIT_COMMITS="（無法取得 commit 資訊：$api_error）"
    GIT_FILES=""; GIT_STAT=""
    return 1
  fi

  # Commits（取 sha 前 7 碼 + message 第一行）
  GIT_COMMITS=$(echo "$response" | jq -r \
    '.commits[] | .sha[0:7] + " " + (.commit.message | split("\n")[0])' \
    2>/dev/null)

  # 變動檔案（轉換成 git diff --name-status 風格）
  GIT_FILES=$(echo "$response" | jq -r '.files[] |
    (if   .status == "added"    then "A"
     elif .status == "removed"  then "D"
     elif .status == "renamed"  then "R"
     elif .status == "copied"   then "C"
     else                            "M" end
    ) + "\t" + .filename' 2>/dev/null)

  # 統計摘要
  local total_files total_add total_del
  total_files=$(echo "$response" | jq '.files | length' 2>/dev/null)
  total_add=$(echo "$response"   | jq '[.files[].additions] | add // 0' 2>/dev/null)
  total_del=$(echo "$response"   | jq '[.files[].deletions] | add // 0' 2>/dev/null)
  GIT_STAT="${total_files} files changed, +${total_add} -${total_del}"

  # 若 API 只回傳部分檔案（> 300），補充說明
  local ahead_by
  ahead_by=$(echo "$response" | jq -r '.ahead_by // 0' 2>/dev/null)
  if [ "$total_files" -ge 300 ]; then
    GIT_STAT="${GIT_STAT}（GitHub API 限制最多顯示 300 個檔案）"
  fi
}
