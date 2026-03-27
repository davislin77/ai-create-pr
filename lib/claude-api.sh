#!/bin/bash
# claude-api.sh — 透過 Claude CLI (claude -p) 呼叫 Claude
# 沿用 Claude Code 已登入的帳號，不需要額外 API Key

# 呼叫 Claude
# 參數: $1=prompt檔案路徑, $2=輸出檔案路徑, $3=model(可選，預設sonnet)
call_claude() {
  local prompt_file="$1"
  local output_file="$2"
  local model="${3:-sonnet}"
  local raw_file="${output_file}.raw"

  cat "$prompt_file" | claude -p --model "$model" --output-format json > "$raw_file" 2>&1

  local exit_code=$?

  # 連線 / 執行失敗
  if [ $exit_code -ne 0 ]; then
    echo "❌ claude CLI 執行失敗（exit: ${exit_code}）" >&2
    cat "$raw_file" >&2
    echo "claude CLI 執行失敗" > "$output_file"
    echo '{"input_tokens":0,"output_tokens":0,"cost_usd":0}' > "${output_file}.usage"
    rm -f "$raw_file"
    return 1
  fi

  # 擷取回應內容
  jq -r '.result // empty' "$raw_file" > "$output_file"

  # 擷取 token 用量（claude -p --output-format json 的格式）
  jq '{
    input_tokens: (.usage.input_tokens // 0),
    output_tokens: (.usage.output_tokens // 0),
    cache_creation: (.usage.cache_creation_input_tokens // 0),
    cache_read: (.usage.cache_read_input_tokens // 0),
    cost_usd: (.total_cost_usd // 0)
  }' "$raw_file" > "${output_file}.usage" 2>/dev/null

  rm -f "$raw_file"
  return 0
}

# 從 usage 檔讀取費用（claude CLI 會直接給 total_cost_usd）
get_cost() {
  local usage_file="$1"
  jq -r '.cost_usd // 0' "$usage_file" 2>/dev/null | \
    awk '{printf "%.4f", $1}'
}
