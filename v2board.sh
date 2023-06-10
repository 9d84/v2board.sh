#!/bin/bash
#
# v2board.sh
# https://github.com/9d84/v2board.sh

# 检查当前用户是否为 root 用户
check_root() {
    [[ $(id -u) -eq 0 ]]
}

# 如果不是 root 用户，退出脚本
exit_if_not_root() {
    if ! check_root; then
        echo "请用root权限运行此脚本" >&2
        exit 1
    fi
}

check_depend() {

    # 需要检查的命令列表
    depends=("docker" "docker-compose" "git")

    # 用于存储未找到的命令
    missing_depends=()

    # 检查每个命令是否存在
    for command in "${depends[@]}"; do
        if ! command -v "$command" &>/dev/null; then
            missing_depends+=("$command")
        fi
    done

    # 判断是否有命令未找到
    if [ ${#missing_depends[@]} -gt 0 ]; then
        echo "缺少以下依赖:"
        for missing_command in "${missing_depends[@]}"; do
            echo "- $missing_command"
        done
        exit 1
    fi
}

###
# 获取设置
###
init() {
    # 设置颜色
    color="\033[38;5;206m"
    reset_color="\033[0m"

    git submodule update --init
    git submodule update --remote
    
    cp .env.example .env

    # 提示用户输入mysql密码
    echo -e "${color}请输入mysql密码（按Enter键生成默认密码）:${reset_color}"
    read -r mysql_password

    # 如果密码为空，则生成一个16位的默认密码
    if [ -z "$mysql_password" ]; then
        mysql_password=$(openssl rand -base64 12)
    fi

    # 提示用户输入mysql数据库名称
    echo -e "${color}请输入mysql数据库名称（默认v2board）:${reset_color}"
    read -r mysql_database

    # 如果数据库名称为空，则设置为默认名称v2board
    if [ -z "$mysql_database" ]; then
        mysql_database="v2board"
    fi

    # 更新.env文件
    sed -i "s/MYSQL_ROOT_PASSWORD =.*/MYSQL_ROOT_PASSWORD = $mysql_password/" .env
    sed -i "s/MYSQL_DATABASE =.*/MYSQL_DATABASE = $mysql_database/" .env
}

###
#启动v2board相关服务
# TODO：脚本自动输入
###
launch() {
    docker-compose up -d

    docker-compose exec www bash -c \
        'wget https://getcomposer.org/download/latest-stable/composer.phar && \
php composer.phar install'

    echo 请在下方输入相关信息
    echo -e "
数据库地址： mysql
数据库名: $mysql_database
数据库用户名: root
数据库密码: $mysql_password
"

    docker-compose exec www php artisan v2board:install
}

exit_if_not_root
check_depend
init
launch
