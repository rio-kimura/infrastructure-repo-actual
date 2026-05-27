#!/bin/bash
set -e

INIT_PASS="vagrant"
INVENTORY="inventories/vagrant/hosts.ini"
VAULT_SOURCE=".vault_password"
VAULT_DEST="$HOME/.vault_password"
PUB_KEY="$HOME/.ssh/id_rsa.pub"

echo "=== [1/5] OSパッケージ・sshpass の導入 ==="
sudo dnf install -y epel-release
sudo dnf install -y ansible-core git sshpass

echo "=== [2/5] 依存コレクションの一括導入 ==="
ansible-galaxy collection install ansible.posix community.docker community.general

echo "=== [3/5] 司令塔用 SSHキーペアの生成 ==="
if [ ! -f "$HOME/.ssh/id_rsa" ]; then
    ssh-keygen -t rsa -b 4096 -N "" -f "$HOME/.ssh/id_rsa"
    echo "✔ SSH鍵を新規作成しました。"
else
    echo "✔ SSH鍵は既に存在します。"
fi

echo "=== [4/5] Ansible Vault パスワードファイルのセキュア隔離 ==="
if [ -f "$VAULT_SOURCE" ]; then
    cp "$VAULT_SOURCE" "$VAULT_DEST"
    chmod 600 "$VAULT_DEST"
    echo "✔ Vaultパスワードの権限正常化(600)を完了しました。"
else
    echo "❌ エラー: $VAULT_SOURCE が存在しません。"
    exit 1
fi

echo "=== [5/5] sshpass による公開鍵の全台フルオート配布 ==="
export ANSIBLE_HOST_KEY_CHECKING=False
SSHPASS=$INIT_PASS ansible all -i "$INVENTORY" \
  -m ansible.posix.authorized_key \
  -a "user=vagrant state=present key='{{ lookup('file', '$PUB_KEY') }}'" \
  -c ssh --extra-vars "ansible_password=$INIT_PASS ansible_port=22" \
  -k

echo "================================================================="
echo " 🎉 鍵配布完了！初期ポート(22番)での通信テストを開始します。"
echo "================================================================="
ansible all -i "$INVENTORY" -m ping --extra-vars "ansible_port=22"
