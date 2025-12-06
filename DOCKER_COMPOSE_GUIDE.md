# JumpServer 官方 Docker Compose 使用自定义镜像说明

## 🔍 问题分析

如果您遇到 `405 Not Allowed` 或 API 无法访问的问题，说明：
- ✅ 后端服务正常运行
- ✅ 前端页面可以访问
- ❌ **nginx 网关配置有问题**

## 📋 官方架构说明

JumpServer 官方 docker-compose 部署架构：

```
外部访问 (http://your-ip)
    ↓
nginx 网关容器 (jms_nginx)  ← 这是统一入口，监听 80/443 端口
    ↓
├─→ /ui/          → web 容器 (jms_web)     ← 您自定义的前端镜像
├─→ /api/         → core 容器 (jms_core)   ← 后端 API
├─→ /koko/        → koko 容器 (jms_koko)   ← SSH/Telnet
├─→ /lion/        → lion 容器 (jms_lion)   ← RDP/VNC
└─→ /media/       → core 容器

重要：web 容器内的 nginx 只负责提供静态文件，不对外暴露端口！
```

## ✅ 正确的使用步骤

### 1. 修改 docker-compose.yml

找到 web 服务配置：

```yaml
services:
  web:
    # 使用您自己的镜像
    image: registry.cn-shanghai.aliyuncs.com/zywdockers/jmp-web:latest
    container_name: jms_web
    restart: always
    tty: true
    depends_on:
      - core
    # 注意：web 容器不需要对外暴露 80 端口！
    # ports:
    #   - "80:80"  # ❌ 删除或注释这行
    volumes:
      - static:/opt/jumpserver/data/static
      - lina:/opt/lina
    networks:
      - jumpserver

  # nginx 网关容器配置
  nginx:
    image: jumpserver/nginx:latest  # 使用官方 nginx 镜像
    container_name: jms_nginx
    restart: always
    ports:
      - "80:80"      # ✅ 只有 nginx 网关对外暴露端口
      - "443:443"
    volumes:
      - static:/opt/jumpserver/data/static
      - lina:/opt/lina
      # nginx 配置文件（官方提供）
      - ./config/nginx/nginx.conf:/etc/nginx/nginx.conf
    depends_on:
      - core
      - web
      - koko
    networks:
      - jumpserver
```

### 2. 检查 nginx 网关配置

确保官方的 nginx 网关配置文件 `config/nginx/nginx.conf` 包含类似这样的配置：

```nginx
upstream web {
    server web:80;  # 指向 web 容器
}

upstream core {
    server core:8080;  # 指向 core 容器
}

server {
    listen 80;
    
    # 前端静态文件
    location /ui/ {
        proxy_pass http://web;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
    
    # API 请求
    location /api/ {
        proxy_pass http://core;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
    
    # 其他路径...
}
```

### 3. 重启服务

```bash
# 停止所有服务
docker-compose down

# 拉取最新的自定义镜像
docker pull registry.cn-shanghai.aliyuncs.com/zywdockers/jmp-web:latest

# 启动所有服务
docker-compose up -d

# 查看服务状态
docker-compose ps
```

## 🔍 故障排查

### 检查容器状态

```bash
# 查看所有容器
docker-compose ps

# 应该看到类似这样的输出：
# jms_nginx    running   0.0.0.0:80->80/tcp    ← nginx 网关
# jms_web      running                         ← web 容器（无端口暴露）
# jms_core     running                         ← core 容器
# jms_koko     running                         ← koko 容器
```

### 检查 nginx 网关日志

```bash
# 查看 nginx 网关日志
docker logs jms_nginx

# 查看 web 容器日志
docker logs jms_web

# 查看 core 容器日志
docker logs jms_core
```

### 测试网络连通性

```bash
# 从 nginx 容器测试访问 web 容器
docker exec jms_nginx curl http://web/ui/

# 从 nginx 容器测试访问 core 容器
docker exec jms_nginx curl http://core:8080/api/health/

# 从 web 容器测试本地 nginx
docker exec jms_web curl http://localhost/ui/
```

### 检查端口占用

```bash
# 确保 80 端口没有被其他服务占用
netstat -tlnp | grep :80
# 或
ss -tlnp | grep :80

# 应该只有 nginx 网关容器占用
```

## ❌ 常见错误

### 错误 1: web 容器直接暴露 80 端口

```yaml
# ❌ 错误配置
services:
  web:
    image: registry.cn-shanghai.aliyuncs.com/zywdockers/jmp-web:latest
    ports:
      - "80:80"  # 这会导致冲突！
```

**问题**: web 容器和 nginx 网关都监听 80 端口，产生冲突。

**解决**: 删除 web 服务中的 `ports` 配置。

### 错误 2: 缺少 nginx 网关容器

```yaml
# ❌ 只有 web 和 core，没有 nginx 网关
services:
  web:
    ...
  core:
    ...
  # 缺少 nginx 网关！
```

**问题**: 没有统一入口整合前后端请求。

**解决**: 添加官方的 nginx 网关容器配置。

### 错误 3: 网络配置错误

```yaml
# ❌ 容器不在同一网络
services:
  web:
    networks:
      - frontend
  core:
    networks:
      - backend  # 不同网络，无法通信
```

**问题**: 容器之间无法通信。

**解决**: 确保所有容器在同一个 Docker 网络中。

## 📝 完整配置示例

```yaml
version: '3'

networks:
  jumpserver:
    driver: bridge

volumes:
  static:
  lina:

services:
  core:
    image: jumpserver/core:v4.10.13
    container_name: jms_core
    restart: always
    environment:
      # 环境变量配置...
    networks:
      - jumpserver

  web:
    image: registry.cn-shanghai.aliyuncs.com/zywdockers/jmp-web:latest
    container_name: jms_web
    restart: always
    depends_on:
      - core
    volumes:
      - static:/opt/jumpserver/data/static
      - lina:/opt/lina
    networks:
      - jumpserver

  nginx:
    image: jumpserver/nginx:latest
    container_name: jms_nginx
    restart: always
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - static:/opt/jumpserver/data/static
      - lina:/opt/lina
    depends_on:
      - core
      - web
    networks:
      - jumpserver
```

## ✅ 验证部署成功

访问 `http://your-server-ip/`，应该能看到：
- ✅ 登录页面正常显示（中文界面）
- ✅ 可以正常登录
- ✅ API 请求正常（无 405 错误）
- ✅ 所有功能正常使用

## 🎯 总结

关键点：
1. **web 容器**：只提供静态文件，不对外暴露端口
2. **nginx 网关**：统一入口，负责路由所有请求
3. **网络配置**：所有容器在同一 Docker 网络
4. **端口暴露**：只有 nginx 网关暴露 80/443 端口

