#!/bin/bash
# repo-config.sh — 管理常用 Repository 清單（支援本地 folder 與 GitHub URL）
#
# .repo-config 格式（每行一個）：
#   別名|類型|路徑或URL
#   類型：local（本地 folder）或 github（GitHub repo URL）
#
# 範例：
#   PMS|local|/Users/davis/Sites/devops/pms
#   Owlting-UI|github|https://github.com/company/owlting-ui

REPO_CONFIG_FILE="$SCRIPT_DIR/.repo-config"

# ── 讀取所有 repo ──────────────────────────────────────────

# 解析 .repo-config → 三個陣列：REPO_ALIASES[] REPO_TYPES[] REPO_TARGETS[]
load_repos() {
  REPO_ALIASES=()
  REPO_TYPES=()
  REPO_TARGETS=()

  [ -f "$REPO_CONFIG_FILE" ] || return

  while IFS='|' read -r alias type target; do
    [[ -z "$alias" || "$alias" == \#* ]] && continue

    # 向下相容：舊格式只有兩欄（alias|path），預設為 local
    if [ -z "$target" ]; then
      target="$type"
      type="local"
    fi

    REPO_ALIASES+=("$alias")
    REPO_TYPES+=("$type")
    REPO_TARGETS+=("$target")
  done < "$REPO_CONFIG_FILE"
}

# ── 儲存 repo ─────────────────────────────────────────────

save_repo() {
  local alias="$1"
  local type="$2"   # local | github
  local target="$3"
  touch "$REPO_CONFIG_FILE"
  echo "${alias}|${type}|${target}" >> "$REPO_CONFIG_FILE"
}

# ── 互動式選擇選單 ────────────────────────────────────────

# 執行後設定全域變數：
#   REPO_PATH  — 本地路徑 或 GitHub repo URL
#   REPO_TYPE  — "local" | "github"
select_repo() {
  load_repos

  echo ""
  echo "📁 選擇 Repository："
  echo ""

  local i
  for i in "${!REPO_ALIASES[@]}"; do
    local icon="📂"
    [ "${REPO_TYPES[$i]}" = "github" ] && icon="🐙"
    printf "  [%d] %-20s %s\n" $(( i + 1 )) "${REPO_ALIASES[$i]}" "$icon ${REPO_TYPES[$i]}"
  done

  echo "  ────────────────────────"
  local add_local_idx=$(( ${#REPO_ALIASES[@]} + 1 ))
  local add_github_idx=$(( ${#REPO_ALIASES[@]} + 2 ))
  printf "  [%d] 新增本地 repo...\n" "$add_local_idx"
  printf "  [%d] 新增 GitHub URL...\n" "$add_github_idx"
  echo ""

  local choice
  read -r -p "選擇 [1-${add_github_idx}]: " choice

  if ! [[ "$choice" =~ ^[0-9]+$ ]]; then
    echo "❌ 請輸入數字"
    select_repo; return
  fi

  if [ "$choice" -ge 1 ] && [ "$choice" -le "${#REPO_ALIASES[@]}" ]; then
    local idx=$(( choice - 1 ))
    REPO_PATH="${REPO_TARGETS[$idx]}"
    REPO_TYPE="${REPO_TYPES[$idx]}"
    local icon="📂"; [ "$REPO_TYPE" = "github" ] && icon="🐙"
    echo "   → $icon ${REPO_ALIASES[$idx]}"

  elif [ "$choice" -eq "$add_local_idx" ]; then
    _add_local_repo

  elif [ "$choice" -eq "$add_github_idx" ]; then
    _add_github_repo

  else
    echo "❌ 無效選項"
    select_repo; return
  fi
}

# ── 新增本地 repo ─────────────────────────────────────────

_add_local_repo() {
  echo ""
  read -r -p "本地 Repository 路徑（可拖曳資料夾進來）: " new_path
  new_path="${new_path%/}"
  new_path="${new_path/#\~/$HOME}"
  new_path="${new_path//\\ / }"   # 處理 Finder 拖曳的跳脫空格

  if [ -z "$new_path" ]; then
    echo "❌ 未輸入路徑"; _add_local_repo; return
  fi

  if ! git -C "$new_path" rev-parse --show-toplevel &>/dev/null; then
    echo "❌ 不是 git repository：$new_path"; _add_local_repo; return
  fi

  read -r -p "幫這個 repo 取個別名（例: PMS）: " new_alias
  if [ -z "$new_alias" ]; then
    echo "❌ 未輸入別名"; _add_local_repo; return
  fi

  save_repo "$new_alias" "local" "$new_path"
  REPO_PATH="$new_path"
  REPO_TYPE="local"
  echo "   ✅ 已儲存「${new_alias}」（本地），下次可直接選擇"
  echo "   → 📂 $REPO_PATH"
}

# ── 新增 GitHub URL repo ──────────────────────────────────

_add_github_repo() {
  echo ""
  echo "請輸入 GitHub repo URL"
  echo "範例：https://github.com/company/repo-name"
  echo ""
  read -r -p "GitHub URL: " new_url
  new_url="${new_url%/}"

  # 基本格式驗證
  if ! echo "$new_url" | grep -qE '^https://github\.com/[^/]+/[^/]+'; then
    echo "❌ 格式不正確，應為 https://github.com/owner/repo"; _add_github_repo; return
  fi

  read -r -p "幫這個 repo 取個別名（例: Owlting-UI）: " new_alias
  if [ -z "$new_alias" ]; then
    echo "❌ 未輸入別名"; _add_github_repo; return
  fi

  save_repo "$new_alias" "github" "$new_url"
  REPO_PATH="$new_url"
  REPO_TYPE="github"
  echo "   ✅ 已儲存「${new_alias}」（GitHub），下次可直接選擇"
  echo "   → 🐙 $REPO_PATH"
}
