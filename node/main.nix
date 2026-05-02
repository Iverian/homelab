{
  config,
  lib,
  pkgs,
  ...
}:

{
  imports = [
    ./hardware-configuration.nix
    ./disko-config.nix
    # Kubernetes services
    ./k8s/storage.nix
    ./k8s/metallb.nix
    ./k8s/samba-operator.nix
    ./k8s/tailscale-operator.nix
    ./k8s/postgres-operator.nix
    ./k8s/ingress.nix
    ./k8s/reloader.nix
    ./k8s/cert-manager.nix
    ./k8s/authelia.nix
    ./k8s/prometheus-stack.nix
    ./k8s/syncthing.nix
    ./k8s/intel-nfd.nix
    ./k8s/gitea.nix
    ./k8s/media.nix
  ];

  sops = {
    age.keyFile = "/etc/nixos/secrets/sops.key";
    defaultSopsFile = ../main.sops.yaml;
  };

  zramSwap = {
    enable = false;
    memoryPercent = 25;
  };
  swapDevices = [
    {
      device = "/var/lib/swapfile";
      size = 32 * 1024; # 16 GiB
    }
  ];

  boot.supportedFilesystems = [ "zfs" ];
  boot.initrd.kernelModules = [ "usb_storage" ];
  boot.kernelPackages = pkgs.linuxPackages_hardened;
  boot.kernelModules = [ "tcp_bbr" ];
  boot.kernelParams = [
    "fsck.mode=force"
    "i915.enable_fbc=1"
    "i915.fastboot=1"
    "i915.i915_enable_rc6=1"
    "tsc=reliable"
    "clocksource=tsc"
  ];
  boot.kernel.sysctl = {
    # "vm.swappiness" = 10;
    "vm.overcommit_ratio" = 90;
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
    "kernel.unprivileged_userns_clone" = 1;
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
    hostId = "73961218";
    hostName = "homelab";
    firewall.enable = false;
    networkmanager.enable = true;
  };

  time.timeZone = "Europe/Moscow";

  i18n.extraLocales = [
    "ru_RU.UTF-8/UTF-8"
    "en_US.UTF-8/UTF-8"
  ];
  i18n.defaultLocale = "ru_RU.UTF-8";
  console.packages = [ pkgs.terminus_font ];
  console = {
    font = "${pkgs.terminus_font}/share/consolefonts/ter-c16b.psf.gz";
    keyMap = "us";
    useXkbConfig = false;
  };

  security.sudo.wheelNeedsPassword = false;
  users.users.iverian = {
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHjkkb347RY92RYbf+by2uDrDMTVK9FjWL9GNMaQOnDr"
    ];

    isNormalUser = true;
    extraGroups = [ "wheel" ];
    initialPassword = "changeme";
    shell = pkgs.bash;
    packages = with pkgs; [ ];
  };

  services.smartd = {
    enable = true;
    devices = [
      {
        device = "/dev/disk/by-id/nvme-Samsung_SSD_970_EVO_Plus_250GB_S4EUNX0R704715T";
      }
      {
        device = "/dev/disk/by-id/ata-WDC_WD40EFAX-68JH4N1_WD-WX72D71NL0SD";
      }
      {
        device = "/dev/disk/by-id/ata-WDC_WD20EFZX-68AWUN0_WD-WX12D4136UV7";
      }
      {
        device = "/dev/disk/by-id/ata-WDC_WD20EFZX-68AWUN0_WD-WX12D41367TU";
      }
      {
        device = "/dev/disk/by-id/ata-WDC_WD40EFAX-68JH4N1_WD-WX72D71NLF63";
      }
    ];
  };

  systemd.services.zfs-load-keys = {
    enable = true;
    after = [
      "systemd-udev-settle.service"
      "systemd-modules-load.service"
      "systemd-ask-password-console.service"
    ];
    before = [ "zfs-import-zdata.service" ];
    wantedBy = [ "zfs-import-zdata.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = "yes";
      ExecStart = "/run/current-system/sw/bin/zfs load-key -a";
    };
  };

  environment.systemPackages = with pkgs; [
    neovim
    curl
    htop
    iotop
    iftop
    usbutils
  ];

  services.irqbalance.enable = true;

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
    };
  };

  services.avahi = {
    enable = true;
    nssmdns4 = true;
    openFirewall = true;
    allowInterfaces = [
      "lo"
      "enp3s0"
    ];
    publish = {
      enable = true;
      addresses = true;
    };
    extraServiceFiles = {
      ssh = "${pkgs.avahi}/etc/avahi/services/ssh.service";
    };
  };

  services.k3s = {
    enable = true;
    role = "server";
  };

  services.xserver.videoDrivers = [ "i915" ];

  # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  system.stateVersion = "25.11";
}
