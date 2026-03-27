#!/bin/bash
# jira-project.sh — 管理 JIRA 專案清單
#
# .jira-projects 格式（每行一個）：
#   專案名稱|PREFIX
#
# 範例：
#   Owlnest|OW
#   Backend|BE

JIRA_PROJECTS_FILE="$SCRIPT_DIR/.jira-projects"

# ── 讀取所有專案 ──────────────────────────────────────────

load_jira_projects() {
  JIRA_PROJECT_NAMES=()
  JIRA_PROJECT_PREFIXES=()

  [ -f "$JIRA_PROJECTS_FILE" ] || return

  while IFS='|' read -r name prefix; do
    [[ -z "$name" || "$name" == \#* ]] && continue
    JIRA_PROJECT_NAMES+=("$name")
    JIRA_PROJECT_PREFIXES+=("$prefix")
  done < "$JIRA_PROJECTS_FILE"
}

# ── 儲存新專案 ────────────────────────────────────────────

save_jira_project() {
  local name="$1"
  local prefix="$2"
  touch "$JIRA_PROJECTS_FILE"
  echo "${name}|${prefix}" >> "$JIRA_PROJECTS_FILE"
}

# ── 互動式選擇選單 ────────────────────────────────────────

# 執行後設定全域變數：
#   JIRA_PREFIX  — 票號前綴，例如 OW
#   TICKET       — 完整票號，例如 OW-1234
select_jira_ticket() {
  load_jira_projects

  echo ""
  echo "📋 選擇 JIRA 專案："
  echo ""

  local i
  for i in "${!JIRA_PROJECT_NAMES[@]}"; do
    printf "  [%d] %s (%s)\n" $(( i + 1 )) "${JIRA_PROJECT_NAMES[$i]}" "${JIRA_PROJECT_PREFIXES[$i]}"
  done

  local add_idx=$(( ${#JIRA_PROJECT_NAMES[@]} + 1 ))
  echo "  ────────────────────────"
  printf "  [%d] 新增專案...\n" "$add_idx"
  echo ""

  local choice
  read -r -p "選擇 [1-${add_idx}]: " choice

  if ! [[ "$choice" =~ ^[0-9]+$ ]]; then
    echo "❌ 請輸入數字"
    select_jira_ticket; return
  fi

  if [ "$choice" -ge 1 ] && [ "$choice" -le "${#JIRA_PROJECT_NAMES[@]}" ]; then
    local idx=$(( choice - 1 ))
    JIRA_PREFIX="${JIRA_PROJECT_PREFIXES[$idx]}"
    echo "   → ${JIRA_PROJECT_NAMES[$idx]} (${JIRA_PREFIX})"

  elif [ "$choice" -eq "$add_idx" ]; then
    _add_jira_project

  else
    echo "❌ 無效選項"
    select_jira_ticket; return
  fi

  # 詢問票號數字（每次都問，不儲存）
  echo ""
  local ticket_num
  read -r -p "票號數字: " ticket_num

  if ! [[ "$ticket_num" =~ ^[0-9]+$ ]]; then
    echo "❌ 請輸入純數字"
    echo ""
    read -r -p "票號數字: " ticket_num
  fi

  TICKET="${JIRA_PREFIX}-${ticket_num}"
  echo "   → ${TICKET}"
}

# ── 新增專案 ──────────────────────────────────────────────

_add_jira_project() {
  echo ""
  read -r -p "專案名稱（例: Owlnest）: " new_name
  if [ -z "$new_name" ]; then
    echo "❌ 未輸入名稱"; _add_jira_project; return
  fi

  read -r -p "票號 Prefix（例: OW）: " new_prefix
  new_prefix=$(echo "$new_prefix" | tr '[:lower:]' '[:upper:]')  # 統一大寫
  if [ -z "$new_prefix" ]; then
    echo "❌ 未輸入 Prefix"; _add_jira_project; return
  fi

  save_jira_project "$new_name" "$new_prefix"
  JIRA_PREFIX="$new_prefix"
  echo "   ✅ 已儲存「${new_name} (${new_prefix})」，下次可直接選擇"
}
