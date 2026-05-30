# -*- mode: ruby -*-
# vi: set ft=ruby :

Vagrant.configure("2") do |config|
  config.vm.box = "almalinux/9"
  
  # =========================================================================
  # 1. Server A: Control Node (司令塔)
  # =========================================================================
  config.vm.define "server-a" do |node|
    node.vm.network "private_network", ip: "10.149.245.110"
    # ✨ SSHポートを 2222番に固定
    node.vm.network "forwarded_port", guest: 22, host: 2222, id: "ssh", auto_correct: true
    node.vm.hostname = "server-a"
    node.vm.provider "virtualbox" do |vb|
      vb.memory = "2048"
      vb.cpus = 1
      vb.name = "server-a-ctrl"
      vb.customize ["modifyvm", :id, "--groups", "/GraduationProject"]
    end
  end

  # =========================================================================
  # 2. Server B: App/DB Node (実行環境 / Docker Webサーバー)
  # =========================================================================
  config.vm.define "server-b" do |node|
    node.vm.network "private_network", ip: "10.149.245.115"
    # ✨ SSHポートの衝突を防ぐため、明示的に 2200番に分離
    node.vm.network "forwarded_port", guest: 22, host: 2200, id: "ssh", auto_correct: true
    node.vm.network "forwarded_port", guest: 80, host: 8080, id: "nginx"
    node.vm.hostname = "server-b"
    node.vm.provider "virtualbox" do |vb|
      vb.memory = "2048"
      vb.cpus = 2  
      vb.name = "server-b-app"
      vb.customize ["modifyvm", :id, "--groups", "/GraduationProject"]
    end
  end

  # =========================================================================
  # 3. Server C: Monitor Node (監視・通知 / Prometheus, Grafana, NOC-Bot)
  # =========================================================================
  config.vm.define "server-c" do |node|
    node.vm.network "private_network", ip: "10.149.245.116"
    # ✨ SSHポートの衝突を防ぐため、明示的に 2201番に分離
    node.vm.network "forwarded_port", guest: 22, host: 2201, id: "ssh", auto_correct: true
    node.vm.network "forwarded_port", guest: 3000, host: 3000, id: "grafana"
    node.vm.hostname = "server-c"
    node.vm.provider "virtualbox" do |vb|
      vb.memory = "2048"
      vb.cpus = 1
      vb.name = "server-c-mon"
      vb.customize ["modifyvm", :id, "--groups", "/GraduationProject"]
    end
  end

  config.vm.boot_timeout = 600
end