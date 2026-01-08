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
  ];

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

  # ZFS
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

  services.openssh.enable = true;
  services.k3s.enable = true;
  services.k3s.role = "server";

  system.stateVersion = "25.11";
}
