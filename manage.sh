#!/usr/bin/env bash
#
# LiteLLM Gemini 代理 · 管理菜单
#
# 用法: bash manage.sh
# 可用环境变量覆盖默认值: REGION / SERVICE_NAME / SA_NAME / SECRET_NAME / PROJECT_ID
#
set -euo pipefail

REGION="${REGION:-us-central1}"
SERVICE_NAME="${SERVICE_NAME:-litellm-gemini}"
SA_NAME="${SA_NAME:-litellm-gemini}"
SECRET_NAME="${SECRET_NAME:-litellm-config}"
PROJECT_ID="${PROJECT_ID:-}"

info() { echo -e "\033[1;32m[INFO]\033[0m $1"; }
warn() { echo -e "\033[1;33m[WARN]\033[0m $1"; }
err()  { echo -e "\033[1;31m[ERROR]\033[0m $1" >&2; }

command -v gcloud >/dev/null 2>&1 \
  || { err "未找到 gcloud 命令。请在 Google Cloud Shell 中运行本脚本。"; exit 1; }

[[ -z "$PROJECT_ID" ]] && PROJECT_ID="$(gcloud config get-value project 2>/dev/null || true)"
if [[ -z "$PROJECT_ID" || "$PROJECT_ID" == "(unset)" ]]; then
  err "无法确定 GCP 项目 ID。请先 'gcloud config set-project <PROJECT_ID>' 或 PROJECT_ID=xxx bash manage.sh"
  exit 1
fi
SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

# ---------- 功能: 查看服务信息 ----------
show_info() {
  echo ""
  echo "---------- 服务信息 ----------"
  echo "项目:     $PROJECT_ID"
  echo "区域:     $REGION"
  SERVICE_URL="$(gcloud run services describe "$SERVICE_NAME" \
    --region="$REGION" --project="$PROJECT_ID" --format='value(status.url)' 2>/dev/null || true)"
  if [[ -n "$SERVICE_URL" ]]; then
    echo "服务地址: $SERVICE_URL"
    echo "API 地址: $SERVICE_URL/v1"
  else
    warn "未找到服务 $SERVICE_NAME (区域 $REGION)。如部署在其他区域，请: REGION=xxx bash manage.sh"
  fi

  MASTER_KEY="$(gcloud secrets versions access latest --secret="$SECRET_NAME" \
    --project="$PROJECT_ID" 2>/dev/null | grep -E '^\s*master_key:' | awk '{print $2}' || true)"
  if [[ -n "$MASTER_KEY" ]]; then
    echo "API Key:  $MASTER_KEY"
  else
    warn "未读取到 Secret $SECRET_NAME 中的 master_key。"
  fi
  echo "------------------------------"
}

# ---------- 功能: 更新部署 ----------
redeploy() {
  if [[ -f "./deploy.sh" ]]; then
    bash ./deploy.sh
  else
    err "当前目录没有 deploy.sh。请在仓库目录中运行，或直接执行: bash deploy.sh"
  fi
}

# ---------- 功能: 卸载 ----------
delete_service() {
  info "删除 Cloud Run 服务 $SERVICE_NAME ..."
  gcloud run services delete "$SERVICE_NAME" --region="$REGION" --project="$PROJECT_ID" --quiet
  info "服务已删除。"
}

delete_secret() {
  info "删除 Secret $SECRET_NAME ..."
  gcloud secrets delete "$SECRET_NAME" --project="$PROJECT_ID" --quiet
  info "Secret 已删除。"
}

delete_sa() {
  info "移除 IAM 绑定 roles/aiplatform.user ..."
  gcloud projects remove-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="roles/aiplatform.user" --quiet >/dev/null 2>&1 || warn "IAM 绑定不存在或已移除。"
  info "删除服务账号 $SA_EMAIL ..."
  gcloud iam service-accounts delete "$SA_EMAIL" --project="$PROJECT_ID" --quiet
  info "服务账号已删除。"
}

confirm() {
  local reply
  read -rp "$1 [y/N]: " reply
  [[ "$reply" =~ ^[Yy]$ ]]
}

uninstall_all() {
  echo ""
  warn "即将删除以下全部资源:"
  echo "  1. Cloud Run 服务:  $SERVICE_NAME (区域 $REGION)"
  echo "  2. Secret:          $SECRET_NAME"
  echo "  3. IAM 绑定 + 服务账号: $SA_EMAIL"
  echo ""
  confirm "确认删除全部资源?" || { info "已取消。"; return; }

  gcloud run services describe "$SERVICE_NAME" --region="$REGION" --project="$PROJECT_ID" >/dev/null 2>&1 \
    && delete_service || warn "服务 $SERVICE_NAME 不存在，跳过。"
  gcloud secrets describe "$SECRET_NAME" --project="$PROJECT_ID" >/dev/null 2>&1 \
    && delete_secret || warn "Secret $SECRET_NAME 不存在，跳过。"
  gcloud iam service-accounts describe "$SA_EMAIL" --project="$PROJECT_ID" >/dev/null 2>&1 \
    && delete_sa || warn "服务账号 $SA_EMAIL 不存在，跳过。"

  echo ""
  info "全部资源已卸载。"
}

uninstall_selective() {
  echo ""
  echo "---------- 选择性卸载 ----------"
  echo "  1) 仅删除 Cloud Run 服务"
  echo "  2) 仅删除 Secret ($SECRET_NAME)"
  echo "  3) 仅删除服务账号及 IAM 绑定 ($SA_EMAIL)"
  echo "  0) 返回主菜单"
  echo "-------------------------------"
  local choice
  read -rp "请选择: " choice
  case "$choice" in
    1) confirm "确认删除服务 $SERVICE_NAME ?" && delete_service || info "已取消。" ;;
    2) confirm "确认删除 Secret $SECRET_NAME ?" && delete_secret || info "已取消。" ;;
    3) confirm "确认删除服务账号 $SA_EMAIL ?" && delete_sa || info "已取消。" ;;
    0) return ;;
    *) warn "无效选项。" ;;
  esac
}

# ---------- 主菜单 ----------
main() {
  while true; do
    echo ""
    echo "=============================================="
    echo -e "\033[1;36m  LiteLLM Gemini 代理 · 管理菜单\033[0m"
    echo "=============================================="
    echo "  项目: $PROJECT_ID | 区域: $REGION"
    echo "----------------------------------------------"
    echo "  1) 查看服务信息（地址 / API Key）"
    echo "  2) 更新部署（修改 config.yaml 后热更新）"
    echo "  3) 完整卸载（删除全部资源）"
    echo "  4) 选择性卸载（单删服务/Secret/服务账号）"
    echo "  0) 退出"
    echo "=============================================="
    local choice
    read -rp "请选择: " choice
    case "$choice" in
      1) show_info ;;
      2) redeploy ;;
      3) uninstall_all ;;
      4) uninstall_selective ;;
      0) info "再见！"; exit 0 ;;
      *) warn "无效选项，请输入 0-4。" ;;
    esac
  done
}

main
