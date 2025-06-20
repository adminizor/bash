#!/bin/bash

# ==============================================================================
# Script: setup_disk_quotas.sh (v2.1 - Correção de Grep)
# Descrição: Automatiza a instalação e configuração inicial do sistema de cotas
#            de disco na partição raiz (/) do Ubuntu. Projetado para ser
#            genérico e funcionar em diferentes configurações de /etc/fstab.
# Autor: Seu Nome/Apelido
# Data: [Data Atual]
# ==============================================================================

# --- Funções de Cor para Melhor Visualização ---
COLOR_GREEN='\033[0;32m'
COLOR_YELLOW='\033[1;33m'
COLOR_RED='\033[0;31m'
COLOR_NC='\033[0m' # No Color

# --- Verificação Inicial ---
if [ "$(id -u)" -ne 0 ]; then
  echo -e "${COLOR_RED}Erro: Este script precisa ser executado como root.${COLOR_NC}"
  echo "Por favor, use: sudo ./setup_disk_quotas.sh"
  exit 1
fi

echo -e "${COLOR_GREEN}--- Iniciando a Configuração do Sistema de Cotas de Disco ---${COLOR_NC}"

# --- Passo 1: Instalar as Ferramentas de Cota ---
echo -e "\n${COLOR_YELLOW}[1/6] Instalando o pacote 'quota'...${COLOR_NC}"
if ! dpkg -s quota &> /dev/null; then
    apt-get update > /dev/null 2>&1
    apt-get install quota -y
    if [ $? -ne 0 ]; then
        echo -e "${COLOR_RED}Falha ao instalar o pacote 'quota'. Abortando.${COLOR_NC}"
        exit 1
    fi
    echo -e "${COLOR_GREEN}Pacote 'quota' instalado com sucesso.${COLOR_NC}"
else
    echo -e "${COLOR_GREEN}Pacote 'quota' já está instalado.${COLOR_NC}"
fi


# --- Passo 2: Habilitar Cotas na Partição Raiz (Lógica Robusta) ---
FSTAB_FILE="/etc/fstab"
echo -e "\n${COLOR_YELLOW}[2/6] Verificando e configurando o arquivo /etc/fstab...${COLOR_NC}"

# Encontra a linha da partição raiz (/), ignorando linhas comentadas
ROOT_LINE=$(grep -E "^\S+\s+/\s+" "$FSTAB_FILE" | grep -v "^#")

if [ -z "$ROOT_LINE" ]; then
    echo -e "${COLOR_RED}Não foi possível encontrar uma entrada de configuração ativa para a partição raiz (/) no $FSTAB_FILE. Abortando.${COLOR_NC}"
    exit 1
fi

# Verifica se as cotas já estão habilitadas
if echo "$ROOT_LINE" | grep -q "usrquota"; then
  echo -e "${COLOR_GREEN}Cotas já parecem estar configuradas no $FSTAB_FILE. Pulando esta etapa.${COLOR_NC}"
else
  echo "Fazendo backup de $FSTAB_FILE para $FSTAB_FILE.bak..."
  cp "$FSTAB_FILE" "$FSTAB_FILE.bak"

  # Lê os campos da linha da partição raiz em variáveis separadas
  read -r device mountpoint fstype options dump pass <<< "$ROOT_LINE"

  # Adiciona as opções de cota à coluna de opções
  NEW_OPTIONS="${options},usrquota,grpquota"

  # Cria a nova linha completa
  NEW_ROOT_LINE="$device $mountpoint $fstype $NEW_OPTIONS $dump $pass"

  # Usa 'sed' para substituir a linha antiga pela nova.
  # O caractere '#' é usado como delimitador para evitar conflito com o '/' no ponto de montagem.
  sed -i "s#${ROOT_LINE}#${NEW_ROOT_LINE}#" "$FSTAB_FILE"

  # Verificação final
  if grep -q "usrquota" "$FSTAB_FILE" && grep -q "$NEW_ROOT_LINE" "$FSTAB_FILE"; then
    echo -e "${COLOR_GREEN}Opções de cota adicionadas com sucesso ao $FSTAB_FILE.${COLOR_NC}"
  else
    echo -e "${COLOR_RED}Falha ao modificar o $FSTAB_FILE. Restaurando backup e abortando.${COLOR_NC}"
    cp "$FSTAB_FILE.bak" "$FSTAB_FILE"
    exit 1
  fi
fi

# --- Passo 3: Remontar a Partição ---
echo -e "\n${COLOR_YELLOW}[3/6] Remontando a partição raiz (/) para aplicar as mudanças...${COLOR_NC}"
mount -o remount /
if [ $? -ne 0 ]; then
    echo -e "${COLOR_RED}Falha ao remontar a partição raiz. Uma reinicialização pode ser necessária. Abortando.${COLOR_NC}"
    exit 1
fi

systemctl daemon-reload
echo -e "${COLOR_GREEN}Partição remontada e daemon do systemd recarregado com sucesso.${COLOR_NC}"

# --- Passo 4: Criar Arquivos de Banco de Dados da Cota ---
echo -e "\n${COLOR_YELLOW}[4/6] Criando os arquivos de banco de dados da cota (aquota.user, aquota.group)...${COLOR_NC}"
quotacheck -cugm /
echo -e "${COLOR_GREEN}Arquivos de cota criados.${COLOR_NC}"

# --- Passo 5: Ativar o Sistema de Cotas ---
echo -e "\n${COLOR_YELLOW}[5/6] Ativando o sistema de cotas...${COLOR_NC}"
quotaon -v /
if [ $? -ne 0 ]; then
    echo -e "${COLOR_RED}Falha ao ativar o sistema de cotas. Verifique os logs. Abortando.${COLOR_NC}"
    exit 1
fi
echo -e "${COLOR_GREEN}Sistema de cotas ativado.${COLOR_NC}"

# --- Passo 6: Verificação Final ---
echo -e "\n${COLOR_YELLOW}[6/6] Exibindo o relatório de cotas para verificação...${COLOR_NC}"
repquota -a

echo -e "\n${COLOR_GREEN}--- Configuração do Sistema de Cotas Concluída! ---${COLOR_NC}"
echo "O sistema agora está pronto para que você defina cotas para usuários individuais."
echo "Use o comando 'sudo edquota -u <nome_do_usuario>' para definir os limites."

exit 0