#!/usr/bin/env bash

# === Configuração de Segurança e Robustez ===
# -e: Sair imediatamente se um comando falhar.
# -u: Tratar variáveis não definidas como um erro.
# -o pipefail: O status de saída de um pipeline é o do último comando que falhou.
set -euo pipefail

# === Variáveis e Constantes ===
readonly PHP_VERSION="8.2"
readonly PHP_PPA="ppa:ondrej/php"
readonly IONCUBE_URL="https://downloads.ioncube.com/loader_downloads/ioncube_loaders_lin_x86-64.tar.gz"

# Caminhos que serão usados com frequência
readonly PHP_MODS_AVAILABLE="/etc/php/${PHP_VERSION}/mods-available"
readonly PAM_INI_FILE="${PHP_MODS_AVAILABLE}/pam.ini"
readonly PHP_FPM_SERVICE="php${PHP_VERSION}-fpm"
readonly CLI_CONF_DIR="/etc/php/${PHP_VERSION}/cli/conf.d"
readonly FPM_CONF_DIR="/etc/php/${PHP_VERSION}/fpm/conf.d"

# === Funções ===

# Função para exibir mensagens de erro e sair
error_exit() {
  echo "ERRO: ${1}" >&2
  exit 1
}

# Função para verificar execução como root
check_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    error_exit "Este script precisa ser executado como root (ou com sudo)."
  fi
}

# Função para verificar se o PHP já está instalado
check_already_installed() {
  if dpkg-query -W -f='${Status}' "php${PHP_VERSION}-cli" 2>/dev/null | grep -q "ok installed"; then
    echo "INFO: PHP ${PHP_VERSION} (php${PHP_VERSION}-cli) parece já estar instalado. Saindo."
    exit 0
  fi
  echo ">>> PHP ${PHP_VERSION} não encontrado. Prosseguindo com a instalação."
}

# Função para instalar e configurar o ionCube Loader
install_ioncube() {
  echo ">>> 6. Instalando e Configurando ionCube Loader..."

  # Determina o diretório de extensões do PHP dinamicamente
  local php_ext_dir
  php_ext_dir=$(php-config --extension-dir) || error_exit "Não foi possível determinar o diretório de extensões do PHP. 'php-dev' está instalado?"
  echo "INFO: Diretório de extensões do PHP: ${php_ext_dir}"

  # Trabalha no diretório /tmp para não sujar o sistema
  cd /tmp || error_exit "Não foi possível acessar o diretório /tmp."

  echo "INFO: Baixando ionCube Loader..."
  wget -qO ioncube.tar.gz "${IONCUBE_URL}" || error_exit "Falha ao baixar o ionCube Loader."

  echo "INFO: Extraindo arquivos..."
  tar -xzf ioncube.tar.gz || error_exit "Falha ao extrair o ionCube Loader."

  local ioncube_loader_file="ioncube/ioncube_loader_lin_${PHP_VERSION}.so"
  if [[ ! -f "${ioncube_loader_file}" ]]; then
    error_exit "Loader do ionCube para PHP ${PHP_VERSION} não encontrado no arquivo baixado."
  fi

  echo "INFO: Copiando loader para ${php_ext_dir}..."
  cp "${ioncube_loader_file}" "${php_ext_dir}/" || error_exit "Falha ao copiar o loader do ionCube."

  # Conteúdo do arquivo .ini. Usamos zend_extension que é o recomendado para o ionCube.
  local ini_content="zend_extension = ${php_ext_dir}/$(basename "${ioncube_loader_file}")"

  echo "INFO: Habilitando ionCube para PHP CLI..."
  echo "${ini_content}" > "${CLI_CONF_DIR}/00-ioncube.ini" || error_exit "Falha ao criar arquivo de configuração do ionCube para CLI."

  echo "INFO: Habilitando ionCube para PHP FPM..."
  echo "${ini_content}" > "${FPM_CONF_DIR}/00-ioncube.ini" || error_exit "Falha ao criar arquivo de configuração do ionCube para FPM."

  echo "INFO: Limpando arquivos temporários do ionCube..."
  rm -rf ioncube.tar.gz ioncube

  echo ">>> ionCube Loader instalado com sucesso."
}


# Função principal de instalação
main() {
  check_root
  check_already_installed

  echo ">>> 1. Adicionando PPA ${PHP_PPA}..."
  apt-get update -y || error_exit "Falha ao atualizar lista de pacotes antes de adicionar PPA."
  apt-get install -y software-properties-common wget || error_exit "Falha ao instalar software-properties-common ou wget."
  add-apt-repository -y "${PHP_PPA}" || error_exit "Falha ao adicionar o PPA ${PHP_PPA}."

  echo ">>> 2. Atualizando lista de pacotes após adicionar PPA..."
  apt-get update -y || error_exit "Falha ao executar apt update após adicionar PPA."

  local php_extensions=(
    "cli" "fpm" "dev" "common" "bcmath" "imap" "redis" "snmp" "zip"
    "curl" "bz2" "intl" "gd" "mbstring" "mysql" "xml" "sqlite3" "pgsql"
  )
  local packages_to_install=()
  for ext in "${php_extensions[@]}"; do
    packages_to_install+=("php${PHP_VERSION}-${ext}")
  done

  echo ">>> 3. Instalando PHP ${PHP_VERSION} e extensões (${packages_to_install[*]})..."
  apt-get install -y "${packages_to_install[@]}" || error_exit "Falha ao instalar PHP ${PHP_VERSION} e/ou extensões."

  echo ">>> 4. Instalando dependências para a extensão PAM (PECL)..."
  apt-get install -y libpam0g-dev php-pear || error_exit "Falha ao instalar dependências para PECL/PAM."

  echo ">>> 5. Instalando extensão PAM via PECL..."
  pecl install pam || error_exit "Falha ao instalar a extensão PAM via PECL."

  if [[ ! -f "${PAM_INI_FILE}" ]]; then
    echo "AVISO: Arquivo ${PAM_INI_FILE} não encontrado após 'pecl install'. Tentando criar."
    echo "extension=pam.so" >"${PAM_INI_FILE}" || error_exit "Falha ao criar ${PAM_INI_FILE}."
  fi
  phpenmod pam || error_exit "Falha ao executar phpenmod para a extensão PAM."

  # --- NOVO PASSO: INSTALAR IONCUBE ---
  install_ioncube

  echo ">>> 7. Limpando cache do APT..."
  apt-get clean || echo "AVISO: Falha ao limpar o cache do APT."

  echo ">>> Verificando instalação final..."
  echo "-------------------------------------"
  php -v
  echo "-------------------------------------"
  echo "Verificando extensões PAM e ionCube:"
  if php -m | grep -q -i "pam"; then echo "✅ Extensão PAM: Carregada"; else echo "❌ Extensão PAM: NÃO encontrada"; fi
  if php -m | grep -q -i "ionCube"; then echo "✅ Extensão ionCube Loader: Carregada"; else echo "❌ Extensão ionCube Loader: NÃO encontrada"; fi
  echo "-------------------------------------"
  echo "Status do serviço PHP-FPM (${PHP_FPM_SERVICE}):"
  systemctl restart "${PHP_FPM_SERVICE}" || echo "AVISO: Falha ao reiniciar ${PHP_FPM_SERVICE}. Verifique manualmente."
  systemctl status "${PHP_FPM_SERVICE}" --no-pager || echo "AVISO: Falha ao obter status de ${PHP_FPM_SERVICE}."
  echo "-------------------------------------"

  echo ""
  echo "Instalação do PHP ${PHP_VERSION}, PAM e ionCube concluída com sucesso!"
  echo ""
  echo "Para gerenciar o serviço PHP-FPM:"
  echo "  sudo systemctl [start|stop|restart|status] ${PHP_FPM_SERVICE}"
  echo "Configurações principais do PHP estão em: /etc/php/${PHP_VERSION}/"
  echo "Lembre-se de configurar os pools do PHP-FPM em /etc/php/${PHP_VERSION}/fpm/pool.d/ conforme necessário."
}

# === Execução ===
main "$@"

exit 0