# ai-create-pr

在 macOS執行，自動根據 JIRA 票與 git branch 產出 GitHub PR 描述的 markdown 檔案。

PR 內容由 Claude AI 產生，費用計入執行者的 Claude Code 帳號。

---

## 需求

| 工具 | 說明 | 安裝方式 |
|------|------|---------|
| [Claude Code](https://claude.ai/download) | AI 引擎，需已登入 | 官網下載 |
| `git` | 取得本地 branch 差異 | 內建或 `brew install git` |
| `jq` | 解析 JSON | `brew install jq` |
| `curl` | 呼叫 API | macOS 內建 |
| `gh`（選用） | GitHub CLI，用於 GitHub OAuth 與 API | `brew install gh` |

---

## 安裝

```bash
# 1. 下載此資料夾到任意位置
# 2. 允許 macOS 執行（只需一次）
xattr -d com.apple.quarantine /path/to/ai-create-pr/create-pr.command
```

---

## 使用方式

在 Finder 中**雙擊** `create-pr.command`，Terminal 會自動開啟並引導完成以下步驟：

### 第一次執行：憑證設定

程式會自動偵測缺少的憑證並引導設定：

**GitHub**
- 若已安裝 `gh`：自動開啟瀏覽器進行 OAuth 授權
- 否則：開啟 GitHub 的 Personal Access Token 頁面，貼回 token

**JIRA**
1. 輸入公司 JIRA 網址（例：`https://yourcompany.atlassian.net`）
2. 輸入 Atlassian 帳號 Email（請至 [id.atlassian.com](https://id.atlassian.com) 確認帳號 email）
3. 開啟 [Atlassian API Token 頁面](https://id.atlassian.com/manage-profile/security/api-tokens)，建立 token 後貼回

> 憑證儲存於資料夾內的 `.credentials`（不會上傳至 git）

### 每次執行流程

```
1. 選擇 JIRA 專案（例：Owlnest (OW)）
2. 輸入票號數字（例：1234）→ 組合為 OW-1234
3. 輸入 Feature Branch（來源 branch）
4. 輸入 Target Branch（預設 main）
5. 選擇 Repository（本地資料夾 或 GitHub URL）
```

程式接著自動：
- 從 JIRA 取得票的標題、描述、驗收條件
- 從 git（本地或 GitHub API）取得 commits、變動檔案、diff 統計
- 呼叫 Claude 產生 PR 描述
- 將結果存入 `results/` 資料夾

### 輸出格式

```markdown
## Issues
- [OW-1234] 票名稱

## Description
- reproduce steps
  - ...
- expected
  - ...

## Modification
- 說明程式改了什麼、為什麼

[OW-1234]: https://yourcompany.atlassian.net/browse/OW-1234
```

輸出檔案命名為 `results/PR_OW-1234_時間戳.md`

---

## 選單管理

### JIRA 專案

常用專案可儲存，下次直接選取：

```
📋 選擇 JIRA 專案：

  [1] Owlnest (OW)
  [2] Backend (BE)
  ────────────────────────
  [3] 新增專案...
```

新增時輸入名稱與 Prefix，儲存至 `.jira-projects`。

### Repository

支援本地資料夾與 GitHub URL 兩種來源：

```
📁 選擇 Repository：

  [1] PMS              📂 local
  [2] Owlting-UI       🐙 github
  ────────────────────────
  [3] 新增本地 repo...
  [4] 新增 GitHub URL...
```

| 來源 | 特性 |
|------|------|
| 本地 📂 | 可讀取未 push 的 commit，資料完整 |
| GitHub 🐙 | 不需 clone，只需已 push 的 branch |

儲存至 `.repo-config`。

---

## 檔案結構

```
ai-create-pr/
├── create-pr.command      # 主程式，Finder 雙擊執行
├── lib/
│   ├── auth.sh            # GitHub / JIRA 憑證管理
│   ├── jira-project.sh    # JIRA 專案選單
│   ├── repo-config.sh     # Repository 選單
│   ├── git-helper.sh      # 本地 git / GitHub API 取得 diff
│   ├── jira.sh            # JIRA REST API
│   └── claude-api.sh      # Claude CLI 呼叫
├── prompts/
│   └── create-pr.md       # Claude prompt 模板
├── results/               # 輸出的 PR markdown 檔案
├── .credentials           # 憑證（自動建立，gitignore）
├── .jira-projects         # JIRA 專案清單（自動建立，gitignore）
└── .repo-config           # Repository 清單（自動建立，gitignore）
```

---

## 重設憑證

執行時在憑證狀態顯示後輸入 `r`：

```
🔧 重設憑證？（直接 Enter 跳過）[r]: r

🔧 重設憑證
  [1] GitHub
  [2] JIRA
  [3] 全部重設
  [0] 取消
```

---

## 注意事項

- JIRA Email 必須與 Atlassian 帳號的登入 email 一致，請至 [id.atlassian.com](https://id.atlassian.com) 確認
- GitHub URL 來源只能讀取已 push 到遠端的 branch
- Token 用量與費用在每次執行結束後顯示於 Terminal
