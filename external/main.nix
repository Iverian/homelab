{
  config,
  lib,
  pkgs,
  ...
}:

{
  sops = {
    defaultSopsFile = ../main.sops.yaml;
    secrets = {
      externalPassword.neededForUsers = true;
      frpToken = { };
    };
    templates.frpsToken = {
      content = config.sops.placeholder.frpToken;
      path = "/etc/frp/token";
    };
  };

  boot.kernelPackages = pkgs.linuxPackages_hardened;
  boot.kernelModules = [ "tcp_bbr" ];
  boot.kernel.sysctl = {
    "net.core.somaxconn" = 65536;
    "net.core.netdev_max_backlog" = 16384;
    "net.ipv4.ip_local_port_range" = "10000 65499";
    "net.ipv4.tcp_fastopen" = 3;
    "net.ipv4.tcp_max_syn_backlog" = 8192;
    "net.ipv4.tcp_max_tw_buckets" = 2000000;
    "net.ipv4.tcp_tw_reuse" = 1;
    "net.ipv4.tcp_fin_timeout" = 10;
    "net.ipv4.tcp_slow_start_after_idle" = 0;
    "net.ipv4.tcp_keepalive_time" = 60;
    "net.ipv4.tcp_keepalive_intvl" = 10;
    "net.ipv4.tcp_keepalive_probes" = 6;
    "net.ipv4.tcp_mtu_probing" = 1;
    "net.core.default_qdisc" = "cake";
    "net.ipv4.tcp_congestion_control" = "bbr";
    "net.ipv4.ip_forward" = 1;
    "net.ipv6.conf.all.forwarding" = 1;
  };
  boot.loader = {
    efi.canTouchEfiVariables = true;
    systemd-boot = {
      enable = true;
      editor = false;
      configurationLimit = 3;
    };
  };
  networking = {
    hostName = "homelab-external";
    firewall.enable = false;
    networkmanager.enable = true;
  };

  time.timeZone = "Europe/Moscow";
  i18n.extraLocales = [
    "ru_RU.UTF-8/UTF-8"
    "en_US.UTF-8/UTF-8"
  ];

  users.users.iverian = {
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHjkkb347RY92RYbf+by2uDrDMTVK9FjWL9GNMaQOnDr"
    ];

    isNormalUser = true;
    extraGroups = [ "wheel" ];
    hashedPasswordFile = config.sops.secrets.externalPassword.path;
    shell = pkgs.bash;
    packages = with pkgs; [ ];
  };

  environment.systemPackages = with pkgs; [
    neovim
    curl
    htop
    iotop
    iftop
  ];

  services.openssh = {
    enable = true;
  };

  services.frp = {
    enable = true;
    role = "server";
    settings = {
      auth = {
        method = "token";
        tokenSource = {
          type = "file";
          file.path = "/etc/frp/token";
        };
      };
      bindPort = 7000;
      vhostHTTPPort = 80;
      vhostHTTPSPort = 443;
    };
  };

  # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  system.stateVersion = "25.11";
}
