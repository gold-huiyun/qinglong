Alpine 直接安装一键脚本（带国内镜像优化）
适用 Alpine 3.18+，整合新版 Dockerfile 的依赖与结构
情景：你现在就是在一台 Alpine 主机上，直接安装并运行青龙，不用 Docker。
#注意相关命令：
```bash
 apk add bash sudo
```

```bash
wget https://raw.githubusercontent.com/gold-huiyun/qinglong/refs/heads/master/linuxdp/install_qinglong_alpine.sh
```
保存为：install_qinglong_alpine.sh
用法：sudo sh install_qinglong_alpine.sh 或 bash install_qinglong_alpine.sh
（默认使用 develop 分支，若需 master：QL_BRANCH=master bash install_qinglong_alpine.sh）

```bash
wget https://gh-proxy.com/https://raw.githubusercontent.com/gold-huiyun/qinglong/refs/heads/master/linuxdp/cninstall_qinglong_alpine.sh
```

保存为：cninstall_qinglong_alpine.sh
用法：sudo sh cninstall_qinglong_alpine.sh 或 bash cninstall_qinglong_alpine.sh
默认使用 master分支，若需 其他：QL_BRANCH=其他 bash cninstall_qinglong_alpine.sh

#系统重启后青龙启动脚本
bash /ql/docker/docker-entrypoint.sh


Linuxdeploy 自启动，设置勾选初始化，初始化勾选异步，创建 "/etc/rc.local"，(注意赋予执行权限 chmod +x rc.local)rc.local写入以下内容
```bash
#!/bin/sh -e
#
# rc.local
#
# This script is executed at the end of each multiuser runlevel.
# Make sure that the script will "exit 0" on success or any other
# value on error.
#
# In order to enable or disable this script just change the execution
# bits.
#
# By default this script does nothing.
#青龙启动脚本
bash /ql/docker/docker-entrypoint.sh

exit 0
```
