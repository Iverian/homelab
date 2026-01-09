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
    ./k8s/ingress.nix
    ./k8s/reloader.nix
    ./k8s/tailscale-operator.nix
    ./k8s/cert-manager.nix
    ./k8s/postgres-operator.nix
    ./k8s/authelia.nix
    ./k8s/prometheus-stack.nix
    ./k8s/media.nix
  ];

  sops.age.keyFile = "/etc/nixos/sops.key";
  sops.defaultSopsFile = ../main.sops.yaml;

  zramSwap.enable = true;
  zramSwap.memoryPercent = 25;

  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.editor = false;
  boot.loader.systemd-boot.configurationLimit = 3;

  networking.hostId = "73961218";
  networking.hostName = "homelab";
  networking.firewall.enable = false;
  networking.networkmanager.enable = true;

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

  boot.supportedFilesystems = [ "zfs" ];
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
  ];

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
  };
  services.k3s.enable = true;
  services.k3s.role = "server";

  # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  system.stateVersion = "25.11";
}
