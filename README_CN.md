# LiteLLM Gemini 代理 · 一键部署（GCP Cloud Run · Keyless）

[English](./README.md) | 简体中文

在 GCP Cloud Run 上一键部署 [LiteLLM](https://github.com/BerriAI/Litellm) 代理服务，将客户端（Cherry Studio、CC Switch、Claude Code 等）的请求转译至 Vertex AI 调用 Gemini 模型。

**核心优势：全程 Keyless** —— 无须导出任何服务账号密钥文件，避免账号风控；费用走 Vertex AI，优先扣除 GCP 新用户 **$300 赠金**。

## 特性

- 一条命令完成部署，自动处理 API 开启、服务账号、IAM 授权、Secret Manager、Cloud Run 全流程
- Keyless 架构：Cloud Run 通过服务账号直连 Vertex AI，本地零密钥文件
- OpenAI & Claude 双兼容：`/v1` OpenAI 格式端点，内置 `claude-sonnet-4-6` 等 Claude 别名自动转发至 Gemini
- `drop_params` 自动忽略客户端非标准参数，防止 400 报错
- 配置存于 Secret Manager，编辑 `config.yaml` 后重跑脚本即可热更新模型列表
- API Key 默认随机生成，可通过管理菜单随时查看
- 交互式管理菜单：查看信息 / 热更新 / 完整卸载 / 选择性卸载

## 前置条件

- 一个 GCP 账号（新用户注册可获得 [$300 赠金](https://cloud.google.com/free)）
- 打开 [Google Cloud Shell](https://shell.cloud.google.com)（推荐，开箱即用），或在本地安装并登录 [gcloud CLI](https://cloud.google.com/sdk/docs/install)

## 快速开始

```bash
git clone https://github.com/lilinle1/litellm-gemini-oneclick.git
cd litellm-gemini-oneclick
bash deploy.sh
```

或免克隆直接运行：

```bash
curl -fsSL https://raw.githubusercontent.com/lilinle1/litellm-gemini-oneclick/main/deploy.sh | bash
```

部署完成后会打印服务地址与 API Key：

```
==============================================
  部署成功！
==============================================
  服务地址:  https://litellm-gemini-xxxx.us-central1.run.app
  API 地址:  https://litellm-gemini-xxxx.us-central1.run.app/v1
  API Key:   sk-a3f8...(随机生成，请务必保存)
==============================================
```

### 自定义参数

| 参数 | 环境变量 | 默认值 | 说明 |
|---|---|---|---|
| `--region` | `REGION` | `us-central1` | Cloud Run 区域 |
| `--project` | `PROJECT_ID` | gcloud 当前项目 | GCP 项目 ID |
| `--service` | `SERVICE_NAME` | `litellm-gemini` | 服务名 |
| `--key` | `MASTER_KEY` | 随机生成 | 自定义 API Key |
| `--memory` | `MEMORY` | `2048M` | 容器内存（低于此值易 OOM） |
| `--cpu` | `CPU` | `2` | 容器 CPU |

示例：

```bash
bash deploy.sh --region=asia-east1 --key=sk-my-key
```

## 客户端配置

| 客户端 | 配置 |
|---|---|
| **Cherry Studio** | 提供商类型：OpenAI 兼容；API 地址：`https://<服务地址>/v1`；API Key：部署时生成的 Key；模型：`gemini-3.8-flash` / `gemini-3.7-flash` / `gemini-2.5-pro` 等 |
| **CC Switch / Claude 客户端** | 端点：`https://<服务地址>/v1`（末尾不加斜杠）；**上游格式必须选 OpenAI Chat Completions**；模型保持客户端默认即可（如 `claude-opus-5-5`、`claude-sonnet-5-5` 等别名会按档位自动重定向至同档 Gemini）。注意：原生 Anthropic Messages 格式（`/v1/messages`）不受支持 |

预置模型列表：

**Gemini 原生模型**

| 模型名 | 说明 |
|---|---|
| `gemini-3.8-flash` | 最新旗舰（2026-09 GA） |
| `gemini-3.7-flash` | 上代旗舰 |
| `gemini-3.1-pro` | Pro 系列（preview，两个名字均可） |
| `gemini-2.5-pro` | 推理增强 |
| `gemini-2.5-flash` | 均衡 |
| `gemini-2.5-flash-lite` | 快速低价 |

**Claude 别名（按档位映射至同档 Gemini，仅 OpenAI 协议生效）**

| Claude 模型名 | 映射至 |
|---|---|
| `claude-opus-5-5` / `claude-opus-5` / `claude-fable-5-1` / `claude-fable-5` | `gemini-3.8-flash` |
| `claude-sonnet-5-5` / `claude-sonnet-5` / `claude-sonnet-4-6` / `claude-3-7-sonnet-20250219` / `claude-haiku-4-5` / `claude-haiku-4-5-20251001` | `gemini-3.7-flash` |

> Claude 别名仅对 OpenAI 协议的请求生效；Anthropic 原生协议（`/v1/messages`）请改用 OpenAI 格式接入。

## 管理菜单

```bash
bash manage.sh
```

```
==============================================
  LiteLLM Gemini 代理 · 管理菜单
==============================================
  1) 查看服务信息（地址 / API Key）
  2) 更新部署（修改 config.yaml 后热更新）
  3) 完整卸载（删除全部资源）
  4) 选择性卸载（单删服务/Secret/服务账号）
  0) 退出
==============================================
```

忘记 API Key？运行菜单选项 1 即可查看。

## 更新模型列表

1. 编辑本地 `config.yaml`（部署脚本会在当前目录生成），按已有格式添加模型条目；
2. 重新运行 `bash deploy.sh`（或菜单选项 2），配置会推送至 Secret Manager 并自动重新部署。

## 常见问题

- **为什么内存要 2048M？** LiteLLM 在低内存配置下容易 OOM 崩溃，默认值已足够。
- **为什么用 `global` 区域？** Gemini 最新系列模型必须通过 Vertex AI 的 `global` 区域调用。
- **`--allow-unauthenticated` 安全吗？** 服务虽允许匿名访问，但所有请求必须携带随机生成的 `master_key` 才能调用，请勿泄露 Key。
- **费用怎么算？** 全部走 Vertex AI 计费，新账号优先消耗 $300 赠金，部署在 Cloud Run 本身有免费额度。

## 卸载

```bash
bash manage.sh   # 选择 3 完整卸载，或选择 4 按需单独删除
```

## 许可证

[MIT](./LICENSE)
