#!/usr/bin/env bash
#
# One-click deploy: LiteLLM Gemini proxy on GCP Cloud Run (Keyless, Vertex AI)
#
# 部署完成后会打印服务地址和 API Key，请妥善保存。
# 用法: bash deploy.sh [选项]
#
set -euo pipefail

# ---------- 默认配置（可用环境变量或命令行参数覆盖） ----------
REGION="${REGION:-us-central1}"
SERVICE_NAME="${SERVICE_NAME:-litellm-gemini}"
SA_NAME="${SA_NAME:-litellm-gemini}"
SECRET_NAME="${SECRET_NAME:-litellm-config}"
MEMORY="${MEMORY:-2048M}"
CPU="${CPU:-2}"
MASTER_KEY="${MASTER_KEY:-}"
PROJECT_ID="${PROJECT_ID:-}"

usage() {
  cat << EOF
一键部署 LiteLLM Gemini 代理 (GCP Cloud Run + Vertex AI, Keyless)

用法: bash deploy.sh [选项]

选项:
  -r, --region <REGION>      Cloud Run 区域        (默认: us-central1)
  -p, --project <PROJECT_ID> GCP 项目 ID           (默认: gcloud 当前项目)
  -s, --service <NAME>       Cloud Run 服务名      (默认: litellm-gemini)
  -k, --key <KEY>            自定义 API Key        (默认: 自动随机生成)
  -m, --memory <MEM>         容器内存              (默认: 2048M, 低于此值易 OOM)
  -c, --cpu <CPU>            容器 CPU              (默认: 2)
  -h, --help                 显示帮助

示例:
  bash deploy.sh
  bash deploy.sh --region=asia-east1 --key=sk-my-key
  REGION=us-central1 bash deploy.sh
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -r|--region)      REGION="$2"; shift 2 ;;
    --region=*)       REGION="${1#*=}"; shift ;;
    -p|--project)     PROJECT_ID="$2"; shift 2 ;;
    --project=*)      PROJECT_ID="${1#*=}"; shift ;;
    -s|--service)     SERVICE_NAME="$2"; shift 2 ;;
    --service=*)      SERVICE_NAME="${1#*=}"; shift ;;
    -k|--key)         MASTER_KEY="$2"; shift 2 ;;
    --key=*)          MASTER_KEY="${1#*=}"; shift ;;
    -m|--memory)      MEMORY="$2"; shift 2 ;;
    --memory=*)       MEMORY="${1#*=}"; shift ;;
    -c|--cpu)         CPU="$2"; shift 2 ;;
    --cpu=*)          CPU="${1#*=}"; shift ;;
    -h|--help)        usage; exit 0 ;;
    *) echo "未知选项: $1"; usage; exit 1 ;;
  esac
done

info() { echo -e "\033[1;32m[INFO]\033[0m $1"; }
warn() { echo -e "\033[1;33m[WARN]\033[0m $1"; }
die()  { echo -e "\033[1;31m[ERROR]\033[0m $1" >&2; exit 1; }

# ---------- 环境检查 ----------
command -v gcloud >/dev/null 2>&1 \
  || die "未找到 gcloud 命令。请在 Google Cloud Shell 中运行本脚本，或先安装 gcloud CLI。"

[[ -z "$PROJECT_ID" ]] && PROJECT_ID="$(gcloud config get-value project 2>/dev/null || true)"
[[ -z "$PROJECT_ID" || "$PROJECT_ID" == "(unset)" ]] \
  && die "无法确定 GCP 项目 ID。请先 'gcloud config set-project <PROJECT_ID>' 或用 --project 指定。"

ACTIVE_ACCOUNT="$(gcloud auth list --filter=status:ACTIVE --format='value(account)' 2>/dev/null || true)"
[[ -z "$ACTIVE_ACCOUNT" ]] && die "gcloud 未登录。请先运行 'gcloud auth login'。"

SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

echo "=============================================="
echo "  LiteLLM Gemini 代理 · 一键部署"
echo "=============================================="
echo "  项目:     $PROJECT_ID"
echo "  区域:     $REGION"
echo "  服务名:   $SERVICE_NAME"
echo "  服务账号: $SA_EMAIL"
echo "=============================================="
echo ""

# ---------- 第 1 步: 开启 API ----------
info "开启所需 API (run / aiplatform / secretmanager)..."
gcloud services enable run.googleapis.com aiplatform.googleapis.com secretmanager.googleapis.com \
  --project="$PROJECT_ID" >/dev/null
info "API 已开启。"

# ---------- 第 2 步: 服务账号与授权 ----------
if gcloud iam service-accounts describe "$SA_EMAIL" --project="$PROJECT_ID" >/dev/null 2>&1; then
  info "服务账号已存在: $SA_EMAIL"
else
  info "创建服务账号 $SA_NAME..."
  gcloud iam service-accounts create "$SA_NAME" \
    --display-name="LiteLLM Gemini proxy" \
    --project="$PROJECT_ID"
fi

info "授予 Vertex AI 用户权限 (roles/aiplatform.user)..."
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="roles/aiplatform.user" \
  --quiet >/dev/null
info "IAM 授权完成。"

# ---------- 第 3 步: 生成 master key ----------
GENERATED_KEY=0
if [[ -z "$MASTER_KEY" ]]; then
  MASTER_KEY="sk-$(openssl rand -hex 16 2>/dev/null \
    || head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n')"
  GENERATED_KEY=1
fi

# ---------- 第 4 步: 生成 LiteLLM 配置 ----------
info "生成 LiteLLM 配置 (config.yaml)..."
cat << EOF > config.yaml
model_list:
  # Gemini 系列（新模型必须使用 global 区域）
  - model_name: gemini-3.8-flash
    litellm_params:
      model: vertex_ai/gemini-3.8-flash
      vertex_project: "${PROJECT_ID}"
      vertex_location: "global"

  - model_name: gemini-3.7-flash
    litellm_params:
      model: vertex_ai/gemini-3.7-flash
      vertex_project: "${PROJECT_ID}"
      vertex_location: "global"

  - model_name: gemini-2.5-pro
    litellm_params:
      model: vertex_ai/gemini-2.5-pro
      vertex_project: "${PROJECT_ID}"
      vertex_location: "global"

  - model_name: gemini-2.5-flash
    litellm_params:
      model: vertex_ai/gemini-2.5-flash
      vertex_project: "${PROJECT_ID}"
      vertex_location: "global"

  - model_name: gemini-2.5-flash-lite
    litellm_params:
      model: vertex_ai/gemini-2.5-flash-lite
      vertex_project: "${PROJECT_ID}"
      vertex_location: "global"

  # Claude 客户端别名（仅 OpenAI 协议客户端生效，按 Claude 档位映射至同档 Gemini）
  # 旗舰档 Opus / Fable → Gemini 3.8 Flash
  - model_name: claude-opus-5-5
    litellm_params:
      model: vertex_ai/gemini-3.8-flash
      vertex_project: "${PROJECT_ID}"
      vertex_location: "global"

  - model_name: claude-opus-5
    litellm_params:
      model: vertex_ai/gemini-3.8-flash
      vertex_project: "${PROJECT_ID}"
      vertex_location: "global"

  - model_name: claude-fable-5-1
    litellm_params:
      model: vertex_ai/gemini-3.8-flash
      vertex_project: "${PROJECT_ID}"
      vertex_location: "global"

  - model_name: claude-fable-5
    litellm_params:
      model: vertex_ai/gemini-3.8-flash
      vertex_project: "${PROJECT_ID}"
      vertex_location: "global"

  # 均衡档 Sonnet → Gemini 3.7 Flash
  - model_name: claude-sonnet-5-5
    litellm_params:
      model: vertex_ai/gemini-3.7-flash
      vertex_project: "${PROJECT_ID}"
      vertex_location: "global"

  - model_name: claude-sonnet-5
    litellm_params:
      model: vertex_ai/gemini-3.7-flash
      vertex_project: "${PROJECT_ID}"
      vertex_location: "global"

  - model_name: claude-sonnet-4-6
    litellm_params:
      model: vertex_ai/gemini-3.7-flash
      vertex_project: "${PROJECT_ID}"
      vertex_location: "global"

  - model_name: claude-3-7-sonnet-20250219
    litellm_params:
      model: vertex_ai/gemini-3.7-flash
      vertex_project: "${PROJECT_ID}"
      vertex_location: "global"

  # 轻量档 Haiku → Gemini 3.7 Flash
  - model_name: claude-haiku-4-5
    litellm_params:
      model: vertex_ai/gemini-3.7-flash
      vertex_project: "${PROJECT_ID}"
      vertex_location: "global"

  - model_name: claude-haiku-4-5-20251001
    litellm_params:
      model: vertex_ai/gemini-3.7-flash
      vertex_project: "${PROJECT_ID}"
      vertex_location: "global"

litellm_settings:
  drop_params: true  # 自动忽略客户端传入的 store 等非标准参数，防止 400 报错

general_settings:
  master_key: ${MASTER_KEY}
EOF
info "配置已生成。"

# ---------- 第 5 步: 存入 Secret Manager ----------
if gcloud secrets describe "$SECRET_NAME" --project="$PROJECT_ID" >/dev/null 2>&1; then
  info "更新 Secret $SECRET_NAME（新增版本）..."
  gcloud secrets versions add "$SECRET_NAME" --data-file=config.yaml --project="$PROJECT_ID"
else
  info "创建 Secret $SECRET_NAME..."
  gcloud secrets create "$SECRET_NAME" \
    --data-file=config.yaml \
    --replication-policy="automatic" \
    --project="$PROJECT_ID"
fi

info "授权服务账号读取 Secret..."
gcloud secrets add-iam-policy-binding "$SECRET_NAME" \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="roles/secretmanager.secretAccessor" \
  --project="$PROJECT_ID" >/dev/null
info "Secret 就绪。"

# ---------- 第 6 步: 部署 Cloud Run ----------
info "部署 Cloud Run 服务（约需 1-3 分钟）..."
gcloud run deploy "$SERVICE_NAME" \
  --image=ghcr.io/berriai/litellm:main-latest \
  --region="$REGION" \
  --project="$PROJECT_ID" \
  --platform=managed \
  --allow-unauthenticated \
  --port=4000 \
  --memory="$MEMORY" \
  --cpu="$CPU" \
  --service-account="$SA_EMAIL" \
  --set-secrets="/secrets/config.yaml=${SECRET_NAME}:latest" \
  --args="--config=/secrets/config.yaml,--port=4000"

SERVICE_URL="$(gcloud run services describe "$SERVICE_NAME" \
  --region="$REGION" --project="$PROJECT_ID" --format='value(status.url)')"

# ---------- 第 7 步: 等待服务就绪 ----------
info "等待服务健康检查通过..."
READY=0
for _ in $(seq 1 30); do
  if curl -sf "${SERVICE_URL}/health/liveliness" >/dev/null 2>&1; then READY=1; break; fi
  sleep 2
done
if [[ "$READY" == "1" ]]; then
  info "服务已就绪。"
else
  warn "服务暂未通过健康检查（可能仍在启动），请稍后重试: ${SERVICE_URL}/health/liveliness"
fi

# ---------- 完成 ----------
echo ""
echo "=============================================="
echo -e "\033[1;36m  部署成功！\033[0m"
echo "=============================================="
echo "  服务地址:  $SERVICE_URL"
echo "  API 地址:  $SERVICE_URL/v1"
echo "  API Key:   $MASTER_KEY"
[[ "$GENERATED_KEY" == "1" ]] && echo "  (Key 为本次随机生成，请务必保存；忘记可用 manage.sh 查看)"
echo ""
echo "  客户端配置（Cherry Studio / CC Switch 等）:"
echo "    提供商类型: OpenAI 兼容"
echo "    API 地址:   $SERVICE_URL/v1"
echo "    API Key:    $MASTER_KEY"
echo "    模型名称:   gemini-3.7-flash / gemini-2.5-flash"
echo "                (Claude 客户端可直接用 claude-sonnet-4-6 别名)"
echo "=============================================="
echo ""
info "本地保留了 config.yaml，之后添加/修改模型可编辑它并重新运行本脚本完成热更新。"
