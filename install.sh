#!/bin/bash
# ================================================
# Setup Automático: Ollama + Cloudflare Tunnel
# Para Mac Mini M4 (16GB) como servidor de coding
# ================================================

set -e  # Para o script se der erro

echo "🚀 Iniciando setup do servidor Ollama + Cloudflare Tunnel..."

# 1. Instalar Homebrew (caso não tenha)
if ! command -v brew &> /dev/null; then
    echo "Instalando Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> \~/.zprofile
    eval "$(/opt/homebrew/bin/brew shellenv)"
fi

# 2. Instalar Ollama e cloudflared
echo "Instalando Ollama e cloudflared..."
brew install ollama cloudflared

# 3. Configurar Ollama como serviço (inicia no boot)
echo "Configurando Ollama como serviço..."
brew services start ollama

# 4. Configurar Ollama para aceitar conexões (necessário para tunnel)
echo "Configurando OLLAMA_HOST=0.0.0.0:11434..."
cat << EOF | sudo tee /Library/LaunchDaemons/com.ollama.plist > /dev/null
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.ollama</string>
    <key>ProgramArguments</key>
    <array>
        <string>/opt/homebrew/bin/ollama</string>
        <string>serve</string>
    </array>
    <key>EnvironmentVariables</key>
    <dict>
        <key>OLLAMA_HOST</key>
        <string>0.0.0.0:11434</string>
        <key>OLLAMA_ORIGINS</key>
        <string>*</string>
    </dict>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
</dict>
</plist>
EOF

sudo launchctl unload /Library/LaunchDaemons/com.ollama.plist 2>/dev/null || true
sudo launchctl load /Library/LaunchDaemons/com.ollama.plist

# 5. Baixar modelo recomendado para coding no M4 16GB
echo "Baixando modelo Qwen2.5-Coder 7B (melhor equilíbrio para seu hardware)..."
ollama pull qwen2.5-coder:7b

# Opcional: se quiser testar o 14B (mais inteligente, mas mais lento)
# ollama pull qwen2.5-coder:14b

echo "✅ Ollama configurado com sucesso!"

# 6. Cloudflare Tunnel
echo ""
echo "=== Cloudflare Tunnel ==="
echo "Agora vamos configurar o túnel."

read -p "Digite o nome do túnel (ex: ollama-coding-mac): " TUNNEL_NAME

# Criar túnel nomeado (se ainda não existir)
if ! cloudflared tunnel list | grep -q "$TUNNEL_NAME"; then
    echo "Criando túnel '$TUNNEL_NAME'..."
    cloudflared tunnel create "$TUNNEL_NAME"
else
    echo "Túnel '$TUNNEL_NAME' já existe."
fi

# Pegar o UUID do túnel
TUNNEL_UUID=$(cloudflared tunnel list | grep "$TUNNEL_NAME" | awk '{print $1}')

echo ""
echo "🔗 Vá até o dashboard do Cloudflare agora:"
echo "https://dash.cloudflare.com → Zero Trust → Networks → Tunnels"
echo ""
echo "1. Selecione o túnel '$TUNNEL_NAME'"
echo "2. Clique em 'Configure' ou 'Public Hostname'"
echo "3. Adicione um Public Hostname:"
echo "   - Subdomain: ollama (ou coding, ai, etc.)"
echo "   - Domain: seu domínio (ex: exemplo.com)"
echo "   - Service: http://localhost:11434"
echo "   - HTTP Host Header: localhost:11434   ← IMPORTANTE para Ollama"
echo ""
echo "Depois de salvar no dashboard, pressione ENTER aqui para continuar..."

read -p "Pressione ENTER quando terminar a configuração no dashboard..."

# Criar config do túnel como serviço
cat << EOF | sudo tee /etc/cloudflared/config.yml > /dev/null
tunnel: $TUNNEL_UUID
credentials-file: /Users/\( (whoami)/.cloudflared/ \){TUNNEL_UUID}.json

ingress:
  - hostname: ollama.seudominio.com      # ← MUDE para o que você configurou
    service: http://localhost:11434
    http-host-header: "localhost:11434"
  - service: http_status:404
EOF

# Instalar como serviço no macOS
sudo cloudflared service install

echo ""
echo "✅ Setup concluído!"
echo ""
echo "=== Como usar no seu PC Windows (VS Code Copilot Chat) ==="
echo "URL do seu servidor: https://ollama.seudominio.com"
echo ""
echo "No VS Code:"
echo "1. Abra GitHub Copilot Chat"
echo "2. Vá em Manage Models ou Language Models"
echo "3. Adicione um modelo OpenAI Compatible:"
echo "   - Base URL: https://ollama.seudominio.com/v1"
echo "   - Model: qwen2.5-coder:7b"
echo "4. Selecione esse modelo no chat e teste no modo Agent"
echo ""
echo "Dicas importantes:"
echo "- O Mac Mini pode dormir a tela (não precisa ficar com monitor ligado)"
echo "- Use um domínio que você gerencia no Cloudflare"
echo "- Cloudflare Tunnel adiciona HTTPS automaticamente (ótimo para Copilot)"
echo "- Para mais segurança, ative Access Policies no Zero Trust (email, etc.)"

echo "Deseja reiniciar os serviços agora? (s/n)"
read restart
if [[ $restart == "s" || $restart == "S" ]]; then
    brew services restart ollama
    sudo launchctl stop com.cloudflare.cloudflared
    sudo launchctl start com.cloudflare.cloudflared
    echo "Serviços reiniciados!"
fi
