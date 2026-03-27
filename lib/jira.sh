#!/bin/bash
# jira.sh — JIRA REST API 操作

# 從 JIRA 取得票的資訊
# 輸出：設定 JIRA_TITLE / JIRA_DESCRIPTION / JIRA_ACCEPTANCE / JIRA_URL 變數
fetch_jira_ticket() {
  local ticket="$1"

  # 防禦性處理：自動去除 URL 末尾的 /browse 或多餘路徑，只保留 scheme + host
  local jira_host
  jira_host=$(echo "$JIRA_BASE_URL" | grep -oE 'https?://[^/]+')

  echo "📡 取得 JIRA 票 ${ticket}..."
  echo "   URL: ${jira_host}/rest/api/3/issue/${ticket}"

  # 明確用 base64 建立 Basic Auth header（比 --user 更相容 Atlassian Cloud）
  local auth_b64
  auth_b64=$(printf '%s:%s' "${JIRA_EMAIL}" "${JIRA_API_TOKEN}" | base64 | tr -d '\n')

  # 用暫存檔分離 body 與 http status code
  local tmp_body
  tmp_body=$(mktemp)

  local http_code
  http_code=$(curl -s \
    -o "$tmp_body" \
    -w "%{http_code}" \
    -H "Authorization: Basic ${auth_b64}" \
    -H "Accept: application/json" \
    -H "Content-Type: application/json" \
    "${jira_host}/rest/api/3/issue/${ticket}" 2>&1)

  local response
  response=$(cat "$tmp_body")
  rm -f "$tmp_body"

  # 若 v3 仍回傳 HTML，自動 fallback 到 v2
  if echo "$response" | grep -q "^<!"; then
    echo "   ⚠️  API v3 回傳 HTML，嘗試 v2..."
    tmp_body=$(mktemp)
    http_code=$(curl -s \
      -o "$tmp_body" \
      -w "%{http_code}" \
      -H "Authorization: Basic ${auth_b64}" \
      -H "Accept: application/json" \
      -H "Content-Type: application/json" \
      "${jira_host}/rest/api/2/issue/${ticket}" 2>&1)
    response=$(cat "$tmp_body")
    rm -f "$tmp_body"
  fi

  # ── HTTP 狀態碼處理 ─────────────────────────────────────

  case "$http_code" in
    200)
      : # 正常，繼續往下
      ;;
    401)
      echo "❌ 認證失敗（401 AUTHENTICATED_FAILED）"
      echo ""
      echo "   目前設定的 Email：${JIRA_EMAIL}"
      echo ""
      echo "   常見原因："
      echo "   1. Email 與 Atlassian 帳號不符"
      echo "      → 請至 https://id.atlassian.com 確認你的帳號 Email"
      echo "   2. API Token 已過期或輸入錯誤"
      echo "      → 請至 https://id.atlassian.com/manage-profile/security/api-tokens 重新建立"
      echo ""
      echo "   確認後請在重設憑證選單選擇 [2] JIRA 重新設定"
      echo ""
      _prompt_manual_jira "$ticket"
      return
      ;;
    403)
      echo "❌ 無權限存取此票（403）：帳號可能沒有該 project 的讀取權限"
      echo ""
      _prompt_manual_jira "$ticket"
      return
      ;;
    404)
      echo "❌ 找不到票號 ${ticket}（404）"
      echo "   請確認票號正確，以及 JIRA_BASE_URL 設定為：${JIRA_BASE_URL}"
      echo ""
      _prompt_manual_jira "$ticket"
      return
      ;;
    "")
      echo "❌ 無法連線至 JIRA（curl 失敗，請確認網路與 JIRA URL）"
      echo "   JIRA_BASE_URL: ${JIRA_BASE_URL}"
      echo ""
      _prompt_manual_jira "$ticket"
      return
      ;;
    *)
      echo "❌ JIRA API 回應異常（HTTP ${http_code}）"
      # 嘗試顯示 API 的錯誤訊息
      local api_msg
      api_msg=$(echo "$response" | jq -r '
        if .errorMessages and (.errorMessages | length > 0) then .errorMessages[0]
        elif .message then .message
        else empty
        end' 2>/dev/null)
      [ -n "$api_msg" ] && echo "   訊息：${api_msg}"
      echo ""
      _prompt_manual_jira "$ticket"
      return
      ;;
  esac

  # ── 解析 JSON 回應 ──────────────────────────────────────

  # 確認是合法的 JSON 且有 .fields
  if ! echo "$response" | jq -e '.fields' &>/dev/null; then
    echo "❌ 回應不是預期格式（可能是非 JSON 內容）"
    echo "   回應前 200 字元：$(echo "$response" | head -c 200)"
    echo ""
    _prompt_manual_jira "$ticket"
    return
  fi

  # 標題
  JIRA_TITLE=$(echo "$response" | jq -r '.fields.summary // ""')

  # 描述：ADF（v3）是 object，v2 是純字串，分別處理
  local desc_raw
  desc_raw=$(echo "$response" | jq -r '.fields.description // ""' 2>/dev/null)

  if echo "$desc_raw" | jq -e 'type == "object"' &>/dev/null 2>&1; then
    # ADF 格式（v3）：遞迴取出所有 text 節點
    JIRA_DESCRIPTION=$(echo "$desc_raw" | \
      jq -r '[.. | objects | select(has("text") and (.type? == null or .type == "text")) | .text] | join(" ")' \
      2>/dev/null | head -c 3000)
  else
    # 純字串（v2）
    JIRA_DESCRIPTION=$(echo "$desc_raw" | head -c 3000)
  fi

  # Acceptance Criteria（嘗試常見自訂欄位）
  JIRA_ACCEPTANCE=$(echo "$response" | jq -r '
    .fields |
    (
      .customfield_10016 //
      .customfield_10034 //
      .customfield_acceptance_criteria //
      null
    ) |
    if type == "object" then
      [.. | objects | select(has("text") and (.type? == null or .type == "text")) | .text] | join(" ")
    elif type == "string" then .
    else ""
    end
  ' 2>/dev/null | head -c 2000)

  # fallback：從描述中擷取 Acceptance 段落
  if [ -z "$JIRA_ACCEPTANCE" ]; then
    JIRA_ACCEPTANCE=$(echo "$JIRA_DESCRIPTION" | \
      grep -A 20 -i "acceptance\|驗收\|AC:" | head -c 1000)
  fi

  JIRA_URL="${jira_host}/browse/${ticket}"

  if [ -z "$JIRA_TITLE" ]; then
    echo "⚠️  票名為空，請手動輸入："
    _prompt_manual_jira "$ticket"
    return
  fi

  echo "   ✓ ${JIRA_TITLE}"
}

# ── 手動輸入 fallback ─────────────────────────────────────

_prompt_manual_jira() {
  local ticket="$1"
  echo "請手動輸入票的資訊："
  echo ""
  read -r -p "票名稱（標題）: " JIRA_TITLE
  echo "功能說明（可多行，輸入空行結束）:"
  JIRA_DESCRIPTION=""
  while IFS= read -r line; do
    [ -z "$line" ] && break
    JIRA_DESCRIPTION="${JIRA_DESCRIPTION}${line} "
  done
  echo "驗收條件（可多行，輸入空行結束，無則直接 Enter）:"
  JIRA_ACCEPTANCE=""
  while IFS= read -r line; do
    [ -z "$line" ] && break
    JIRA_ACCEPTANCE="${JIRA_ACCEPTANCE}${line}\n"
  done
  JIRA_URL="${jira_host}/browse/${ticket}"
}
