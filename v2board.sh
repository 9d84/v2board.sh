#!/bin/bash
#
# v2board.sh
# https://github.com/9d84/v2board.sh

# 颜色输出
echo_content() {
    color=$1
    shift
    if [[ $TERM =~ ^screen.* ]]; then
        echo $@ # 不支持颜色的终端直接输出
    else
        case $color in # 支持颜色的终端使用颜色输出
        "red") printf "\033[31m%s\033[0m\n" "$@" ;;
        "sky_blue") printf "\033[1;36m%s\033[0m\n" "$@" ;;
        "green") printf "\033[32m%s\033[0m\n" "$@" ;;
        "white") printf "\033[37m%s\033[0m\n" "$@" ;;
        "magenta") printf "\033[31m%s\033[0m\n" "$@" ;;
        "yellow") printf "\033[33m%s\033[0m\n" "$@" ;;
        esac
    fi
}

# 检查当前用户是否为 root 用户
check_root() {
    [[ $(id -u) -eq 0 ]]
}

# 如果不是 root 用户，退出脚本
exit_if_not_root() {
    check_root || {
        echo "请用root权限运行此脚本" >&2
        exit 1
    }
}

# 检查依赖命令是否安装
check_depend() {
    # 需要检查的命令列表
    depends=("docker" "git")

    # 存储未找到的命令
    missing_depends=()

    # 检查每个命令是否存在
    for command in "${depends[@]}"; do
        command -v "$command" &>/dev/null || missing_depends+=("$command")
    done

    # 如果有命令未找到，则输出缺失的依赖信息并退出脚本
    if ((${#missing_depends[@]} > 0)); then
        echo_content red "缺少以下依赖:"
        printf -- '- %s\n' "${missing_depends[@]}"
        exit 1
    fi
}

#检查并安装脚本
check_v2board_directory() {
    V2BOARD_DIR="/usr/local/etc/v2board.sh"
    V2BOARD_SCRIPT="/usr/bin/v2board.sh"
    REPO_URL="https://github.com/9d84/v2board.sh"

    if [[ ! -d "$V2BOARD_DIR" ]]; then
        echo_content yellow "v2board.sh 目录不存在，正在进行安装..."
        mkdir -p $V2BOARD_DIR
        git clone "$REPO_URL" "$V2BOARD_DIR"
        ln -s "$V2BOARD_DIR/v2board.sh" "$V2BOARD_SCRIPT"
        echo_content green "快捷方式安装成功！输入 v2board.sh 即可进入脚本。"
    fi
}

#防止重复安装
check_env_file() {
    ENV_FILE="/usr/local/etc/v2board.sh/www/.env"

    if [[ -f "$ENV_FILE" ]]; then
        echo_content yellow "您已安装过v2board"
        echo_content yellow "如果需要重新安装的，请rm -rf /usr/local/etc/v2board.sh再重装"
        echo_content yellow "如果需要更新v2board,请在菜单中选择"
        exit 1
    fi
}

# 初始化设置
init() {
    cd $V2BOARD_DIR
    # 更新 git 子模块和重命名示例文件
    git submodule update --init
    git submodule update --remote
    find . -maxdepth 1 -type f -name "*.example" -exec bash -c 'newname="${1%.example}"; mv "$1" "$newname"' bash {} \;

    # 提示用户输入 mysql 密码
    mysql_password=$(get_user_input "请输入mysql密码（Enter生成随机密码）：")

    # 如果密码为空，则生成一个默认密码
    [[ -z $mysql_password ]] && mysql_password=$(openssl rand -base64 12)

    # 提示用户输入 mysql 数据库名称
    mysql_database=$(get_user_input "请输入 mysql 数据库名称（默认为 v2board）:")

    # 如果数据库名称为空，则设置为默认名称 v2board
    [[ -z $mysql_database ]] && mysql_database="v2board"

    # 更新 .env 文件中的 mysql 密码和数据库名称
    sed -i "s/MYSQL_ROOT_PASSWORD =.*/MYSQL_ROOT_PASSWORD = $mysql_password/" .env
    sed -i "s/MYSQL_DATABASE =.*/MYSQL_DATABASE = $mysql_database/" .env
}

# 获取用户输入
get_user_input() {
    read -p $'\e[95m'"$1"$'\e[0m' response
    echo "$response"
}

# 询问用户是否需要绑定域名
ask_domain_binding() {
    response=$(get_user_input "是否需要绑定域名？(y/N): ")
    response=$(echo "$response" | tr '[:upper:]' '[:lower:]')
    [[ $response == "y" ]]
}

# 询问用户要绑定的域名
ask_domain_name() {
    domain_name=$(get_user_input "请输入域名: ")
    domain_name=$(echo "$domain_name" | tr -d '[:space:]')
    echo "$domain_name"
}

# 替换文件中的文本
replace_text_in_file() {
    file_path="$1"
    old_text="$2"
    new_text="$3"
    sed -i "s|$old_text|$new_text|g" "$file_path"
}

# 替换caddy.conf中的域名
replace_domain_name() {
    bind_domain=false
    if ask_domain_binding; then
        bind_domain=true
        domain_name=$(ask_domain_name)
        replace_text_in_file "caddy.conf" ":80" "$domain_name"
    fi
}

# 提示用户输入邮箱地址，并将邮箱地址添加到 caddy.conf 文件
email() {
    email=$(get_user_input "请输入您的邮箱地址：")

    # 邮箱地址的正则表达式模式
    pattern="^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"

    # 检查输入的邮箱地址是否有效
    [[ $email =~ $pattern ]] || {
        echo_content red "请输入有效的邮箱地址"
        exit 1
    }

    # 将邮箱地址添加到 caddy.conf 文件
    sed -i "0,/{/ s/{/{\ntls ${email}/" caddy.conf
}

# 启动 v2board 相关服务
launch() {
    docker compose up -d

    docker compose exec www bash -c \
        'wget https://getcomposer.org/download/latest-stable/composer.phar && \
php composer.phar install'

    echo_content sky_blue "请在下方输入相关信息"
    echo "
数据库地址： mysql
数据库名: $mysql_database
数据库用户名: root
数据库密码: $mysql_password
"

    docker compose exec www php artisan v2board:install
    # 解决站点提示“队列服务运行异常的问题”
    cd $V2BOARD_DIR
    docker compose restart

    echo_content green "配置文件位于$V2BOARD_DIR"

}

# 更新 v2board
update_v2board() {
    echo "正在更新 v2board..."
    cd $V2BOARD_DIR
    git config --global --add safe.directory $V2BOARD_DIR/www
    git submodule update --remote
    docker compose exec www bash -c "
    wget https://github.com/composer/composer/releases/latest/download/composer.phar -O composer.phar && \
    php composer.phar update -vvv &&\
    php artisan v2board:update
    "
    echo_content green "v2board 更新完成！"
}

#更新脚本
update_script() {
    echo_content sky_blue "正在更新脚本..."
    wget -O "$V2BOARD_DIR/v2board.sh" "https://raw.githubusercontent.com/9d84/v2board.sh/master/v2board.sh"
    chmod +x "$V2BOARD_SCRIPT"
    echo_content green "脚本更新完成！"
}

# 主菜单
show_menu() {
    echo_content sky_blue "请选择要执行的操作:"
    echo "[1] 安装 v2board"
    echo "[2] 更新脚本"
    echo "[3] 更新 v2board"
    echo "[Q] 退出"
}

handle_error() {
    echo_content red "$1"
    exit 1 
}

# 主函数
main() {
    exit_if_not_root
    check_depend
    check_v2board_directory

    while true; do
        show_menu

        read -p "请选择操作: " choice

        case $choice in
        1)
            check_env_file
            init
            if ask_domain_binding; then
                replace_domain_name
                email
            fi
            launch
            ;;
        2)
            update_script
            ;;
        3)
            update_v2board
            ;;
        [Qq])
            break
            ;;
        *)
           handle_error "无效的选择,请重新输入."  # 错误处理
            ;;
        esac

        echo
    done
}


# 调用主函数
main
