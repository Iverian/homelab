{
  config,
  lib,
  pkgs,
  ...
}:

{
  sops = {
    age.keyFile = "/etc/nixos/secrets/sops.key";
    defaultSopsFile = ../main.sops.yaml;
    secrets = {
      frpToken = { };
      frpCaCert = { };
      frpServerCert = { };
      frpServerKey = { };
    };
    templates.frpToken = {
      content = config.sops.placeholder.frpToken;
      path = "/etc/frp/token";
    };
    templates.frpCaCert = {
      content = config.sops.placeholder.frpCaCert;
      path = "/etc/frp/ca.pem";
    };
    templates.frpServerCert = {
      content = config.sops.placeholder.frpServerCert;
      path = "/etc/frp/server-cert.pem";
    };
    templates.frpServerKey = {
      content = config.sops.placeholder.frpServerKey;
      path = "/etc/frp/server-key.pem";
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
  # copy.fail mitigation, until we're on a kernel that has it patched
  boot.extraModprobeConfig = "install algif_aead /bin/false";
  boot.growPartition = true;
  boot.kernelParams = [ "console=tty1" ];
  boot.loader.grub.device = "/dev/sda";
  boot.loader.grub.efiSupport = false;
  boot.loader.grub.efiInstallAsRemovable = false;
  boot.loader.timeout = 1;
  boot.loader.grub.extraConfig = ''
    serial --unit=1 --speed=115200 --word=8 --parity=no --stop=1
    terminal_output console serial
    terminal_input console serial
  '';

  fileSystems = {
    "/" = {
      device = "/dev/disk/by-label/nixos";
      fsType = "ext4";
      options = [
        "x-systemd.growfs"
        "x-initrd.mount"
      ];
    };
  };

  networking = {
    hostName = "homelab-external";
    firewall.enable = true;
    networkmanager.enable = true;
  };

  time.timeZone = "Europe/Moscow";
  i18n.extraLocales = [
    "ru_RU.UTF-8/UTF-8"
    "en_US.UTF-8/UTF-8"
  ];

  security.sudo.wheelNeedsPassword = false;
  users.users.iverian = {
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHjkkb347RY92RYbf+by2uDrDMTVK9FjWL9GNMaQOnDr"
    ];

    isNormalUser = true;
    extraGroups = [ "wheel" ];
    hashedPassword = "$y$j9T$jyEOKc4Wge0pxD4edKum7/$1n9kBlWL65Rm1Zw4Oev85s3PQzXunxFPFd4GE60Uyf0";
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

  systemd.services."serial-getty@tty1".enable = true;

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
    };
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
      enablePrometheus = false;
      transport.tls.force = true;
      transport.tls.certFile = "/etc/frp/server-cert.pem";
      transport.tls.keyFile = "/etc/frp/server-key.pem";
      transport.tls.trustedCaFile = "/etc/frp/ca.pem";
    };
  };

  # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  system.stateVersion = "25.11";
}
