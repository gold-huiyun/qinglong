# Termux 安装 Alpine 

## ✅ ：用 `proot-distro` 官方安装 Alpine（最稳）

Termux 官方的 `proot-distro` 会用更稳的配置与更新的 `proot`/`proot-rs`，避免这些触发脚本错误。

### 步骤：

1. **更新 Termux 包：**
   ```bash
   pkg up -y
   ```

2. **安装并用 `proot-distro` 部署 Alpine：**
   ```bash
   pkg install -y proot-distro
   proot-distro install alpine
   proot-distro login alpine
   ```

3. **进入后再试：**
   ```bash
   apk update
   apk add bash
   ```

---

