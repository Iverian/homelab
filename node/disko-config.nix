{
  disko.devices = {
    disk = {
      main = {
        type = "disk";
        device = "/dev/disk/by-id/nvme-Samsung_SSD_970_EVO_Plus_250GB_S4EUNX0R704715T";
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              size = "1G";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [ "umask=0077" ];
              };
            };
            luks = {
              size = "100%";
              content = {
                type = "luks";
                name = "root";
                settings = {
                  keyFile = "/dev/disk/by-id/usb-Gembird_GFL-2.0-8mini_7835531142426188517-0:0";
                  keyFileSize = 4096;
                  allowDiscards = true;
                };
                content = {
                  type = "filesystem";
                  format = "ext4";
                  mountpoint = "/";
                };
              };
            };
          };
        };
      };
      data1 = {
        type = "disk";
        device = "/dev/disk/by-id/ata-WDC_WD40EFAX-68JH4N1_WD-WX72D71NL0SD";
        content = {
          type = "gpt";
          partitions = {
            zfs = {
              size = "100%";
              content = {
                type = "zfs";
                pool = "zdata";
              };
            };
          };
        };
      };
      data2 = {
        type = "disk";
        device = "/dev/disk/by-id/ata-WDC_WD20EFZX-68AWUN0_WD-WX12D4136UV7";
        content = {
          type = "gpt";
          partitions = {
            zfs = {
              size = "100%";
              content = {
                type = "zfs";
                pool = "zdata";
              };
            };
          };
        };
      };
      data3 = {
        type = "disk";
        device = "/dev/disk/by-id/ata-WDC_WD20EFZX-68AWUN0_WD-WX12D41367TU";
        content = {
          type = "gpt";
          partitions = {
            zfs = {
              size = "100%";
              content = {
                type = "zfs";
                pool = "zdata";
              };
            };
          };
        };
      };
      data4 = {
        type = "disk";
        device = "/dev/disk/by-id/ata-WDC_WD40EFAX-68JH4N1_WD-WX72D71NLF63";
        content = {
          type = "gpt";
          partitions = {
            zfs = {
              size = "100%";
              content = {
                type = "zfs";
                pool = "zdata";
              };
            };
          };
        };
      };
    };
    zpool = {
      zdata = {
        type = "zpool";
        rootFsOptions = {
          encryption = "on";
          keyformat = "raw";
          keylocation = "file:///etc/nixos/secrets/zfs.key";
          mountpoint = "none";
          compression = "zstd";
          acltype = "posixacl";
          xattr = "sa";
          atime = "on";
          relatime = "on";
          "com.sun:auto-snapshot" = "true";
        };
        options = {
          ashift = "12";
          "feature@encryption" = "enabled";
        };
        mode = {
          topology = {
            type = "topology";
            vdev = [
              {
                mode = "mirror";
                members = [
                  "data1"
                  "data4"
                ];
              }
              {
                mode = "mirror";
                members = [
                  "data2"
                  "data3"
                ];
              }
            ];
          };
        };
        datasets = {
          "data" = {
            type = "zfs_fs";
            mountpoint = "/data/hdd";
            options = {
              compression = "zstd";
            };
          };
        };
      };
    };
  };
}
